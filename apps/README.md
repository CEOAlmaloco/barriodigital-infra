# apps/ — ec2-apps (BFF + requests + catalog + notify)

Compose del mundo **apps** (una EC2). Cada microservicio trae su propio `Dockerfile` en su repo.

## Local (repos hermanos)

Desde esta carpeta, con los repositorios de BFF, requests, catalog y notify al mismo nivel que `barriodigital-infra`. Arrancar MQ primero: Notify se conecta a su red externa ya existente, no usa `depends_on` entre proyectos.

```bash
cp .env.example .env   # y completa los valores
docker compose -f ../mq/compose.yml --env-file ../mq/.env up -d
# wallet descomprimido en ./wallet (o WALLET_HOST_PATH)
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build
docker compose ps
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8081/actuator/health
```

## EC2 (layout plano `~/barriodigital`)

Usar `compose.ec2.yml` cuando BFF, requests, catalog, wallet y `.env` viven juntos. Catalog se construye antes y el BFF espera su health: si se recrea el BFF con catalog caído, el alta responde 503.

Los archivos son independientes: no combinar ambos con `-f`. Añadir también el repo de Notify al layout plano. Configurar `RABBIT_ADDRESSES` con el DNS o IP privada de EC2-MQ y AMQP accesible desde EC2-Apps. No sirven `localhost` ni los nombres Docker de otro host. La configuración remota actual ofrece solo el endpoint del nodo 1, sin failover al nodo 2. No se añade una red bridge entre EC2 distintas.

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

## Puertos

- **BFF, 8080.** En producción el front no lo llama directo: las peticiones entran por el API Gateway, que las reenvía a este puerto (ver `../docs/decisiones.md`).
- **requests, 8081.** Los dos compose lo publican en el host (sirve para el health check local), así que en la EC2 el security group no debe abrir el 8081, solo el 8080.
- **catalog, 8082.** Solo `expose`, sin `ports`. No se abre en el security group. El health se mira dentro del contenedor: `docker compose exec catalog curl -f http://localhost:8082/actuator/health`.
- **notify, 8083.** Solo `expose`, sin `ports`, rutas públicas, BFF ni API Gateway. `docker compose exec notify curl -fsS http://localhost:8083/actuator/health`.

## Notify y certificados (EP2-18)

Los dos Compose construyen Notify con su Dockerfile. Pasan explícitamente `RABBIT_ADDRESSES`, `RABBIT_USER`, `RABBIT_PASSWORD`, `EMAIL_MODE`, `EMAIL_FROM` y las variables `SMTP_*` de la plantilla. `--env-file` permite interpolar: no inyecta automáticamente todo el archivo. Logging es el modo de correo predeterminado y no envía mensajes reales. SMTP se activa con `EMAIL_MODE=smtp` y su configuración completa.

En local Notify usa las redes de Apps y `${RABBIT_NETWORK_NAME:-barriodigital-mq_default}`; RabbitMQ se resuelve como `rabbitmq-1:5672,rabbitmq-2:5672`. Si se cambia el proyecto MQ con `-p`, ajustar `RABBIT_NETWORK_NAME`. No se publican puertos adicionales del broker para esta conexión. Detener Notify antes de bajar MQ para liberar su red.

En ambos entornos `CERTIFICATE_OUTPUT_DIR=/app/data/certificates` coincide con el montaje de lectura/escritura `certificates:/app/data/certificates`. El volumen nombrado pertenece al proyecto Apps; con su nombre actual es `barriodigital-apps_certificates`. Recrear Notify o un `down` normal conserva los PDF. **`down -v` elimina ese volumen y sus certificados.** No utilizarlo para actualizar Notify. Los datos son locales al host, no compartidos entre EC2 ni entre motores Docker.

La imagen mantiene el usuario de su base, root por defecto, y prepara el directorio. No necesita permisos 777. Comprobar el UID y la escritura sobre el montaje real después de construir. El generador escribe un temporal en ese mismo directorio y publica mediante movimiento atómico; un proveedor sin esa capacidad produce error recuperable, sin escritura directa sobre el PDF final.

El health utiliza `curl` incluido en la imagen, con intervalos de 20 s, timeout 5 s y 60 s de inicio. `UP` acredita conectividad Rabbit, no la topología completa, SMTP ni la escritura del volumen. Comprobar exchanges, colas y bindings por separado.

No se incorpora `depends_on` de Requests hacia Notify: el publicador no existe aún. Su integración completará el orden de arranque y la garantía de topología. EP2-18 adelanta de EP2-28 el servicio Notify, sus variables, redes, healthcheck y volumen en los dos Compose; reutilizarlos al integrar el resto.

## Validación local de EP2-18

Primero inspeccionar contenedores, redes, volúmenes y puertos. Usar un broker sin tráfico ajeno y entorno sintético no versionado. Si los nombres fijos de los contenedores ya están ocupados, no detenerlos ni reutilizar sus colas. No iniciar BFF, Requests o Catalog para esta validación.

Desde `barriodigital-infra`, con archivos de entorno exclusivos en `.local/ep2-18`:

```powershell
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env config --quiet
docker compose -f apps/compose.ec2.yml --env-file .local/ep2-18/ec2.env config --quiet
docker compose -f mq/compose.yml --env-file .local/ep2-18/mq.env config --quiet
docker compose -f mq/compose.yml --env-file .local/ep2-18/mq.env up -d
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env up -d --build notify
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env exec notify id -u
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env exec notify curl -fsS http://localhost:8083/actuator/health
docker exec rabbitmq-1 rabbitmqctl list_exchanges name type durable
docker exec rabbitmq-1 rabbitmqctl list_queues name durable arguments consumers
docker exec rabbitmq-1 rabbitmqctl list_bindings source_name destination_name routing_key
```

La revisión estática EC2 debe usar un endpoint ficticio claramente identificado para interpolar y no desplegar. Revisar solo build, puertos, redes, montaje, healthcheck y nombres de variables del modelo efectivo; no imprimir `environment` completo con secretos resueltos.

Publicar ambos eventos por Management solo en el broker aislado, con `eventId` nuevos, `cmd.topic`, routing key igual a `type`, JSON UTF-8 y entrega persistente. Los campos mínimos son `requestId` y `procedureType`. Verificar dos archivos, sus logs `certificate-pdf`, un duplicado sin regeneración y un payload inválido en la DLQ. No confundir `routed: true` con generación terminada.

```powershell
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env exec notify sh -c 'sha256sum /app/data/certificates/*.pdf'
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env up -d --no-deps --force-recreate notify
docker compose -f apps/compose.yml --env-file .local/ep2-18/apps.env exec notify sh -c 'sha256sum /app/data/certificates/*.pdf'
```

Comparar nombres y hashes **antes de reenviar eventos**. Después reenviar uno para comprobar reemplazo atómico sobre el montaje real: misma ruta, PDF completo y nueva generación. Verificar que no queden `.part`. Los tests deterministas cubren fallos y preservación del archivo previo; una prueba de permisos por sí sola no basta cuando el proceso es root.

### Resultados del 17/10/2026

Se validaron sintácticamente los tres Compose mediante `config --quiet`, con entornos ficticios no versionados. El modelo EC2 se revisó sin imprimir secretos; `--project-directory ..` permitió comprobar sus contextos contra un layout plano equivalente en el workspace. Esa revisión no acredita conexión o despliegue EC2.

Se construyó Notify y se iniciaron únicamente MQ y Notify, sin recursos BarrioDigital previos ni tráfico ajeno. Se comprobaron tres exchanges, seis colas y nueve bindings, un consumidor por cola principal y ninguno en DLQ. Dos eventos nuevos produjeron PDF y logs posteriores al guardado; el duplicado no regeneró y un payload inválido quedó en la DLQ de certificados.

El montaje resultó `barriodigital-apps_certificates`, lectura/escritura, UID 0, con redes Apps y MQ y sin puerto publicado de Notify. Tras recrear únicamente Notify, ambos hashes permanecieron idénticos **antes de reenviar**. Al reenviar el ingreso cambió solo ese PDF en su misma ruta; no quedaron temporales. También se comprobó conservación al actualizar a la imagen final. Los contenedores de validación se detuvieron al terminar y sus volúmenes se conservaron; los volúmenes MQ nuevos contienen configuración y datos sintéticos de esta validación.

Evidencias locales ignoradas: `.local/ep2-18/topology.json`, `summary.json`, `ec2-model-redacted.json`, logs, copias PDF y `hashes-before.txt`, `hashes-after.txt`, `hashes-reprocessed.txt`. Se usaron los Compose existentes, sin override de arquitectura ni archivos alternativos. No se ejecutó `down -v`, no se modificó AWS y no se enviaron correos reales.
