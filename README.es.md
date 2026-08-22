<p align="center">
  <img src="./logo.png" alt="PHP DevForge" width="300px" height="300px">
</p>

# PHP DevForge

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/zelti/php-devforge/actions/workflows/ci.yml/badge.svg)](https://github.com/zelti/php-devforge/actions/workflows/ci.yml)
![PHP](https://img.shields.io/badge/PHP-8.3%20%7C%208.4%20%7C%208.5-777BB4)
[![GitHub last commit](https://img.shields.io/github/last-commit/zelti/php-devforge)]()

[English](README.md) · **Español**

Un entorno PHP local donde **la estructura de carpetas es la configuración**.

> A diferencia de las herramientas basadas en configuración por proyecto, PHP DevForge
> deriva los dominios directamente de la estructura de carpetas. Sin archivos de config,
> sin comandos de inicialización: creas la carpeta y el sitio existe.

---

## ⚡ Cómo funciona

```
~/php-devforge/sites/
├── mi-app        →  https://mi-app--sites.phpforge.dev
├── tienda        →  https://tienda--sites.phpforge.dev
└── api/v2        →  https://v2--api--sites.phpforge.dev
```

El nombre del host es la ruta, invertida y unida con `--`. No hay nada que registrar
ni que reiniciar. Creas una carpeta y recargas el navegador.

**Cualquier versión de PHP, por petición:**

```
https://mi-app--sites.phpforge.dev          # tu versión por defecto
https://mi-app--sites--p83.phpforge.dev     # esta petición en PHP 8.3
https://mi-app--sites--p85.phpforge.dev     # esta petición en PHP 8.5
```

El mismo código en tres versiones, sin reiniciar y sin cambiar nada. Útil para
comprobar una actualización antes de comprometerte con ella.

Todo se sirve por **HTTPS real**, con un certificado en el que tu equipo confía.

## 🧭 Comparación

|  | PHP DevForge | [Herd](https://herd.laravel.com) | [DDEV](https://ddev.com) |
|---|---|---|---|
| Dominio desde el nombre de la carpeta | ✅ | ✅ | ❌ config por proyecto |
| **Rutas anidadas** (`v2--api--sites`) | ✅ cualquier nivel | ❌ un nivel | ❌ |
| **Versión de PHP por petición** (`--p85`) | ✅ desde la URL | ❌ por sitio | ❌ por proyecto |
| Linux | ✅ | ❌ macOS/Windows | ✅ |
| Corre en Docker | ✅ | ❌ nativo | ✅ |
| HTTPS local | ✅ | ✅ | ✅ |
| `.htaccess` | ✅ Apache | ✅ | ✅ |

DDEV te da una definición reproducible por proyecto — mejor cuando cada uno necesita
un stack distinto. Herd es la opción nativa más rápida en macOS. PHP DevForge está
pensado para tener muchos proyectos sobre un mismo entorno, sin configurar ninguno.

## 📖 Qué incluye

- **Apache + PHP-FPM 8.3, 8.4 y 8.5**, los tres activos, elegidos por petición
- **HTTPS automático** con una CA local de confianza
- **DNS local con comodín** que solo afecta a tu dominio de desarrollo
- **Edición en vivo** — los archivos están montados, no hay que sincronizar nada
- **Los archivos son tuyos** — los contenedores adoptan tu usuario, así que nada de
  `sudo` ni de `node_modules` imborrables
- **Xdebug** con interruptor, **Composer**, **Node 24**, **pnpm**
- Opcionales: **PostgreSQL**, **Elasticsearch** y **Kibana**

## 🚀 Instalación rápida

```bash
git clone https://github.com/zelti/php-devforge.git
cd php-devforge
./install.sh            # hace unas preguntas y deja todo listo
forge start
```

Y abre **https://welcome--sites.phpforge.dev**.

## 🔧 Instalación

### 📋 Requisitos

- Docker y Docker Compose v2 (también se usan para generar los certificados)
- Git
- Bash (Linux o macOS)

### 🚀 Pasos

1. **Clona el repositorio:**
   ```bash
   git clone https://github.com/zelti/php-devforge.git
   cd php-devforge
   ```
   Clónalo donde quieras: los scripts y los alias averiguan su propia ubicación.

2. **Ejecuta el instalador:**
   ```bash
   ./install.sh
   ```
   Pregunta por tu dominio, dónde vivirán tus proyectos y la versión de PHP por
   defecto; busca un puerto DNS libre, detecta tu usuario, escribe `.env`, crea la
   carpeta de proyectos, y ofrece generar los certificados y configurar el DNS.

   Se puede volver a ejecutar sin miedo: tu `.env` actual da los valores por defecto.
   Para uso desatendido:
   ```bash
   ./install.sh --yes --domain=midominio.dev --projects-dir=~/code
   ./install.sh --help        # todas las opciones
   ```

   Nada necesita `sudo` salvo el paso del DNS, y solo si lo aceptas.

3. **Carga los atajos (opcional):**
   ```bash
   source aliases.bash
   ```
   O añade esa línea a tu `~/.bashrc`, con la ruta completa a esta carpeta.

4. **Levanta el entorno:**
   ```bash
   docker compose up -d
   ```
   Comprueba que funciona: `https://welcome--sites.phpforge.dev`

## 💻 Uso

```bash
forge start                  # levantar todo
forge stop
forge restart
forge status                 # qué corre y cómo está configurado

forge use 8.5                # cambiar la versión por defecto
forge shell 8.4              # entrar a un contenedor
forge logs 8.4               # seguir sus logs

forge images build|pull      # construir en local, o usar las publicadas
forge certs                  # regenerar los certificados
forge dns status             # ver el DNS local

forge help
```

`forge` funciona desde cualquier carpeta y en cualquier shell. El instalador lo
enlaza en `~/.local/bin`. Los argumentos de versión aceptan `8.5` u `85`, y las
versiones disponibles salen de `docker-compose.yml` — añade un servicio y
`forge use 8.6` funciona solo.

### 🌐 Tus proyectos

Viven en la carpeta que elegiste al instalar (`PROJECTS_DIR` en `.env`,
`~/php-devforge` por defecto):

```
~/php-devforge/
├── projects/          tu código
└── sites/             un enlace simbólico por proyecto, para URLs cortas
    └── welcome/       página de prueba
```

Dentro de los contenedores siempre es `/home/php-devforge/public_html`, que es donde
miran Apache y PHP. Solo el lado del host es configurable.

**Los enlaces simbólicos deben apuntar dentro de `PROJECTS_DIR`.** Los contenedores
solo ven esa carpeta, así que un enlace a otro sitio no resuelve y da 404.

No hace falta ningún `chown`: los contenedores adoptan tu identificador de usuario
(`PUID`/`PGID` en `.env`), así que lo que crean es tuyo y `node_modules` se borra sin
`sudo`.

#### Ejemplo con Laravel

```bash
ln -s ../projects/mi-app/public ~/php-devforge/sites/mi-app
```

→ `https://mi-app--sites.phpforge.dev`

El enlace debe apuntar a la carpeta que contiene el `index.php` (el `public/` del
framework). El `.htaccess` funciona: `AllowOverride All` está activado.

### 🐞 Xdebug

Dentro del contenedor:

```bash
xdebug                    # activar o desactivar
xdebug --force-activate
xdebug /ruta/script.php   # ejecutar un script con Xdebug activo
```

Configura tu editor para escuchar en el puerto **9003**.

## 🌐 DNS local

El instalador ofrece configurarlo. Enruta **solo** tu dominio de desarrollo al dnsmasq
del stack; el resto de tu DNS no se toca, así que apagar los contenedores nunca te deja
sin internet.

```bash
./setup-local-dns.sh            # aplicar
./setup-local-dns.sh --status   # ver la configuración
./setup-local-dns.sh --test     # comprobar la resolución
./setup-local-dns.sh --remove   # deshacer: borra un archivo
```

dnsmasq escucha en `127.0.0.1:${DNS_PORT}` en vez del puerto 53, que suele estar
ocupado por systemd-resolved, Pi-hole o similar. El instalador busca uno libre y lo
escribe en `.env`.

Soportado: Linux con systemd-resolved, y macOS mediante `/etc/resolver`. En cualquier
otro sistema el script imprime instrucciones y **no cambia nada**, en vez de reescribir
tu DNS de una forma que podría romperse con los contenedores apagados.

## ✏️ Personalizar sin romper las actualizaciones

**No edites nada dentro de `docker-library/`.** Esos archivos cambian con cada versión,
así que tus cambios darán conflictos al hacer `git pull` — y una copia aparte es peor:
deja de recibir arreglos, en silencio. Usa esto. Los tres están fuera de git.

**Ajustes de PHP — sin reconstruir.** Deja un archivo en `custom/php.d/`:

```ini
; custom/php.d/99-mio.ini
memory_limit = 512M
upload_max_filesize = 100M
```

```bash
docker compose up -d --force-recreate php84dev
```

Se lee *además* de la configuración de la imagen, así que no pisa nada y el interruptor
de Xdebug sigue funcionando.

**Tus propios servicios** — `docker-compose.local.yml`, se carga solo:

```yaml
services:
  redis:
    image: redis:7-alpine
    ports:
      - 127.0.0.1:6379:6379
```

El mismo archivo sobreescribe lo que venga en el proyecto: puertos, volúmenes,
variables.

**Extensiones o paquetes extra** — extiende la imagen en vez de copiar su Dockerfile,
así sigues recibiendo los arreglos:

```dockerfile
# custom/php/Dockerfile
FROM ghcr.io/zelti/php-devforge/php:8.4-dev
RUN sudo pecl install mongodb && sudo docker-php-ext-enable mongodb
```

```yaml
# docker-compose.local.yml
services:
  php84dev:
    build:
      context: ./custom/php
```

## 📦 Descargar o construir las imágenes

Por defecto se usan imágenes ya construidas desde `ghcr.io`, así que la primera vez
tarda un minuto en vez de los ~15 que cuesta compilar las extensiones de PHP, PECL y
Node. El instalador pregunta cuál quieres, y puedes cambiar de idea con una línea:

```bash
IMAGE_MODE=missing   # usar las publicadas (por defecto)
IMAGE_MODE=build     # construir siempre en local
IMAGE_MODE=always    # volver a descargar, para forzar la última publicada
```

Después, `docker compose up -d`.

Elige `build` si editas algo dentro de `docker-library/`: tus cambios se recogen solos,
y la caché de Docker hace que no cueste nada cuando no hay cambios.

**Ojo:** lo que se fija al construir la imagen — `NODE_VERSION`, por ejemplo — solo
aplica si construyes. Una imagen descargada ya lo trae fijado.

## 🗄️ Bases de datos y correo

No arranca nada que no elijas. El instalador pregunta; después:

```bash
forge db list              # cuáles existen y cuáles están encendidas
forge db on pg18
forge db off mariadb12
forge mail on              # capturador de correo en maildev.<dominio>
```

| Nombre | Imagen | Puerto en tu máquina |
|---|---|---|
| `pg16` `pg17` `pg18` | postgres 16 / 17 / 18 | 5416 / 5417 / 5418 |
| `mariadb11` `mariadb12` | mariadb 11.8 LTS / 12 | 3311 / 3312 |
| `mail` | Mailpit | interfaz en `https://maildev.<dominio>` |

Los puertos codifican la versión, así que varias pueden convivir — útil para probar
una migración contra la versión que usarás en producción.

**Desde tu código**, se alcanzan por el nombre del contenedor en la red compartida:

```php
new PDO("pgsql:host=postgres18dev;port=5432;dbname=php-devforge", $user, $pass);
new PDO("mysql:host=mariadb12dev;port=3306;dbname=php-devforge", $user, $pass);
```

Las credenciales son `USER_DEV` / `PASSWD_DEV` del `.env`. Los puertos de arriba son
para tus propias herramientas: un cliente gráfico, `psql`, un script de migración.

**Correo**: apunta el SMTP de tu framework a `maildev:1025`, sin autenticación ni TLS.
Todo lo enviado se captura y se ve en `https://maildev.<dominio>`; nada sale de tu
máquina.

## 🧩 Servicios opcionales

Algunos no se levantan por defecto. Llevan un `profile` de compose, así que los pides
cuando los quieras:

```bash
docker compose --profile search up -d      # Elasticsearch + Kibana
```

Los perfiles son cosa de compose, así que este sigue siendo un comando de
`docker compose`; `forge start` cubre el conjunto por defecto.

| Perfil | Servicios | Notas |
|---|---|---|
| *(ninguno)* | apachedev, php83dev, php84dev, php85dev, dnsmasq, postgres16dev | los levanta `forge start` |
| `search` | es8143dev, kibana | Kibana en `127.0.0.1:5601` |
| `tools` | mkcert | lo usa `install_cert.sh`; no es un servicio permanente |
| `nginx` | nginxdev | **sustituye** a apachedev; ver abajo |

### nginx en vez de Apache

Apache es el predeterminado porque soporta `.htaccess`, cosa que nginx no. Si
prefieres nginx, está disponible — como alternativa, no como añadido, porque ambos
quieren los puertos 80 y 443:

```bash
docker compose stop apachedev
docker compose --profile nginx up -d nginxdev
```

Sirve las mismas URLs, incluidas las rutas anidadas y el sufijo `--pNN`.

Es **OpenResty**, no nginx a secas: el docroot y el backend de PHP se derivan del
nombre del host con Lua, y eso nginx normal no lo puede hacer. Cambiar la imagen base
por `nginx:alpine` no funcionaría.

Son definiciones reales, no YAML comentado, así que `docker compose config` y la CI las
siguen validando y no pueden romperse en silencio.

## 🛠️ Extensiones y herramientas

**Extensiones de PHP:** GD, Intl, Zip, PDO MySQL, PDO PostgreSQL, SOAP, XSL, BC Math,
OPcache, Mbstring, Exif, PCNTL, Imagick, Redis, APCu, Xdebug

**Herramientas:** Composer, Node.js 24 LTS (vía NVM), pnpm, Git, Cron

## 🐛 Problemas comunes

- **El DNS no resuelve**: ejecuta `./setup-local-dns.sh --status` y `--test`. Puede
  hacer falta reiniciar el navegador.
- **El certificado no es de confianza**: vuelve a ejecutar `./install_cert.sh` y
  reinicia el navegador. Firefox tiene su propio almacén en Linux: instala `nss` (Arch)
  o `libnss3-tools` (Debian/Ubuntu) y repite.
- **Los contenedores no arrancan**: comprueba que Docker esté corriendo y que los
  puertos 80 y 443 estén libres.
- **Problemas de permisos**: revisa que `PUID`/`PGID` en `.env` coincidan con los tuyos
  (`id -u`, `id -g`) y recrea los contenedores.
- **No cambia la versión de PHP**: revisa `PHP_VERSION` en `.env` (83, 84 u 85), o añade
  `--p83`/`--p84`/`--p85` al host.
- **`npm` muestra un aviso sobre pnpm**: es a propósito. npm sigue funcionando.
- **Un `.ini` de `custom/php.d/` parece ignorado**: recrea el contenedor con
  `docker compose up -d --force-recreate php84dev`. Reiniciar no basta.
- **Los alias no funcionan**: asegúrate de haber hecho `source aliases.bash`.

## 🤝 Contribuir

1. Haz un fork y crea una rama
2. Haz tus cambios
3. Comprueba que la CI pasa — construye e instala en una máquina limpia, así que
   detecta bastante
4. Abre un pull request describiendo qué cambia y por qué

## 📄 Licencia

MIT — ver [LICENSE](LICENSE).
