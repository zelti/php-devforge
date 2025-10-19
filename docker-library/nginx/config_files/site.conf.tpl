# ======================
# Nginx configuration
# ======================
# This configuration uses environment variables from Docker (.env file):
#   - $DEV_DOMAIN   : sets the base development domain (e.g., phpbox.dev)
#   - $PHP_VERSION   : sets the default PHP version (e.g., 83 or 84)
# These variables are replaced at container startup via `envsubst`:
#   envsubst '$DEV_DOMAIN $PHP_VERSION' < site.conf.tpl > /etc/nginx/conf.d/site.conf
# ==============================================================================

gzip on;
gzip_buffers 16 8k;
gzip_comp_level 5;
gzip_disable "msie6";
gzip_min_length 1000;
gzip_http_version 1.0;
gzip_proxied any;
gzip_types text/plain application/javascript application/x-javascript text/javascript text/xml text/css image/svg+xml;
gzip_vary on;


# Map to decide PHP backend based on hostname
map $host $php_backend {
    "~--p83\.${DEV_DOMAIN}$" "php83dev";
    "~--p84\.${DEV_DOMAIN}$" "php84dev";
    default "php${PHP_VERSION}";
}

# ======================
# HTTP - port 80
# ======================
server {
    listen 80;
    server_name ~^(?<subdomains>.+)\.${DEV_DOMAIN}$;
    include /etc/nginx/snippets/common_server_config.conf;
}
# ======================
# HTTPS - port 443
# ======================
server {
    listen 443 ssl;
    server_name ~^(?<subdomains>.+)\.${DEV_DOMAIN}$;
    ssl_certificate     /etc/nginx/ssl/php-devbox.pem;  # certificate
    ssl_certificate_key /etc/nginx/ssl/php-devbox.key;  # private key
    include /etc/nginx/snippets/common_server_config.conf;
}

