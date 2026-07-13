# Desplegar Koha en Railway

Koha es un sistema grande: además de la app Perl necesita **MySQL/MariaDB**,
un motor de búsqueda (aquí usamos **Elasticsearch**, así evitamos Zebra) y,
opcionalmente, **Memcached**. Este repo ya trae `Dockerfile`,
`docker/entrypoint.sh` y `docker/koha-conf.xml.template` para correrlo
directamente desde el código fuente (modo "dev install", el mismo que usa
`koha-testing-docker`), sin necesidad de empaquetar `.deb`.

La build compila ~150 dependencias de CPAN, así que la primera build puede
tardar 15-30 minutos.

## 1. Servicios que necesitás crear en Railway

En un mismo proyecto de Railway:

1. **MySQL** — desde el marketplace de Railway ("+ New" → "Database" →
   "MySQL"). Railway expone automáticamente las variables `MYSQLHOST`,
   `MYSQLPORT`, `MYSQLDATABASE`, `MYSQLUSER`, `MYSQLPASSWORD`.
2. **Elasticsearch** — desde el marketplace ("+ New" → busca "Elasticsearch")
   o desplegalo vos con la imagen `docker.elastic.co/elasticsearch/elasticsearch:8.x`
   (con `discovery.type=single-node` y `xpack.security.enabled=false` para
   simplificar). Anotá el host:puerto interno que te da Railway.
3. **(Opcional) Memcached** — mejora el rendimiento de sesiones/cache;
   podés omitirlo y dejar `MEMCACHED_SERVERS` vacío.
4. **koha-staff** — servicio desde este repo (build con Dockerfile), es la
   interfaz de personal (`/cgi-bin/koha/...`).
5. **koha-opac** — un **segundo servicio desde el mismo repo/Dockerfile**,
   para el catálogo público.

## 2. Variables de entorno

En **ambos** servicios (`koha-staff` y `koha-opac`) configurá:

| Variable | Valor |
|---|---|
| `DB_TYPE` | `mysql` |
| `DB_HOST` | `${{MySQL.MYSQLHOST}}` |
| `DB_PORT` | `${{MySQL.MYSQLPORT}}` |
| `DB_NAME` | `${{MySQL.MYSQLDATABASE}}` |
| `DB_USER` | `${{MySQL.MYSQLUSER}}` |
| `DB_PASS` | `${{MySQL.MYSQLPASSWORD}}` |
| `ELASTICSEARCH_SERVERS` | host:puerto de tu servicio Elasticsearch |
| `MEMCACHED_SERVERS` | host:puerto de Memcached, si lo agregaste |
| `API_SECRET_PASSPHRASE` | string aleatorio fijo (generalo una vez y reusalo) |
| `ENCRYPTION_KEY` | 32 caracteres hex fijos (generalo una vez) |
| `BCRYPT_SETTINGS` | dejalo sin definir, se autogenera si falta (ver nota) |

> **Importante:** `API_SECRET_PASSPHRASE`, `ENCRYPTION_KEY` y
> `BCRYPT_SETTINGS` deben ser **iguales y estables** entre `koha-staff` y
> `koha-opac`, y no deberían cambiar entre deploys — si no, se invalidan
> sesiones y datos cifrados. El `entrypoint.sh` genera valores aleatorios si
> faltan (con un warning en los logs), pero para producción fijalos vos
> como variables de Railway.

Además, en cada servicio seteá cuál app sirve:

- `koha-staff`: `SERVICE=intranet`
- `koha-opac`: `SERVICE=opac`

Railway inyecta `PORT` automáticamente; el `entrypoint.sh` lo usa para
levantar Starman.

## 3. Dominios públicos

Generá un dominio público (`Settings → Networking → Generate Domain`) para
cada uno de los dos servicios. El de `koha-staff` es donde vas a hacer el
setup inicial; el de `koha-opac` es el catálogo público.

## 4. Primer arranque: el instalador web de Koha

La primera vez que abrís la URL de `koha-staff`, Koha te va a redirigir
automáticamente al **instalador web** (`installer/install.pl`), que:

1. Verifica la conexión a la base de datos.
2. Crea el esquema de tablas.
3. Carga los datos obligatorios (idiomas, tipos de item, etc.).
4. Te permite crear el usuario superbibliotecario inicial.

Esto es el mismo asistente que corre cualquier instalación de Koha (por
paquete `.deb` o desde código fuente) — no hace falta scriptear nada, solo
completar el wizard desde el navegador.

Después de terminar el instalador, andá a **Administration → Search engine
configuration** y ejecutá el reindexado con Elasticsearch
(`misc/search_tools/rebuild_elasticsearch.pl`, disponible como Koha Task
también vía la interfaz), para que la búsqueda funcione.

## 5. Trabajos en segundo plano (opcional)

Koha corre tareas de background (recordatorios, indexado async, etc.) vía
`Koha::BackgroundJob`. Si las necesitás, agregá un **tercer servicio**
desde este mismo repo/Dockerfile, con:

- `SERVICE=intranet` (o cualquiera, no importa cuál sirva ya que no expone
  puerto público)
- Custom Start Command: `perl /app/misc/background_jobs_worker.pl`
- Sin dominio público asignado.

## 6. Limitaciones conocidas de este setup

- **Sin Zebra**: se usa Elasticsearch como único motor de búsqueda
  (soportado nativamente desde Koha 22.11+).
- **Sin SIP2 / cron nativo de Debian**: si necesitás el servidor SIP2 o
  cronjobs (`misc/cronjobs/`), hay que agregarlos como servicios Railway
  adicionales con su propio Custom Start Command.
- **Build larga**: compilar el árbol de CPAN completo (~150 módulos) tarda
  bastante en la primera build; las siguientes son más rápidas gracias al
  cache de capas de Docker mientras no cambie `cpanfile`.
