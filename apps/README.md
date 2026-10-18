# apps/ — ec2-apps (BFF + requests + catalog + notify)

Compose del mundo **apps** (una EC2). Cada microservicio trae su propio `Dockerfile` en su repo.

## Local (repos hermanos)

Desde esta carpeta, con los repositorios de BFF, requests, catalog y notify al mismo nivel que `barriodigital-infra`. El arranque y la recuperación habituales utilizan Docker Compose.

Requiere Docker con Compose y soporte `--wait`, credenciales Oracle, wallet de Autonomous y configuración
Entra del BFF. Para la primera configuración, crear los entornos desde las plantillas versionadas:

```bash
cp .env.example .env
cp ../mq/.env.example ../mq/.env
```

Completar ambos archivos antes de continuar. `RABBIT_USER` y `RABBIT_PASSWORD` de Apps deben coincidir con
`RABBITMQ_DEFAULT_USER` y `RABBITMQ_DEFAULT_PASS` de MQ; configurar también la cookie compartida del clúster.
Completar `ORACLE_*` y `AZURE_*` según la tabla de variables. Crear `./wallet` y extraer dentro el ZIP del
wallet descargado desde Oracle Autonomous, o indicar su ubicación mediante `WALLET_HOST_PATH`.
Mantener `EMAIL_MODE=logging` para comprobar el flujo sin enviar correos reales.

```bash
docker compose -f ../mq/compose.yml --env-file ../mq/.env up -d --wait --wait-timeout 180
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build --wait --wait-timeout 180 notify
```

Con Notify saludable, ejecutar la comprobación manual de topología descrita más abajo y revisar sus criterios
de éxito antes de continuar con Requests y los demás servicios:

```bash
docker compose --env-file .env up -d --build
docker compose ps
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8081/actuator/health
```

## EC2 (layout plano `~/barriodigital`)

Usar `compose.ec2.yml` cuando BFF, requests, catalog, wallet y `.env` viven juntos. Catalog se construye antes y el BFF espera su health: si se recrea el BFF con catalog caído, el alta responde 503.

Los archivos son independientes: no combinar ambos con `-f`. Añadir también el repo de Notify al layout plano. Configurar `RABBIT_ADDRESSES` con el DNS o IP privada de EC2-MQ y AMQP accesible desde EC2-Apps. No sirven `localhost` ni los nombres Docker de otro host. La configuración remota actual ofrece solo el endpoint del nodo 1, sin failover al nodo 2. No se añade una red bridge entre EC2 distintas.

Para preparar ese layout desde un clon limpio, situarse en el directorio que contiene los repositorios
hermanos, incluido `barriodigital-infra`. Copiar los archivos versionados para la primera configuración:

```bash
cp barriodigital-infra/apps/compose.ec2.yml compose.ec2.yml
cp barriodigital-infra/apps/.env.example .env
```

Completar `.env` con los valores de ese entorno y extraer el wallet en `./wallet` antes de iniciar servicios.
Si esos archivos ya existen, conservar su configuración al actualizar.

```bash
docker compose -f compose.ec2.yml --env-file .env config --quiet
docker compose -f compose.ec2.yml --env-file .env up -d --build --wait --wait-timeout 180 notify
```

MQ debe haberse iniciado en EC2-MQ con su Compose y configuración privada, según `../mq/README.md`. El operador
ejecuta allí las consultas de topología de la sección siguiente. Tras revisarlas, continuar en EC2-Apps:

```bash
docker compose -f compose.ec2.yml --env-file .env up -d --build
```

## Variables (`.env`, no subir a git)

Plantilla en `.env.example`; los valores de Entra ID están en `../docs/decisiones.md`.

| Variable | Qué va |
|----------|--------|
| `AZURE_ISSUER_URI` | Issuer v2 del tenant |
| `AZURE_AUDIENCES` | `api://<clientId>,<clientId>`. El GUID es obligatorio: los tokens v2 lo traen en `aud` y, sin él, el BFF responde 401 "Audience inválido" |
| `ORACLE_URL` | `jdbc:oracle:thin:@barriodig_low?TNS_ADMIN=/wallet` (dentro del contenedor el wallet se monta en `/wallet`) |
| `ORACLE_USER`, `ORACLE_PASSWORD` | Usuario de la aplicación en Oracle. Si la password tiene `$`, en este `.env` va como `$$` |
| `CORS_ALLOWED_ORIGINS` | Orígenes del front separados por coma; por defecto `http://localhost:4200` |
| `WALLET_HOST_PATH` | Solo `compose.yml`: ruta del wallet en el host; por defecto `./wallet` |
| `CATALOG_BASE_URL` | `http://catalog:8082`. El compose se la pasa al BFF. Catalog usa las mismas `ORACLE_*` y el mismo wallet |
| `RABBIT_ADDRESSES`, `RABBIT_USER`, `RABBIT_PASSWORD` | Se pasan explícitamente a Requests y Notify. Local: nodos de la red MQ; EC2: endpoint privado del nodo 1 |
| `RABBIT_NETWORK_NAME` | Solo local: red externa MQ compartida por Requests y Notify |

## Puertos

- **BFF, 8080.** En producción el front no lo llama directo: las peticiones entran por el API Gateway, que las reenvía a este puerto (ver `../docs/decisiones.md`).
- **requests, 8081.** Los dos compose lo publican en el host (sirve para el health check local), así que en la EC2 el security group no debe abrir el 8081, solo el 8080.
- **catalog, 8082.** Solo `expose`, sin `ports`. No se abre en el security group. El health se mira dentro del contenedor: `docker compose exec catalog curl -f http://localhost:8082/actuator/health`.
- **notify, 8083.** Solo `expose`, sin `ports`, rutas públicas, BFF ni API Gateway. `docker compose exec notify curl -fsS http://localhost:8083/actuator/health`.

## Notify y certificados (EP2-18)

Los dos Compose construyen Notify con su Dockerfile. Pasan explícitamente `RABBIT_ADDRESSES`, `RABBIT_USER`, `RABBIT_PASSWORD`, `EMAIL_MODE`, `EMAIL_FROM` y las variables `SMTP_*` de la plantilla. `--env-file` permite interpolar: no inyecta automáticamente todo el archivo. Logging es el modo de correo predeterminado y no envía mensajes reales. SMTP se activa con `EMAIL_MODE=smtp` y su configuración completa.

En local Notify y Requests usan las redes de Apps y `${RABBIT_NETWORK_NAME:-barriodigital-mq_default}`; RabbitMQ se resuelve como `rabbitmq-1:5672,rabbitmq-2:5672`. Si se cambia el proyecto MQ con `-p`, ajustar `RABBIT_NETWORK_NAME`.

En ambos entornos `CERTIFICATE_OUTPUT_DIR=/app/data/certificates` coincide con el montaje de lectura/escritura `certificates:/app/data/certificates`. El volumen nombrado pertenece al proyecto Apps; con su nombre actual es `barriodigital-apps_certificates`. Recrear Notify o un `down` normal conserva los PDF. **`down -v` elimina ese volumen y sus certificados.** No utilizarlo para actualizar Notify. Los datos son locales al host, no compartidos entre EC2 ni entre motores Docker.

La imagen mantiene el usuario de su base, root por defecto, y prepara el directorio. No necesita permisos 777. Comprobar el UID y la escritura sobre el montaje real después de construir. El generador escribe un temporal en ese mismo directorio y publica mediante movimiento atómico; un proveedor sin esa capacidad produce error recuperable, sin escritura directa sobre el PDF final.

## Comprobación manual de topología de email y cuadrillas

Después de iniciar MQ y Notify, comprobar el health desde Apps. En local, desde esta carpeta:

```bash
docker compose --env-file .env exec notify curl -fsS --max-time 4 http://localhost:8083/actuator/health
```

En el layout plano de EC2-Apps, usar el archivo independiente:

```bash
docker compose -f compose.ec2.yml --env-file .env exec notify curl -fsS --max-time 4 http://localhost:8083/actuator/health
```

Se espera HTTP correcto y `status: UP`. En el host Docker de MQ (local o, por el operador, en EC2-MQ),
consultar sin publicar ni consumir mensajes:

```bash
docker exec rabbitmq-1 rabbitmqctl --quiet --timeout 10 list_exchanges --vhost / name type durable auto_delete
docker exec rabbitmq-1 rabbitmqctl --quiet --timeout 10 list_queues --vhost / name durable auto_delete arguments consumers
docker exec rabbitmq-1 rabbitmqctl --quiet --timeout 10 list_bindings --vhost / source_name destination_name destination_kind routing_key arguments
```

Los comandos deben terminar correctamente. Revisar los siguientes valores antes de continuar con el
`docker compose up -d --build` de Apps:

| Recurso | Criterio de éxito |
|---|---|
| `cmd.topic` | Tipo `topic`, durable `true`, auto-delete `false` |
| `cmd.direct` | Tipo `direct`, durable `true`, auto-delete `false` |
| `cmd.dead.dlx` | Tipo `direct`, durable `true`, auto-delete `false` |
| `q.cmd.email` | Durable `true`, auto-delete `false`, `x-dead-letter-exchange=cmd.dead.dlx` y `x-dead-letter-routing-key=email.dead` |
| `q.cmd.email.dlq` | Durable `true`, auto-delete `false`, argumentos vacíos y ningún consumidor |
| Binding principal de email | Origen `cmd.topic`, destino de tipo `queue` `q.cmd.email`, routing key `email.*`, argumentos vacíos; cubre `email.admitted`, `email.visit` y `email.resolved` |
| Binding DLQ de email | Origen `cmd.dead.dlx`, destino de tipo `queue` `q.cmd.email.dlq`, routing key `email.dead`, argumentos vacíos |
| `q.cmd.crew` | Durable `true`, auto-delete `false`, `x-dead-letter-exchange=cmd.dead.dlx` y `x-dead-letter-routing-key=crew.dead` |
| `q.cmd.crew.dlq` | Durable `true`, auto-delete `false`, argumentos vacíos y ningún consumidor |
| Binding principal de cuadrillas | Origen `cmd.direct`, destino de tipo `queue` `q.cmd.crew`, routing key `crew.ticket`, argumentos vacíos |
| Binding DLQ de cuadrillas | Origen `cmd.dead.dlx`, destino de tipo `queue` `q.cmd.crew.dlq`, routing key `crew.dead`, argumentos vacíos |

Las colas siguen el contrato de colas clásicas. Con una instancia de Notify se espera un consumidor en
cada una de `q.cmd.email` y `q.cmd.crew`, y ninguno en sus DLQ; su presencia no sustituye la revisión de
recursos y enlaces. Estas consultas utilizan los
permisos operativos existentes en el host MQ y la cookie del contenedor; no añaden permisos administrativos
al usuario AMQP de Requests. Management permanece en loopback.

El health acredita conexión, no toda la topología; `depends_on: service_healthy` tampoco comprueba bindings.
Esta revisión es manual: corregir cualquier recurso o enlace faltante antes de continuar. Requests conserva
`restart: unless-stopped` en EC2, pero los reinicios automáticos de Docker no repiten la revisión ni garantizan
el orden entre servicios.

Las pruebas y el resumen de integración se documentan en el repo `ms-barriodigital-requests` → `README.md`.
