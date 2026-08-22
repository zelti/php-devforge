-- Derives the document root and the PHP-FPM backend from the host name.
--
-- Mirrors docker-library/httpd/config_files/resolve_docroot.lua. The logic is the
-- same; only the API differs, since this runs under OpenResty rather than mod_lua.
--
--   my-app--sites.phpforge.dev        -> public_html/sites/my-app     on the default
--   v2--api--sites.phpforge.dev       -> public_html/sites/api/v2
--   my-app--sites--p85.phpforge.dev   -> the same folder, on PHP 8.5
--
-- Segments are joined with "--" and read right to left, so the host reads like a
-- path in reverse.

local BASE = "/home/php-devforge/public_html"

-- True for a directory or a symlink to one. Opening a directory succeeds but
-- reading it does not, which is enough to tell them apart without extra libraries.
local function is_dir(path)
    local f = io.open(path, "r")
    if not f then return false end
    local ok = f:read(1)
    f:close()
    return ok == nil
end


local host = ngx.var.host
local dev_domain = ngx.var.dev_domain
local default_version = ngx.var.php_version

ngx.var.docroot = BASE

if not host or not dev_domain or dev_domain == "" then
    return
end

-- Escape the dots, or "phpforge.dev" would match "phpforgeXdev" too.
local domain = dev_domain:gsub("%.", "%%.")

-- --pNN chooses the PHP version for this request. Exactly two digits, so a crafted
-- host cannot inject anything into the backend address.
local version
local path_only = host:match("^(.*)%-%-p([0-9][0-9])%." .. domain .. "$")
if path_only then
    _, version = host:match("^(.*)%-%-p([0-9][0-9])%." .. domain .. "$")
else
    path_only = host:match("^(.*)%." .. domain .. "$")
end

version = version or default_version
if version and version:match("^[0-9][0-9]$") then
    ngx.var.php_backend = "php" .. version .. "dev"
end

if not path_only or path_only == "" then
    return
end

-- Split on "--" only. A plain "[^-]+" would split on every hyphen, so a project
-- called my-app became sites/app/my instead of sites/my-app.
-- \1 cannot appear in a host name, so it is a safe temporary separator.
local parts = {}
local marked = (path_only:gsub("%-%-", "\1"))
for part in marked:gmatch("[^\1]+") do
    parts[#parts + 1] = part
end

-- Read right to left: the host is the path reversed.
local reversed = {}
for i = #parts, 1, -1 do
    reversed[#reversed + 1] = parts[i]
end

-- sites/ is a shortcut: anything linked in there gets a short host name. Tried
-- first, with the full path from the root as the fallback, so both
--   mi-app.dominio                   -> sites/mi-app
--   public--mi-app--projects.dominio -> projects/mi-app/public
-- keep working.
local path = table.concat(reversed, "/")
local shortcut = BASE .. "/sites/" .. path
ngx.var.docroot = is_dir(shortcut) and shortcut or (BASE .. "/" .. path)
