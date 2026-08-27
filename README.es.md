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

Cada carpeta bajo `~/php-devforge/` es un sitio. El nombre del host es su ruta, leída
de dentro hacia fuera y unida con `--`:

```
~/php-devforge/projects/mi-app/public/
                     ↓
https://public--mi-app--projects.phpforge.dev
```

No hay nada que registrar ni que reiniciar. Creas la carpeta y recargas el navegador.

### ¿Quieres una URL más corta?

Ese nombre es honesto, pero largo. Enlaza el proyecto en `sites/` y responderá también
con su propio nombre:

```bash
forge link ~/php-devforge/projects/mi-app/public
→ https://mi-app.phpforge.dev
```

```
~/php-devforge/sites/
├── mi-app        →  https://mi-app.phpforge.dev
├── tienda        →  https://tienda.phpforge.dev
└── api/v2        →  https://v2--api.phpforge.dev
```

La URL larga sigue funcionando. La corta es un nombre de más, no un reemplazo: las dos
llegan a la misma carpeta.

**Cualquier versión de PHP, por petición:**

```
https://mi-app.phpforge.dev          # tu versión por defecto
https://mi-app--p83.phpforge.dev     # esta petición en PHP 8.3
https://mi-app--p85.phpforge.dev     # esta petición en PHP 8.5
```

El mismo código en las versiones que instalaste, sin reiniciar y sin cambiar nada.
Útil para comprobar una actualización antes de comprometerte con ella.

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

- **Apache + PHP-FPM 8.3, 8.4 y 8.5** — instalas las que quieras, elegidas por petición
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

Y abre **https://welcome.phpforge.dev**.

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
   Pregunta por tu dominio, dónde vivirán tus proyectos, qué versiones de PHP
   instalar y cuál de ellas es la de por defecto; busca un puerto DNS libre, detecta
   tu usuario, escribe `.env`, crea la carpeta de proyectos, y ofrece generar los
   certificados y configurar el DNS.

   Se puede volver a ejecutar sin miedo: tu `.env` actual da los valores por defecto.
   Para uso desatendido:
   ```bash
   ./install.sh --yes --domain=midominio.dev --projects-dir=~/code
   ./install.sh --yes --php=84,83             # dos versiones, 8.4 la de por defecto
   ./install.sh --yes --profiles=pg18,mail    # bases de datos y correo, desatendido
   ./install.sh --help                        # todas las opciones
   ```

   Nada necesita `sudo` salvo el paso del DNS, y solo si lo aceptas.

3. **Carga los atajos (opcional):**
   ```bash
   source aliases.bash
   ```
   O añade esa línea a tu `~/.bashrc`, con la ruta completa a esta carpeta.

4. **Levanta el entorno:**
   ```bash
   forge start
   ```
   Comprueba que funciona: `https://welcome.phpforge.dev`

### 🧹 Desinstalar

```bash
forge uninstall --dry-run    # qué borraría, sin tocar nada
forge uninstall              # hacerlo
```

Deshace la instalación en orden inverso: los contenedores, la red y las
imágenes, el enlace de `forge`, la entrada de DNS local, la CA de confianza
(almacén del sistema *y* Firefox/Chrome) y los archivos que generó el
instalador — `.env`, `certificates/`, `.caroot/`.

**Tus datos no se dan por supuestos.** Los volúmenes de las bases de datos y tu
carpeta de proyectos son dos preguntas aparte, ambas con "no" por defecto, y
`--yes` las conserva. Para llevártelas también: `--volumes` y `--projects`. Tu
`docker-compose.local.yml` y lo que tengas en `custom/php.d/` no se tocan nunca.

Antes de tocar nada imprime todo lo que va a borrar, con tamaños. Lo último que
dice es cómo borrar la carpeta del repositorio, que es lo único que no hace por
ti.

## 💻 Uso

### ▶️ Arrancar y parar

```bash
forge start                  # levantar todo
forge stop
forge restart
forge status                 # qué corre y cómo está configurado

forge link ~/code/app/public # publicar un proyecto en app.<dominio>

forge php list               # versiones de PHP, y cuáles están instaladas
forge php on|off 8.3         # instalar una, o liberar los ~2 GB que ocupa
forge use 8.5                # cambiar la versión por defecto (la instala si falta)
forge shell 8.4              # entrar a un contenedor
forge logs 8.4               # seguir sus logs

forge profile list           # servicios opcionales, y cuáles están encendidos
forge profile on|off <nom>   # encender o apagar uno
forge db list                # las bases de datos entre ellos
forge mail on|off            # un buzón de pruebas en mail.<dominio>

forge images build|pull      # construir en local, o usar las publicadas
forge certs                  # regenerar los certificados
forge dns status             # ver el DNS local

forge uninstall              # deshacer la instalación (ver más abajo)
forge help
```

`forge` funciona desde cualquier carpeta y en cualquier shell. El instalador lo
enlaza en `~/.local/bin`. Los argumentos de versión aceptan `8.5` u `85`, y las
versiones disponibles salen de `docker-compose.yml` — añade un servicio y
`forge use 8.6` funciona solo.

Es un envoltorio de `docker compose`, no un reemplazo: no esconde nada y los
comandos crudos siguen funcionando desde la carpeta del proyecto. Existe para que
lo que haces a diario sea una palabra, y para que lo que tiene truco — un enlace
relativo que los contenedores puedan seguir, nginx y Apache sin pelearse por el
puerto 80 — salga bien sin que tengas que acordarte de por qué.

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

**Dos formas de llegar al mismo proyecto.** `sites/` es un atajo: se prueba primero,
y la ruta completa desde la raíz es el respaldo.

| URL | Sirve |
|---|---|
| `mi-app.phpforge.dev` | `sites/mi-app` |
| `v2--api.phpforge.dev` | `sites/api/v2` |
| `public--mi-app--projects.phpforge.dev` | `projects/mi-app/public` |

Así puedes publicar a propósito con un nombre corto, o llegar a cualquier carpeta por
su ruta completa sin enlazar nada.

**Para publicar:** `forge link <carpeta> [nombre]` crea el enlace por ti. Usa el nombre
del proyecto cuando la carpeta se llama `public` (como en todos los frameworks), lo crea
**relativo** para que también resuelva dentro de los contenedores, y rechaza una carpeta
fuera de `PROJECTS_DIR` — los contenedores no ven nada más, así que ese enlace daría 404.

A mano sería:

```bash
cd ~/php-devforge
ln -s ../projects/mi-app/public sites/mi-app
```

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

### 🐘 Versiones de PHP

Se eligen al instalar, igual que las bases de datos, porque cada una es una imagen
aparte de unos 2 GB:

```bash
forge php list        # 8.3 off / 8.4 ON default / 8.5 off
forge php on 8.3      # descargarla y arrancarla
forge php off 8.3     # pararla; la imagen sigue en disco hasta que la borres
```

Una de ellas es la **de por defecto**: responde a todos los nombres de host sin
sufijo `--pNN`. `forge use 8.5` la cambia, instalando esa versión antes si no la
tienes, y `forge php off` se niega a quitar la de por defecto — si no, ningún
nombre de host normal tendría quién lo atienda.

Pedir una versión que no instalaste devuelve una página que lo explica y dice el
comando para añadirla, en vez de un 503 pelado.

### 🔄 Día a día

- Edita el código en tu editor — los archivos están montados, los cambios son inmediatos
- No hay que reiniciar nada por un cambio de código
- Entra a un contenedor con `forge shell 8.4`
- Mira qué está pasando con `forge logs`

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
forge dns setup     # aplicar
forge dns status    # ver la configuración
forge dns test      # comprobar la resolución
forge dns remove    # deshacer: borra un archivo
```

Llaman a `./setup-local-dns.sh`, que también puedes ejecutar directamente con las
mismas opciones como `--banderas`.

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
forge restart php84dev
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

Después, `forge start`. O sáltate la edición: `forge images build` y
`forge images pull` ponen esa línea y reinician por ti.

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
forge mail on              # capturador de correo en mail.<dominio>
```

| Nombre | Imagen | Puerto en tu máquina |
|---|---|---|
| `pg16` `pg17` `pg18` | postgres 16 / 17 / 18 | 5416 / 5417 / 5418 |
| `mariadb11` `mariadb12` | mariadb 11.8 LTS / 12 | 3311 / 3312 |
| `mail` | Mailpit | interfaz en `https://mail.<dominio>` |

Los puertos codifican la versión, así que varias pueden convivir — útil para probar
una migración contra la versión que usarás en producción.

**Desde tu código**, se alcanzan por el nombre del contenedor en la red compartida:

```php
new PDO("pgsql:host=postgres18dev;port=5432;dbname=php-devforge", $user, $pass);
new PDO("mysql:host=mariadb12dev;port=3306;dbname=php-devforge", $user, $pass);
```

Las credenciales son `USER_DEV` / `PASSWD_DEV` del `.env`. Los puertos de arriba son
para tus propias herramientas: un cliente gráfico, `psql`, un script de migración.

**Correo**: apunta el SMTP de tu framework a `mailpit:1025`, sin autenticación ni TLS.
Todo lo enviado se captura y se ve en `https://mail.<dominio>`; nada sale de tu
máquina.

## 🧩 Servicios opcionales

Algunos no se levantan por defecto. Llevan un `profile` de compose, así que los pides
cuando los quieras:

```bash
forge profile list                 # qué existe, y qué está encendido
forge profile on search            # Elasticsearch + Kibana
forge profile off search
```

El listado lee los archivos de compose, así que se mantiene solo: cada fila muestra
las imágenes que arranca ese perfil.

| Perfil | Servicios | Notas |
|---|---|---|
| *(ninguno)* | apachedev, dnsmasq | los levanta `forge start` |
| `php83` `php84` `php85` | php83dev, php84dev, php85dev | se eligen al instalar, o `forge php on 8.3` |
| `pg16` `pg17` `pg18` | postgres | ver la sección Bases de datos y correo |
| `mariadb11` `mariadb12` | mariadb | igual |
| `mail` | mailpit | interfaz en `https://mail.<dominio>` |
| `search` | es8143dev, kibana | Kibana en `127.0.0.1:5601` |
| `tools` | mkcert | lo usa `install_cert.sh`; no es un servicio permanente |
| `nginx` | nginxdev | **sustituye** a apachedev; ver abajo |

Cuáles arrancan lo decide `COMPOSE_PROFILES` en `.env`, una lista separada por comas.
El instalador la escribe, `forge db` y `forge mail` la editan, y también puedes tocarla
a mano:

```bash
COMPOSE_PROFILES=pg18,mariadb12,mail
```

Lo que no esté ahí queda definido pero nunca se levanta.

### nginx en vez de Apache

Apache es el predeterminado porque soporta `.htaccess`, cosa que nginx no. Si
prefieres nginx, está disponible — como alternativa, no como añadido, porque ambos
quieren los puertos 80 y 443:

```bash
forge profile on nginx     # para apachedev; no pueden compartir los puertos
forge profile off nginx    # y lo devuelve
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

**Herramientas:** Composer, Node.js 24 LTS vía NVM, pnpm, Git, Cron

`NODE_VERSION` en `.env` fija la versión de Node, y aplica cuando construyes tus
propias imágenes — una descargada ya la trae fijada. `npm` sigue funcionando pero te
apunta a pnpm. Xdebug está apagado hasta que lo enciendas con el comando `xdebug`
dentro de un contenedor; tu editor debe escuchar en el puerto **9003**.

## 🐛 Problemas comunes

- **El DNS no resuelve**: ejecuta `forge dns status` y `forge dns test`. Puede hacer
  falta reiniciar el navegador.
- **El certificado no es de confianza**: vuelve a ejecutar `forge certs` y reinicia el
  navegador. Firefox tiene su propio almacén en Linux: instala `nss` (Arch) o
  `libnss3-tools` (Debian/Ubuntu) y repite.
- **Los contenedores no arrancan**: comprueba que Docker esté corriendo y que los
  puertos 80 y 443 estén libres.
- **Problemas de permisos bajo `public_html`**: revisa que `PUID`/`PGID` en `.env`
  coincidan con los tuyos (`id -u`, `id -g`) y haz `forge restart`. Los contenedores
  adoptan esos ids al arrancar, así que lo que escriben es tuyo.
- **No cambia la versión de PHP**: revisa `PHP_VERSION` en `.env`, o añade
  `--p83`/`--p84`/`--p85` al nombre del host. `forge status` muestra la de por defecto.
- **"PHP 8.3 is not installed"**: esa versión no se eligió al instalar.
  `forge php on 8.3` la añade; `forge php list` muestra las que tienes.
- **`npm` muestra un aviso sobre pnpm**: es a propósito. npm sigue funcionando; aquí se
  prefiere pnpm.
- **Un `.ini` de `custom/php.d/` parece ignorado**: recrea el contenedor con
  `forge restart php84dev`. Reiniciar no basta.
- **`forge: command not found`**: el instalador lo enlaza en `~/.local/bin`, que
  algunos shells no tienen en el `PATH`. Añádelo, o haz `source aliases.bash` desde la
  carpeta del proyecto.

### Dos copias del proyecto

Cada copia usa el mismo nombre de proyecto de compose, así que un segundo clon —para
probar una actualización sin tocar lo que funciona— no obtiene su propio entorno.
Obtiene el mismo:

| Compartido | No compartido |
|---|---|
| los contenedores | tu código, en la carpeta que diga cada `.env` |
| los volúmenes de base de datos | el propio `.env`: dominio, versión de PHP, carpeta de proyectos |
| los puertos 80 y 443 | los certificados de `certificates/` |

Arrancar desde la segunda carpeta reconfigura los contenedores que ya corren, no crea
otros. `forge` pregunta antes, y `forge status` dice desde qué carpeta se arrancaron:

```
[!] These containers were started from:
      ~/Projects/otra-copia
    To go back:  cd ~/Projects/otra-copia && forge start

    Take them over? [y/N]
```

`forge --force <comando>` se salta la pregunta, que es también lo que necesitas donde
no hay terminal para responderla.

**Tu código nunca corre peligro**: es una carpeta de tu disco, montada dentro. Lo que
sí comparten las dos carpetas son los datos de las bases de datos, que viven en un
volumen de Docker con el nombre del proyecto y no el de la carpeta. `forge` no tiene
ningún comando que los borre — pero un `docker compose down -v` escrito a mano desde
cualquiera de las dos alcanza a las dos.

Para más ayuda, mira los logs con `forge logs` — o `forge logs apachedev` para un
servicio — o abre un issue en GitHub.

## 🤝 Contribuir

1. Haz un fork y crea una rama
2. Haz tus cambios
3. Comprueba que la CI pasa — instala y ejecuta todo en una máquina limpia, así que
   detecta bastante
4. Abre un pull request describiendo qué cambia y por qué

La CI construye las tres versiones de PHP, ejecuta el instalador, configura el DNS,
comprueba que un `.php` nunca se sirve como código fuente, que los archivos creados
en los contenedores son tuyos, y que Apache y nginx sirven lo mismo. Si está en
verde, funciona en una máquina que no es la tuya.

### Ejecutar un paso de la CI antes de subir

Una vuelta por GitHub son seis minutos, y la mayoría de los fallos no están en el
código sino en el propio paso: una bandera que pasas en local y la CI no, un valor
que debía dejar listo un paso anterior, una tubería que se comporta distinto bajo
`pipefail`. Así que ejecuta el paso tal como está escrito, en vez de reescribirlo:

```bash
forge start                                   # los pasos necesitan la pila arriba

.github/scripts/run-step.py                   # lista todos los pasos
.github/scripts/run-step.py "the forge command works"
.github/scripts/run-step.py -x "<nombre>"     # traza, para cazar el grep silencioso
```

Lee `.github/workflows/ci.yml` y ejecuta el bloque `run:` del paso verbatim bajo
`bash -e`, igual que GitHub. Necesita PyYAML; si no lo tienes, te dice cómo
instalarlo.

**Los pasos no son independientes.** Algunos leen cosas que creó un paso anterior
—el proyecto `my-app`, una base de datos encendida—, así que si uno falla por un
archivo que no existe, ejecuta antes el que lo crea. `run-step.py` sin argumentos
los lista en orden.

**Dos tipos de paso no pueden pasar en local**, y es lo esperado:

| Paso | Por qué | Para ejecutarlo igual |
|---|---|---|
| los de HTTPS | `curl` sin `-k`, a propósito: comprueba el almacén de confianza del sistema | `./install_cert.sh` (pide sudo, instala la CA) |
| los de DNS | reescriben el resolutor del sistema | `./setup-local-dns.sh` (pide sudo) |

Todo lo demás corre contra tus propios contenedores.

## 📄 Licencia

MIT — ver [LICENSE](LICENSE).
