set $dev_domain "${DEV_DOMAIN}";
set $php_version "${PHP_VERSION}";
# The COMPOSE_PROFILES line, so the Lua can tell an uninstalled version from a typo.
set $enabled_profiles "${ENABLED_PROFILES}";

# Both are filled in by the Lua below. The placeholder values matter: if the Lua
# ever failed to run, a .php would be served as a static file, which is how the
# Apache side once leaked source code. An unroutable backend fails closed instead.
set $docroot "/home/php-devforge/public_html";
set $php_backend "php-backend-unset";
# Filled by the Lua with the target of the project's front-controller rule, when
# its .htaccess declares one. Empty means "no such rule": 404 as before.
set $front_controller "";
# A static front controller -- a built SPA rewrites to index.html. try_files
# cannot take an empty item, so "nothing declared" is a path that never exists.
set $front_file "/__no_front_file__";
set $fc_mode "${NGINX_FRONT_CONTROLLER}";

rewrite_by_lua_file /etc/nginx/lua/resolve_docroot.lua;

root $docroot;
index index.php index.html;

# Hidden files like ".php"
location ~ /\.ph(p[345]?|t|tml|ps)$ {
    deny all;
}

location / {
    try_files $uri $uri/ @front_controller;
}

# Reached when the URL is neither a file nor a directory -- exactly what Laravel's
# `RewriteCond !-f` and `!-d` say. A static front controller (a built SPA rewrites
# to index.html) is served from here; a .php one has to go through FastCGI, and
# that cannot happen in this block: try_files serves the file within the current
# location, so an index.html reached from the .php location would be handed to
# php-fpm, which answers 403 by limit_extensions. Hence the second hop.
location @front_controller {
    try_files $front_file @front_php;
}

location @front_php {
    # Nothing declared one: the old behaviour, unchanged, for every project that
    # is a folder of files rather than an application.
    if ($front_controller = "") {
        return 404;
    }
    include fastcgi_params;
    resolver 127.0.0.11 ipv6=off valid=10s;
    fastcgi_pass $php_backend:9000;
    # Not $fastcgi_script_name: in a named location that is still /admin, and the
    # script to run is the front controller.
    fastcgi_param SCRIPT_FILENAME $document_root/$front_controller;
    fastcgi_param SCRIPT_NAME /$front_controller;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
}

location ~ \.php$ {
    # A .php that does not exist goes to the app's front controller, so it renders
    # its own 404 instead of php-fpm answering "File not found".
    #
    # Straight to @front_php, not @front_controller: nginx keeps this location's
    # FastCGI handler across the jump, so a static front controller reached from
    # here would be handed to php-fpm, which refuses it with 403. A project whose
    # front controller is an index.html therefore 404s on a .php URL, where Apache
    # would serve the shell. That corner is documented rather than fought.
    try_files $uri @front_php;
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
