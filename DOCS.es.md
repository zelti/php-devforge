# PHP DevForge · Documentación

← Volver al [README](README.es.md) · [English](DOCS.md)

- [🔧 Instalación](#-instalación)
- [💻 Uso](#-uso)
- [🔗 Dominios, y cómo publicar un proyecto](#-dominios-y-cómo-publicar-un-proyecto)
- [📱 Túneles públicos](#-túneles-públicos)
- [🌐 DNS local](#-dns-local)
- [✏️ Personalizar sin romper las actualizaciones](#-personalizar-sin-romper-las-actualizaciones)
- [📦 Descargar o construir las imágenes](#-descargar-o-construir-las-imágenes)
- [🗄️ Bases de datos y correo](#-bases-de-datos-y-correo)
- [🧩 Servicios opcionales](#-servicios-opcionales)
- [🤖 Agentes de IA](#-agentes-de-ia)
- [🛠️ Extensiones y herramientas](#-extensiones-y-herramientas)
- [🐛 Problemas comunes](#-problemas-comunes)
- [🤝 Contribuir](#-contribuir)

---

## 🔧 Instalación

### 📋 Requisitos

- Docker y Docker Compose v2 (también se usan para generar los certificados)
- Git
- Bash (Linux o macOS)

### 🚀 Pasos

En una línea, si prefieres no hacer los dos primeros a mano — clona el repositorio
y le pasa el testigo al mismo instalador, nada más:

```bash
curl -fsSL https://raw.githubusercontent.com/zelti/php-devforge/main/bootstrap.sh | bash
```

Clona en `$HOME/php-devforge-config` salvo que digas otra cosa con `--dir=` o
`PHP_DEVFORGE_HOME`. ¿Prefieres leerlo antes? Guárdalo con `-o bootstrap.sh`,
léelo, y luego `bash bootstrap.sh`. Acabes como acabes, llegas al mismo sitio que
con los pasos de abajo, así que sigue por el 3.

1. **Clona el repositorio:**
   ```bash
   git clone https://github.com/zelti/php-devforge.git
   cd php-devforge
   ```
   Clónalo donde quieras: los scripts averiguan su propia ubicación.

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

3. **Úsalo desde cualquier sitio:**
   El instalador enlaza `forge` en `~/.local/bin`, así que el comando funciona desde
   cualquier carpeta y en cualquier shell. `forge help` lo lista todo.

4. **Levanta el entorno:**
   ```bash
   forge start
   ```
   Comprueba que funciona: `https://welcome.phpforge.dev` — la página informa de
   lo que hay corriendo de verdad: la versión de PHP y el servidor que responden,
   qué otras versiones tienes instaladas y qué bases de datos y correo están arriba.

### 🔄 Actualizar

```bash
forge update
```

Mueve este checkout al último release y reconcilia `.env` contra él — en cuanto
haya uno nuevo, verás un aviso amarillo en cualquier comando. Te deja exactamente
en ese release (un commit suelto, no una rama), así que todo el que actualiza
termina en el mismo código; `forge update --edge` sigue `main` en cambio, si
prefieres eso. Un cambio local en un archivo rastreado (no `.env` ni nada dentro
de `custom/`, que son tuyos y nunca se tocan) lo detiene en vez de arriesgarse a
perderlo — `forge update --stash` lo lleva consigo, sin que tengas que escribir
comandos de git tú mismo.

Las imágenes de Docker se versionan aparte, con una etiqueta flotante que no
las sigue automáticamente: `docker compose pull` si también quieres la más
reciente.

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
forge tunnel                 # y una URL pública, para llegar desde fuera de tu máquina

forge php list               # versiones de PHP, y cuáles están instaladas
forge php on|off 8.3         # instalar una, o liberar los ~2 GB que ocupa
forge use 8.5                # cambiar la versión por defecto (la instala si falta)
forge run composer install   # ejecutar un comando en el contenedor correcto
forge shell 8.4              # entrar a un contenedor
forge logs 8.4               # seguir sus logs

forge profile list           # servicios opcionales, y cuáles están encendidos
forge profile on|off <nom>   # encender o apagar uno
forge db list                # las bases de datos entre ellos
forge mail on|off            # un buzón de pruebas en mail.<dominio>

forge images build|pull      # construir en local, o usar las publicadas
forge certs                  # regenerar los certificados
forge dns status             # ver el DNS local
forge skill status           # enseñarle a los agentes de IA a usar esto

forge install                # reejecutar el instalador: dominio, versiones o perfiles
forge uninstall              # deshacer la instalación (ver más abajo)
forge version
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

### ⚙️ Ejecutar comandos en un proyecto

`forge run` ejecuta un comando dentro del contenedor correcto, en la carpeta donde
estás:

```bash
cd ~/php-devforge/projects/mi-app
forge run composer install
forge run pnpm run build
forge run php artisan migrate

forge run -p 8.3 php -v                    # otra versión, solo esta vez
forge run -C projects/mi-app pnpm build    # desde donde sea
```

Existe porque escribirlo a mano tiene cuatro formas de salir mal. La carpeta de
proyectos está montada en otra ruta adentro, así que pasar la del host falla con
`chdir ... no such file or directory`. El usuario es `php-devforge`, no root. Node
y pnpm vienen de nvm y solo están en el PATH de un shell de **login**, así que sin
eso parecen no estar instalados. Y `-it` falla cuando no hay terminal — `forge
run` lo agrega solo cuando la hay, que es lo mismo que mantiene los códigos de
color fuera de la salida capturada.

Devuelve el código de salida del comando, así que sirve dentro de un script.

### 🐞 Xdebug

Dentro del contenedor:

```bash
xdebug                    # activar o desactivar
xdebug --force-activate
xdebug /ruta/script.php   # ejecutar un script con Xdebug activo
```

Configura tu editor para escuchar en el puerto **9003**.

## 🔗 Dominios, y cómo publicar un proyecto

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

### 🧪 Ejemplo con Laravel

```bash
ln -s ../projects/mi-app/public ~/php-devforge/sites/mi-app
```

→ `https://mi-app--sites.phpforge.dev`

El enlace debe apuntar a la carpeta que contiene el `index.php` (el `public/` del
framework). El `.htaccess` funciona: `AllowOverride All` está activado.

### 🐘 Elegir la versión de PHP desde la URL

Añade `--pNN` al host para elegir versión solo en esa petición:

- `https://mi-app--sites.phpforge.dev` — la de por defecto, la de `.env`
- `https://mi-app--sites--p83.phpforge.dev` — PHP 8.3
- `https://mi-app--sites--p84.phpforge.dev` — PHP 8.4
- `https://mi-app--sites--p85.phpforge.dev` — PHP 8.5

El backend sale del nombre del host, así que añadir una versión no necesita tocar
ninguna configuración: basta un servicio en `docker-compose.yml`.

## 📱 Túneles públicos

Todo lo anterior se alcanza desde esta máquina y desde ninguna otra.
`forge tunnel` le da a un proyecto una URL pública — que es como se prueba en un
teléfono de verdad en vez de en una ventana estrecha del navegador, y como le
enseñas a un cliente por dónde va la cosa sin desplegar nada en ningún sitio.

Dos formas, y la única diferencia es si le das credenciales a Cloudflare.

### 🎲 Una URL desechable, sin cuenta

```bash
forge tunnel                 # la carpeta donde estás
forge tunnel mi-app          # o nombras una carpeta, o un sitio publicado
forge tunnel --php 8.3       # servirlo con una versión concreta
```

Una dirección aleatoria `*.trycloudflare.com`, que se imprime al levantarse.
Corre en primer plano y termina con Ctrl+C. No instala nada ni deja nada detrás.

> ⚠️ **Mientras corre, la app está en internet.** Cualquiera con la dirección
> llega a ella — y a tu base de datos, y a los datos de prueba que tenga dentro.
> La dirección es aleatoria, que no es lo mismo que secreta.

### 📧 Dejar entrar solo a quien tú digas

```bash
forge tunnel --allowed-mail tu@ejemplo.com
forge tunnel --allowed-mail tu@ejemplo.com --allowed-mail '*@acme.com'
```

Quien visite escribe esa dirección, Cloudflare le manda un PIN de un solo uso, y
solo entonces la petición llega a tu máquina. La tuya para el teléfono, la del
cliente para enseñárselo. **Tu app no ve nada de ese inicio
de sesión**: es de Cloudflare, delante del túnel, así que no hay nada que montar
ni nada que quitar después.

Repite la bandera para más de una dirección; `*@dominio` deja entrar a todos los
de ahí. Necesita cloudflared 2026.9.3 o más nuevo.

Esto es solo del modo desechable. El equivalente de un túnel con nombre es una
política de Cloudflare Access, que vive en su panel y no es algo que gestione
este comando.

### 🏷️ Un nombre que se queda, en tu propio dominio

Necesita un dominio que ya esté en tu cuenta de Cloudflare.

```bash
forge tunnel login                                  # el navegador, una vez
forge tunnel add mi-app mi-app.tunel.tudominio.com  # crea el registro DNS
forge tunnel on                                     # en segundo plano, aguanta un reinicio
forge tunnel status
forge tunnel rm mi-app
```

Tras el primero puedes omitir el nombre: `forge tunnel add otra-app` copia la
forma de lo que ya esté mapeado. Se pueden publicar varios proyectos a la vez, y
`forge tunnel on` los sirve todos por una sola conexión.

`forge tunnel off` para el túnel y deja los registros DNS donde estaban; quien
despublica uno es `rm`.

### 🔎 Por qué tu app no necesita ningún cambio

Dos detalles que una línea de `cloudflared` escrita a mano suele errar, y son la
razón de que esto sea un comando y no un fragmento en el README.

**Va al puerto HTTPS del servidor, no al 80.** Por HTTP en claro la app no ve TLS
y escribe enlaces `http://` dentro de una página `https://`: el navegador los
bloquea por contenido mixto, o las redirecciones entran en bucle. El remedio
habitual es tocar la configuración de proxies de la app — trabajo que un entorno
de desarrollo no tiene por qué pedirte. Por el 443, PHP recibe `HTTPS=on` de
verdad y en la app no cambia nada. El certificado propio se salta a propósito, y
ningún teléfono lo ve nunca, porque el HTTPS público lo pone Cloudflare.

**La cabecera `Host` se pasa intacta.** El servidor elige el proyecto a partir de
ella, y un túnel manda su propio nombre, que no es de tu dominio local — así que
lo evidente es reescribirla, y ahí está la trampa. La app se creería entonces que
vive en `mi-app.phpforge.dev` y escribiría ahí cada enlace y cada redirección,
ninguno alcanzable desde el teléfono. En vez de eso, `forge tunnel` da de alta el
nombre público como un sitio más mientras el túnel vive, en una carpeta
`.tunnel/` al lado de `sites/`, y la barre al salir — también después de cerrar
la ventana a lo bruto. La app ve la dirección que el visitante usó de verdad.

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
así que tus cambios darán conflictos al hacer `forge update` — y una copia aparte es peor:
deja de recibir arreglos, en silencio. Usa esto. Los tres están fuera de git.

**Ajustes de PHP — sin reconstruir.** Deja un archivo en `custom/php.d/`:

```ini
; custom/php.d/99-mio.ini
memory_limit = 512M
upload_max_filesize = 100M
```

```bash
forge restart
```

Se lee *además* de la configuración de la imagen, así que no pisa nada y el interruptor
de Xdebug sigue funcionando.

**Para una sola versión** — lo mismo, en la carpeta de esa versión:

```ini
; custom/8.3/php.d/99-mio.ini
memory_limit = 1G
```

Se lee después de la carpeta común, así que gana donde las dos coincidan, y ninguna
otra versión la ve. Todo lo que pongas en `custom/<versión>/` se monta en ese
contenedor, así que ahí van también las cosas por versión que no sean `.ini`.

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

Sirve las mismas URLs, incluidas las rutas anidadas y el sufijo `--pNN` — para
proyectos cuyos archivos se corresponden con las URLs.

**Los frameworks también enrutan**, cosa que en nginx normalmente no ocurre. Laravel,
Symfony y WordPress ponen su regla de enrutado en el `.htaccess`, y nginx no lee
`.htaccess` — es una decisión de diseño suya, no una opción. Pero el Lua que ya
resuelve el docroot lee **esa única** regla y se la pasa a un `try_files`:

```apache
RewriteCond %{REQUEST_FILENAME} !-d      # lo que significa try_files $uri $uri/
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.php [L]              # el destino al que cae
```

Un SPA compilado declara lo mismo con `index.html` como destino, y ese se sirve en
vez de pasarlo a PHP. Así, un proyecto enruta si dice que quiere, y el que no — un
sitio estático, una carpeta de páginas `.php` — sigue respondiendo `404` a lo que no
sea un archivo. Con `NGINX_FRONT_CONTROLLER` en `.env` lo cambias:

| | |
|---|---|
| `auto` (por defecto) | respeta la regla que el proyecto declara en su `.htaccess` |
| `always` | trata `index.php` como front controller aunque no haya `.htaccess` — Symfony sin `apache-pack`, WordPress antes de guardar sus enlaces permanentes |
| `off` | nginx a secas: `404` para todo lo que no sea un archivo |

**Solo se lee la regla de enrutado.** Las de denegación, `AuthType`, cabeceras y todo
lo demás del `.htaccess` siguen ignoradas bajo nginx, y lo estarán siempre. Hay además
un caso que difiere: una URL terminada en `.php` dentro de un proyecto cuyo front
controller es un `index.html` responde `404` aquí y la shell en Apache. Por eso Apache
sigue siendo el predeterminado.

Es **OpenResty**, no nginx a secas: el docroot y el backend de PHP se derivan del
nombre del host con Lua, y eso nginx normal no lo puede hacer. Cambiar la imagen base
por `nginx:alpine` no funcionaría.

Son definiciones reales, no YAML comentado, así que `docker compose config` y la CI las
siguen validando y no pueden romperse en silencio.

### 🔨 Escribir un perfil propio

Los servicios de arriba no tienen nada especial: cada uno es un servicio de
compose con una clave `profiles:`. Pon uno en `docker-compose.local.yml` y se
une a ellos — `forge profile` lo descubre solo, así que no hay ninguna lista
donde darlo de alta.

```yaml
services:
  redisdev:
    profiles: ["redis"]          # ← esta línea es todo
    image: redis:7-alpine
    container_name: redisdev
    ports:
      - 127.0.0.1:6379:6379
    restart: unless-stopped
```

Ya está. Nace apagado, hasta que lo pidas:

```console
$ forge profile list
  redis       off  redis:7-alpine
$ forge profile on redis
```

La columna de la imagen sale de los propios ficheros de compose, no de una tabla
que alguien tenga que mantener, así que tu servicio se describe igual que los
que vienen de serie. Una vez encendido, `forge logs redisdev` también funciona —
un servicio de un perfil apagado está oculto para compose, que es justamente por
lo que no cuesta nada tenerlo escrito.

**Llegar desde PHP.** Usa el nombre del servicio como host: los contenedores
comparten red y compose le da ese alias a cada uno. Igual que se llega a los que
vienen de serie:

```php
$redis = new Redis();
$redis->connect('redisdev', 6379);
```

**Llegar desde la máquina** es para lo que está la línea `ports:`, y el
`127.0.0.1:` de delante conviene dejarlo: sin él Docker abre el puerto en todas
las interfaces, que en un portátil significa también el wifi de la cafetería.

**Es tuyo y se queda.** `docker-compose.local.yml` está fuera de git, así que
`git pull` nunca choca con él y `forge update` ni lo mira. La otra cara es que no
viaja: quien clone el repositorio no se lleva tu Redis. Si lo necesita el equipo
entero, su sitio es `docker-compose.override.yml` y un pull request.

## 🤖 Agentes de IA

El repo trae un archivo de skill, `skills/php-devforge/SKILL.md`, que le enseña a
un agente de IA cómo funciona este entorno: `forge run` en vez de `docker exec`,
cómo una carpeta se convierte en URL, los datos de conexión a las bases y al
correo, qué es inmediato y qué necesita reinicio, y las trampas.

El instalador ofrece engancharlo, y después:

```bash
forge skill status     # qué agentes encontró, y cuáles están enganchados
forge skill on         # todos, o: forge skill on codex
forge skill off
forge skill path       # imprime la ruta, para apuntar cualquier otra cosa
```

Solo se le ofrece a un agente cuya carpeta de configuración ya existe, así que no
se crea nada para una herramienta que no usás. Dos formas, porque cada agente
carga las instrucciones distinto:

| Agente | Cómo |
|---|---|
| Claude Code | un symlink en `~/.claude/skills/`, se carga cuando hace falta |
| Codex, Gemini, opencode | un bloque delimitado en su archivo global de instrucciones |

El bloque es corto a propósito: un archivo global está en el contexto de cada
sesión, así que lleva un resumen y la ruta al archivo completo. Va entre
`<!-- php-devforge:start -->` y `<!-- php-devforge:end -->`, se reescribe en su
lugar en vez de agregarse otra vez, y `forge skill off` saca el bloque y la línea
en blanco de antes, dejando el resto del archivo intacto.

## 🛠️ Extensiones y herramientas

**Extensiones de PHP:** GD, Intl, Zip, PDO MySQL, PDO PostgreSQL, SOAP, XSL, BC Math,
OPcache, Mbstring, Exif, PCNTL, Imagick, Redis, APCu, Xdebug

**Herramientas:** Composer, Node.js 24 LTS vía NVM, pnpm, Git, Cron

`NODE_VERSION` en `.env` fija la versión de Node, y aplica cuando construyes tus
propias imágenes — una descargada ya la trae fijada. `npm` sigue funcionando pero te
apunta a pnpm. Xdebug está apagado hasta que lo enciendas con el comando `xdebug`
dentro de un contenedor; tu editor debe escuchar en el puerto **9003**.

## 🐛 Problemas comunes

- **El dominio dejó de resolver tras reinstalar**: `forge dns status` ahora pone
  juntos los tres números que tienen que coincidir — el puerto que pide tu sistema,
  el de `.env` y el que publica dnsmasq. Si no coinciden, `./setup-local-dns.sh`
  apunta el sistema al puerto en uso.
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
  `forge restart`. Reiniciar no basta. Mira también que no haya un archivo en
  `custom/<versión>/php.d/` pisándolo — ese gana.
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

### Publicar una versión

La versión vive en un solo archivo, `VERSION`, y `forge version` la imprime junto al
commit en el que estás:

```bash
$ forge version
PHP DevForge 0.1.0 (c45e1f3)
```

Para publicar una: sube el número en `VERSION` y mergea a `main`. Eso es todo —
el tag y el Release de GitHub pasan solos desde ahí: un cambio en `VERSION` que
llega a `main` se etiqueta automáticamente
(`.github/workflows/tag-on-version-bump.yml`), y ese tag crea el Release
(`.github/workflows/release.yml`, `gh release create --generate-notes`).

Las notas se agrupan solas por etiqueta (`.github/release.yml`): `enhancement`,
`bug`, `documentation` — las mismas que el repo ya trae. Una etiqueta por PR,
la que coincida con el prefijo que ya usa su commit (`feat:`/`fix:`/`docs:`);
un fix que encontraste mientras construías algo nuevo se queda contado en ese
mismo PR, no en una segunda etiqueta.

La CI rechaza un `VERSION` que no sea semver, y un commit etiquetado cuya etiqueta y
`VERSION` no coincidan — así no pueden separarse.

**Las prerelease funcionan igual** — `VERSION=0.3.0-beta.1` se etiqueta y se
publica exactamente igual, solo que el Release queda marcado como prerelease
en GitHub, así que nunca aparece como "latest" (ni en el badge de arriba, ni
para `forge update`, que ignora cualquier tag con sufijo `-` al elegir el más
nuevo). `forge update --edge` sigue `main` igual, sea prerelease o no.

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

Los pasos que piden una página cargan `.github/scripts/serve.sh`, que trae dos
ayudantes: `serves <host> <texto>` verifica que una página contenga algo, y
`serve <host> <ruta>` reintenta durante un minuto y, cuando se rinde, dice por
qué — el estado que recibió, lo que dijo curl, y qué había escuchando en el 443.

**Dos tipos de paso no pueden pasar en local**, y es lo esperado:

| Paso | Por qué | Para ejecutarlo igual |
|---|---|---|
| los de HTTPS | `curl` sin `-k`, a propósito: comprueba el almacén de confianza del sistema | `./install_cert.sh` (pide sudo, instala la CA) |
| los de DNS | reescriben el resolutor del sistema | `./setup-local-dns.sh` (pide sudo) |

Todo lo demás corre contra tus propios contenedores.
