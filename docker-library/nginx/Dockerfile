# Usa la imagen base OpenResty con Debian Bookworm
FROM openresty/openresty:bookworm

# Instala Bash y gettext (para envsubst) para asegurar la compatibilidad con tu CMD
# En Bookworm, gettext es el paquete que proporciona envsubst.
# Aunque Bash ya podría estar en Bookworm, lo instalamos para asegurar la compatibilidad con el CMD.
RUN apt-get update && \
    apt-get install -y --no-install-recommends bash gettext && \
    rm -rf /var/lib/apt/lists/*

# Crear usuario de desarrollo php-devforge
# Nota: Debian generalmente usa 'www-data' o 'nginx' como grupo del servidor web.
RUN useradd -m -d /home/php-devforge -s /bin/bash php-devforge \
    && sed -i -e "s/umask 022/umask 002/g" /home/php-devforge/.bashrc

# Ajustar permisos 
# Usamos 'www-data' ya que es el grupo común de Nginx/OpenResty en Debian.
RUN chown -R php-devforge:www-data /home/php-devforge \
    && chmod -R 775 /home/php-devforge

# 1. Crear el directorio Lua (si no existe) y el directorio de snippets
RUN mkdir -p /etc/nginx/lua /etc/nginx/snippets

# 2. Copia la plantilla y los archivos
# Usamos /etc/nginx/conf.d/ para las plantillas
COPY config_files/site.conf.tpl /etc/nginx/conf.d/site.conf.tpl 
COPY config_files/common_server_config.conf.tpl /etc/nginx/conf.d/common_server_config.conf.tpl
# El script Lua
COPY config_files/resolve_docroot.lua /etc/nginx/lua/resolve_docroot.lua 
#other config
COPY config_files/config.main /etc/nginx/conf.d/config.main
# 3. Crear carpeta de certificados
RUN mkdir -p /etc/nginx/ssl/

# 4. CMD: Procesa ambos templates con envsubst y luego inicia OpenResty
CMD ["/bin/bash", "-c", " \
    # Procesa el archivo principal de Nginx
    envsubst '$DEV_DOMAIN $PHP_VERSION' < /etc/nginx/conf.d/site.conf.tpl > /etc/nginx/conf.d/site.conf && \
    \
    # Procesa el fragmento de configuración común y lo guarda donde se incluye
    envsubst '$DEV_DOMAIN $PHP_VERSION' < /etc/nginx/conf.d/common_server_config.conf.tpl > /etc/nginx/snippets/common_server_config.conf && \
    \
    # Inicia OpenResty
    openresty -g 'daemon off;' \
    "]