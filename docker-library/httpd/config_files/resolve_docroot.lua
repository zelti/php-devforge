-- resolve_docroot.lua
-- Script Lua simple para determinar docroot dinámico

require "apache2"

function silly_mapper(r)
    local dev_domain = os.getenv("DEV_DOMAIN") 
    local host = r.hostname
    local docroot = "/home/php-devforge/public_html"
    
    
    -- Si DEV_DOMAIN no está configurada, salir
    if not dev_domain then
        r:err("ERROR: DEV_DOMAIN environment variable not set")
        return apache2.DECLINED
    end
    
    local path_only = nil
    
    -- Primero intentar capturar con sufijo PHP (-p[numero])
    path_only = host:match("^(.*)%-%-p[0-9][0-9]%." .. dev_domain:gsub("%.", "%%.") .. "$")
    
    if not path_only then
        -- Si no tiene sufijo PHP, capturar el subdominio completo
        path_only = host:match("^(.*)%." .. dev_domain:gsub("%.", "%%.") .. "$")
    end
        
    if path_only and path_only ~= "" then
        -- Manejar la lógica de reemplazo
        local final_path = path_only
                
        -- Determinar si usa -- o . como separador
        local path_parts = {}
        
        if string.find(final_path, "%-%-") then
            -- Usar separador --
            for part in string.gmatch(final_path, "[^%-%-]+") do
                table.insert(path_parts, part)
            end
        else
            -- Usar separador . (punto)
            for part in string.gmatch(final_path, "[^%.]+") do
                table.insert(path_parts, part)
            end
        end
            
        -- Invertir el orden de las partes
        local reversed_parts = {}
        for i = #path_parts, 1, -1 do
            table.insert(reversed_parts, path_parts[i])
        end
        
        -- Construir el path final invertido
        final_path = table.concat(reversed_parts, "/")
                
        -- Construir la ruta final
        docroot = docroot .. "/" .. final_path
        
        -- Opcional: Verificar si el directorio existe
        local file = io.open(docroot, "r")
        if file then
            file:close()
        end
    end
    
    -- Establecer el nuevo document root
    r:set_document_root(docroot)
    
    return apache2.DECLINED
end

-- Picks the PHP-FPM backend from the host: --pNN wins, else PHP_VERSION from .env.
-- Only two digits are captured, so the Host header cannot inject into the address.
function set_php_handler(r)
    if not r.filename or not r.filename:match("%.php$") then
        return apache2.DECLINED
    end

    local dev_domain = os.getenv("DEV_DOMAIN")
    if not dev_domain then return apache2.DECLINED end

    local ver = r.hostname:match("%-%-p([0-9][0-9])%." .. dev_domain:gsub("%.", "%%.") .. "$")
                or os.getenv("PHP_VERSION")

    -- No version means no handler, so Apache would serve the .php as text.
    if not ver or not ver:match("^[0-9][0-9]$") then
        r:err("PHP_VERSION missing or invalid; refusing to serve " .. r.filename)
        return 500
    end

    r.handler = "proxy:fcgi://php" .. ver .. "dev:9000"
    return apache2.DECLINED
end
