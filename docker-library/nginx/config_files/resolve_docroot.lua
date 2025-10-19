-- resolve_docroot.lua
-- Script Lua para determinar el docroot dinámico, manejando subdominios con '-' y '.'

-- Obtiene la variable del host de Nginx
local host = ngx.var.host

-- Variable default para el docroot
local docroot = "/home/php-devforge/public_html"

-- Obtenemos el dominio base desde la variable de entorno
local dev_domain = ngx.var.dev_domain

if host and dev_domain and dev_domain ~= "" then
    -- 1. Intentar eliminar el sufijo de versión de PHP si está presente: "--pXX.phpbox.dev"
    -- El patrón usa la variable DEV_DOMAIN para ser dinámico.
    local path_only = host:match("^(.*)%-p[0-9]{2}\\." .. dev_domain .. "$")

    if not path_only then
        -- Si no tiene sufijo PHP, capturamos el subdominio hasta el dominio base
        path_only = host:match("^(.*)\\." .. dev_domain .. "$")
    end

    if path_only then
        -- 2. Manejar la lógica de reemplazo
        local final_path = path_only
        
        -- Primero: Reemplazar todas las ocurrencias de '--' por '/' (ej. "modulo--admin" -> "modulo/admin")
        final_path = final_path:gsub("--", "/")
        
        -- Segundo: Reemplazar todas las ocurrencias de '.' por '/' (ej. "app.v1" -> "app/v1")
        -- Se usa un patrón más estricto ([.]{1}) para evitar conflictos con el dominio.
        final_path = final_path:gsub("([.])", "/")
        
        -- 3. Construir el docroot final
        docroot = "/home/php-devforge/public_html/" .. final_path
    end
end

-- Asigna el valor calculado a la variable de Nginx ($docroot)
ngx.var.docroot = docroot

-- ngx.log(ngx.INFO, "Host: " .. (host or "N/A") .. " -> Docroot: " .. docroot)