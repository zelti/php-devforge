set $dev_domain "${DEV_DOMAIN}"; 
set $php_version "${PHP_VERSION}"; 

# Inicializa y llama al script Lua
set $docroot "UNDEFINED"; 
rewrite_by_lua_file /etc/nginx/lua/resolve_docroot.lua; 

root $docroot;
index index.php index.html;

# Deny access to hidden .php files
location ~ /\.ph(p[345]?|t|tml|ps)$ {
    deny all;
}

# Main location
location / {
    try_files $uri $uri/ =404;
}

# Dynamic PHP-FPM with Authorization headers
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass $php_backend:9000;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}

# Websockets
location /ws {
        # redirect all traffic to localhost:8080;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-NginX-Proxy true;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_pass php_backend:8080/$is_args$args;
        proxy_redirect off;
        proxy_read_timeout 86400;

        # enables WS support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # prevents 502 bad gateway error
        proxy_buffers 8 32k;
        proxy_buffer_size 64k;

        reset_timedout_connection on;

        #error_log /var/log/nginx/wss_error.log;
        #access_log /var/log/nginx/wss_access.log;
    }
