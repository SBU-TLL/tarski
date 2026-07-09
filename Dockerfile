# syntax=docker/dockerfile:1
###############################################################################
# Production image — tarski ("Tarski's Truth Machine", A-Frame/WebXR experience)
#
# Tech stack : fully static client-side A-Frame / WebXR app. index.html (+
#              index2.html, super.html, viewer/) load jQuery + A-Frame and its
#              components from public CDNs, plus local JS (script.js, logic.js,
#              grab.js, aabb-collider.js, progressive-controls.js, ...) and level
#              data in .txt files. NO PHP, no .htaccess, no server-side code, no
#              database, no auth.
# Web server : Apache (php:8.3-apache) — consistent with the fleet; serves the
#              static assets. (This app is also trivially static-hostable / CDN.)
#
# Authentication: NONE. Public static experience. Gate at the ingress if ever
#   needed. No secrets, no DB (see .env.production.example).
#
# WebXR note: entering VR requires a SECURE CONTEXT (HTTPS). The container serves
# plain HTTP on 8080; the ingress / reverse proxy terminates TLS (443 -> 8080),
# which satisfies the secure-context requirement in production.
#
# Runs non-root (www-data) on unprivileged port 8080.
###############################################################################
FROM php:8.3-apache

# --- Apache modules (headers for parity; no .htaccess/rewrites in this app) ---
RUN set -eux; \
    a2enmod headers

# --- Run as a non-root user on an unprivileged port (8080) ---
RUN set -eux; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    sed -ri 's/:80>/:8080>/' /etc/apache2/sites-available/000-default.conf

# --- Security hardening (suppress server tokens/signature, TRACE, ETag) ---
RUN set -eux; \
    { \
      echo 'ServerTokens Prod'; \
      echo 'ServerSignature Off'; \
      echo 'TraceEnable Off'; \
      echo 'FileETag None'; \
    } > /etc/apache2/conf-available/zzz-hardening.conf; \
    a2enconf zzz-hardening

# --- Docroot policy: no dir listing, parse .htaccess if any, log to
#     stdout/stderr for container log capture ---
RUN set -eux; \
    { \
      echo '<Directory /var/www/html>'; \
      echo '    Options -Indexes +FollowSymLinks'; \
      echo '    AllowOverride All'; \
      echo '    Require all granted'; \
      echo '</Directory>'; \
      echo 'ErrorLog /dev/stderr'; \
      echo 'CustomLog /dev/stdout combined'; \
    } > /etc/apache2/conf-available/zzz-docroot.conf; \
    a2enconf zzz-docroot

# --- Application code. .dockerignore excludes .ddev/, .git/, .env*, Dockerfile,
#     the stale unused local aframe*.js copies (~2.2MB; the app loads A-Frame
#     from the CDN), docs, editor config and OS junk. ---
COPY --chown=www-data:www-data . /var/www/html/

# --- Permissions: read-only static tree owned by www-data ---
RUN set -eux; \
    find /var/www/html -type d -exec chmod 0755 {} +; \
    find /var/www/html -type f -exec chmod 0644 {} +; \
    chown -R www-data:www-data /var/run/apache2 /var/log/apache2 /var/lock; \
    chmod -R g=u /var/run/apache2 /var/log/apache2 /var/lock

USER www-data
EXPOSE 8080

# php:apache base CMD = apache2-foreground
