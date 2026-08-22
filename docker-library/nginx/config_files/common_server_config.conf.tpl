set $dev_domain "${DEV_DOMAIN}";
set $php_version "${PHP_VERSION}";

# Both are filled in by the Lua below. The placeholder values matter: if the Lua
# ever failed to run, a .php would be served as a static file, which is how the
# Apache side once leaked source code. An unroutable backend fails closed instead.
set $docroot "/home/php-devforge/public_html";
set $php_backend "php-backend-unset";

rewrite_by_lua_file /etc/nginx/lua/resolve_docroot.lua;

root $docroot;
index index.php index.html;

# Hidden files like ".php"
location ~ /\.ph(p[345]?|t|tml|ps)$ {
    deny all;
}

location / {
    try_files $uri $uri/ =404;
}

location ~ \.php$ {
    include fastcgi_params;
    # A variable address needs a resolver: nginx looks it up per request.
    resolver 127.0.0.11 ipv6=off valid=10s;
    # Used directly rather than via an intermediate `set`. A `set` here runs in the
    # rewrite phase, which happens *before* rewrite_by_lua_file, so it would capture
    # the placeholder instead of what the Lua computed.
    fastcgi_pass $php_backend:9000;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    # nginx does not forward Authorization to FastCGI on its own either.
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}
