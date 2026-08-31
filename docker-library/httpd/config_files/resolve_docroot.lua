-- resolve_docroot.lua
-- Script Lua simple para determinar docroot dinámico

require "apache2"

-- True for a directory or a symlink to one. Opening a directory succeeds but
-- reading it does not, which is enough to tell them apart without extra libraries.
local function is_dir(path)
    local f = io.open(path, "r")
    if not f then return false end
    local ok = f:read(1)
    f:close()
    return ok == nil
end


-- 83 -> 8.3
local function pretty(v)
    return v:sub(1, 1) .. "." .. v:sub(2)
end

-- ENABLED_PROFILES is the COMPOSE_PROFILES line from .env, handed over by
-- docker-compose.yml. Versions are installed one profile at a time, so a version
-- that is not listed there has no container to proxy to.
--
-- No php entry at all means we cannot tell -- someone running compose by hand --
-- and then it is better to proxy and fail as before than to refuse everything.
local function installed_versions()
    local enabled = os.getenv("ENABLED_PROFILES") or ""
    if not enabled:find("php%d%d") then return nil end
    local list = {}
    for v in enabled:gmatch("php(%d%d)") do list[#list + 1] = v end
    table.sort(list)
    return list
end

local function has(list, ver)
    for _, v in ipairs(list) do if v == ver then return true end end
    return false
end

-- Answered from the translate-name hook, not from set_php_handler: a "/" reaches
-- PHP through mod_dir's DirectoryIndex, whose internal redirect throws away a body
-- written that late -- the request ends as an empty 200 on a directory. Translate
-- name runs before mod_dir, so this covers "/" and /index.php alike.
--
-- Without it the request proxies to a host that does not resolve and Apache
-- answers a bare 503, which says nothing about the one thing that is wrong.
local function not_installed_page(r, ver, list)
    local default = os.getenv("PHP_VERSION") or ""
    local have = {}
    for _, v in ipairs(list) do
        have[#have + 1] = pretty(v) .. (v == default and " (default)" or "")
    end

    r.status = 503
    r.content_type = "text/html; charset=utf-8"
    r:puts([[<!doctype html>
<title>PHP ]] .. pretty(ver) .. [[ is not installed</title>
<style>
body{font:16px/1.6 system-ui,sans-serif;max-width:44rem;margin:4rem auto;padding:0 1.5rem}
code{background:#f4f4f5;padding:.15em .4em;border-radius:.25em}
p{color:#3f3f46}
</style>
<h1>PHP ]] .. pretty(ver) .. [[ is not installed</h1>
<p><code>]] .. (r.hostname or "") .. [[</code> asks for PHP ]] .. pretty(ver) .. [[,
but this environment serves ]] .. table.concat(have, ", ") .. [[.</p>
<p>Add it:</p>
<pre><code>forge php on ]] .. pretty(ver) .. [[</code></pre>
<p><code>forge php list</code> shows every version this project can install.</p>
]])
    r:info("PHP " .. pretty(ver) .. " requested but not installed: " .. (r.hostname or ""))
    return apache2.DONE
end

function silly_mapper(r)
    local dev_domain = os.getenv("DEV_DOMAIN") 
    local host = r.hostname
    local docroot = "/home/php-devforge/public_html"
    
    
    -- Si DEV_DOMAIN no está configurada, salir
    if not dev_domain then
        r:err("ERROR: DEV_DOMAIN environment variable not set")
        return apache2.DECLINED
    end

    -- The whole host is unusable when its PHP version is not installed, static
    -- files included, so this is decided once here rather than per file type.
    local installed = installed_versions()
    if installed then
        local ver = host:match("%-%-p([0-9][0-9])%." .. dev_domain:gsub("%.", "%%.") .. "$")
                    or os.getenv("PHP_VERSION")
        if ver and ver:match("^[0-9][0-9]$") and not has(installed, ver) then
            return not_installed_page(r, ver, installed)
        end
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
            -- Split on "--" only. "[^%-%-]+" would split on every single hyphen,
            -- so a project named mi-app became sites/app/mi instead of sites/mi-app.
            -- \1 cannot appear in a hostname, so it is a safe temporary separator.
            local tmp = (final_path:gsub("%-%-", "\1"))
            for part in string.gmatch(tmp, "[^\1]+") do
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
                
        -- sites/ is a shortcut: anything linked in there gets a short host name.
        -- Tried first, with the full path from the root as the fallback, so both
        --   mi-app.dominio                  -> sites/mi-app
        --   public--mi-app--projects.dominio -> projects/mi-app/public
        -- keep working.
        local shortcut = docroot .. "/sites/" .. final_path
        if is_dir(shortcut) then
            docroot = shortcut
        else
            docroot = docroot .. "/" .. final_path
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

    -- mod_rewrite's per-directory hook is a fixup too, and it runs first. A
    -- front controller's .htaccess (Laravel, Symfony, WordPress...) rewrites to
    -- index.php from there, which leaves r.filename as "redirect:/index.php" --
    -- a marker, not a path. mod_proxy concatenates the handler with it, so the
    -- backend became "fcgi://phpNNdev:9000redirect:/index.php" and every URL
    -- except "/" died on a DNS lookup. The internal redirect that follows runs
    -- this hook again with the real file name, so declining here costs nothing.
    if r.filename:sub(1, 1) ~= "/" then
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
