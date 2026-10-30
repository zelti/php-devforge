# Contribuir a PHP DevForge

← [README](README.es.md) · [Documentación](DOCS.es.md) · [English](CONTRIBUTING.md)

---

1. Haz un fork y crea una rama
2. Haz tus cambios
3. Comprueba que la CI pasa — instala y ejecuta todo en una máquina limpia, así que
   detecta bastante
4. Abre un pull request describiendo qué cambia y por qué

La CI construye las tres versiones de PHP, ejecuta el instalador, configura el DNS,
comprueba que un `.php` nunca se sirve como código fuente, que los archivos creados
en los contenedores son tuyos, y que Apache y nginx sirven lo mismo. Si está en
verde, funciona en una máquina que no es la tuya.

## Publicar una versión

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

## Ejecutar un paso de la CI antes de subir

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
