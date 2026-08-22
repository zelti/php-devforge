# nginx configuration, via OpenResty.
#
# OpenResty, not plain nginx: the document root and the PHP backend are derived
# from the host name in Lua, which stock nginx cannot do. Swapping the base image
# for nginx:alpine will not work.
#
# ${DEV_DOMAIN} and ${PHP_VERSION} are substituted by envsubst at container start.

gzip on;
gzip_buffers 16 8k;
gzip_comp_level 5;
gzip_disable "msie6";
gzip_min_length 1000;
gzip_http_version 1.0;
gzip_proxied any;
gzip_types text/plain application/javascript application/x-javascript text/javascript text/xml text/css image/svg+xml;
gzip_vary on;

# The backend used to be picked by a map listing every version, which meant editing
# this file to add one. resolve_docroot.lua sets it from the host instead.

# Mail catcher UI. nginx prefers an exact server_name over a regex one regardless
# of order, so this wins over the wildcard below without needing a load-order trick
# the way Apache does.
server {
    listen 80;
    listen 443 ssl;
    http2 on;
    server_name mail.${DEV_DOMAIN};
    ssl_certificate     /etc/nginx/ssl/php-devforge.pem;
    ssl_certificate_key /etc/nginx/ssl/php-devforge.key;
    location / {
        resolver 127.0.0.11 ipv6=off valid=10s;
        set $mail "mailpit:8025";
        proxy_pass http://$mail;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name ~^(?<subdomains>.+)\.${DEV_DOMAIN}$;
    include /etc/nginx/snippets/common_server_config.conf;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ~^(?<subdomains>.+)\.${DEV_DOMAIN}$;
    ssl_certificate     /etc/nginx/ssl/php-devforge.pem;
    ssl_certificate_key /etc/nginx/ssl/php-devforge.key;
    include /etc/nginx/snippets/common_server_config.conf;
}
