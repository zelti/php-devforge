<p align="center">
  <img src="./logo.png" alt="PHP DevForge" width="300px">
</p>

# PHP DevForge

[![Release](https://img.shields.io/github/v/release/zelti/php-devforge)](https://github.com/zelti/php-devforge/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/zelti/php-devforge/actions/workflows/ci.yml/badge.svg)](https://github.com/zelti/php-devforge/actions/workflows/ci.yml)
![PHP](https://img.shields.io/badge/PHP-8.3%20%7C%208.4%20%7C%208.5-777BB4)
[![GitHub last commit](https://img.shields.io/github/last-commit/zelti/php-devforge)](https://github.com/zelti/php-devforge/commits/main)

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

## 🧭 Para quién es

DDEV te da una definición reproducible por proyecto — mejor cuando cada uno necesita
un stack distinto. Herd es la opción nativa más rápida en macOS. PHP DevForge está
pensado para tener muchos proyectos sobre un mismo entorno, sin configurar ninguno.

## 📖 Qué incluye

- **Apache (o nginx) + PHP-FPM 8.3, 8.4 y 8.5** — instala las que quieras, elegidas por petición
- **HTTPS automático** con una CA de confianza local, y DNS comodín que solo toca tu dominio de desarrollo
- **Edición en vivo** — los ficheros están montados, no hay nada que sincronizar
- **Los ficheros siguen siendo tuyos** — los contenedores adoptan tu usuario: ni `sudo` ni `node_modules` imborrables
- **Xdebug** con un interruptor, **Composer**, **Node 24**, **pnpm**
- Opcionales: **PostgreSQL**, **MariaDB**, **capturador de correo**, **Elasticsearch** y **Kibana**

## 🚀 Instalación rápida

```bash
curl -fsSL https://raw.githubusercontent.com/zelti/php-devforge/main/bootstrap.sh | bash
forge start
```

¿Prefieres no mandar un script directo a `bash`? Descárgalo, léelo, y después córrelo:
```bash
curl -fsSL https://raw.githubusercontent.com/zelti/php-devforge/main/bootstrap.sh -o bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

O clónalo tú mismo:
```bash
git clone https://github.com/zelti/php-devforge.git
cd php-devforge
./install.sh            # hace unas preguntas y deja todo listo
forge start
```

Y abre **https://welcome.phpforge.dev**.

## ⌨️ Los comandos que vas a usar

| | |
|---|---|
| `forge start` · `stop` · `status` | levantar el entorno, y ver qué está corriendo |
| `forge link ~/php-devforge/projects/app/public` | publicar un proyecto en `app.phpforge.dev` |
| `forge run composer install` | ejecutar algo en el contenedor correcto |
| `forge shell 8.4` | abrir una shell dentro |
| `forge logs` | seguir los logs — un 500 en blanco casi siempre está aquí |
| `forge php on 8.3 · forge use 8.5` | instalar una versión, o cambiar la de por defecto |
| `forge db on pg18 · forge mail on` | arrancar una base de datos, o el buzón de pruebas |
| `forge tunnel` | una URL pública, para probar el sitio en un móvil de verdad |
| `forge help` | todos |

## 📖 Documentación completa

Todo lo demás — instalar, actualizar, bases de datos, servicios opcionales, nginx, Xdebug, DNS, resolución de problemas y cómo contribuir — está en **[DOCS.es.md](DOCS.es.md)**.

## 📄 Licencia

MIT — ver [LICENSE](LICENSE).
