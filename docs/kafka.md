# Kafka — recorrido en la nube (EP3-56)

Corte: 12 de noviembre de 2026. Learner Lab us-east-1.

## Topología

| Pieza | Valor |
|---|---|
| EC2 Kafka | pública `3.227.22.131` · privada `172.31.0.172` |
| EC2 Apps | pública `3.92.161.52` · privada `172.31.45.131` |
| Bootstrap apps | `172.31.0.172:9092,9093,9094` |
| Kafka UI | `http://3.227.22.131:8090` |
| Gateway | `https://0yo277ntr8.execute-api.us-east-1.amazonaws.com` |

Compose apps: layout JAR (`apps/compose.ec2.jars.yml`). Imágenes `*:ep3`.

## Orden de despliegue aplicado

1. Clúster Kafka (3 brokers + ZK + UI) — ya EP3-15  
2. kafka-admin (crea tópicos sistema)  
3. report + audit  
4. requests + catalog + mq-admin (+ notify)  
5. BFF (+ frontend Amplify ya publicado)

## Criterios

### 1. Tópicos — OK

`GET kafka-admin /api/kafka/topics`: `requests.events`, `audit.timeline`, `requests.events.report.DLT`, `requests.events.audit.DLT`, `audit.timeline.audit.DLT` → **3 particiones / RF 3**.  
Detalle `requests.events`: ISR=3, `min.insync.replicas=2`.  
Evidencia: `docs/evidencias/ep3-56-topics.json`.

### 2. Flujo del trámite + KPIs — OK (parcial timeline HTTP)

Recorrido Vecino→Funcionario sobre `0758ccb6-…` / `BD-2026-000012` (create→take→admit→gestión→terreno→resuelto).  
KPIs &lt; 5 s: `resolvedCount=1`, `lastEventAt` alineado, proyección `RESUELTO`.  
Evidencia: `docs/evidencias/ep3-56-flujo-tramite.txt`.

**Pendiente de producto:** audit aún no expone `GET /api/audit/timeline` ni consume `requests.events` (EP3-40/42 OPEN). El historial con actor está en `request_activity` (requests) y en los eventos de `requests.events`.

### 3. Auditoría de configuración + IP — OK

Cupo `bache` 8→9 con `X-Source-Ip=198.51.100.77` → `procedure-type.updated` en `audit.timeline`.  
Cola `ep356.demo.q` con `X-Source-Ip=203.0.113.50` → `queue.created`.  
Evidencia: `docs/evidencias/ep3-56-audit-config-ip.txt`.

### 4–5. Caos brokers — OK

Un broker down → ISR 2; altas HTTP 201.  
Tres brokers down → cambios de estado HTTP 200; outbox con `relay-detenido … sin confirmacion del broker`; al volver, `relay-reanudado` y eventos publicados en orden de `event_sequence`.  
Evidencia: `docs/evidencias/ep3-56-caos-kafka.txt`.

### 6. report detenido — OK

LAG `report-group` sube; al levantar, LAG=0 y KPIs al día.

### 7. Malformado → DLT — OK (replay API ejercitada)

Mensaje sin `eventType` en `requests.events.report.DLT`. Listado kafka-admin 200. Replay selectivo respondió `OMITIDO/sin destino` (sobre no rejugable tal cual).

### 8. Regresión Rabbit — OK

notify: `email-simulado`, `crew-ticket`, `certificate-pdf` en el mismo corte.

## Remedios Oracle aplicados en lab (no van al jar)

- `processed_events` PK renombrada a `pk_processed_events` (report).  
- `folio` + `folio_counter` (script EP3-28).  
- `request_activity` CHECK `kind` ampliado a `ASIGNACION`/`CALIFICACION`.  
- `outbox_events` recreada con `event_sequence GENERATED ALWAYS AS IDENTITY … ORDER` (script EP3-31). Sin esto el relay abortaba (`El evento no tiene event_sequence`) y no llenaba `requests.events`.

## Redeploy apps (JAR)

1. `mvnw -DskipTests package` por servicio.  
2. `scp` → `~/barriodigital/{servicio}/app.jar`.  
3. `.env`: `KAFKA_BOOTSTRAP_SERVERS`, `INTERNAL_TOKEN`.  
4. `sudo docker compose -f compose.yml --env-file .env up -d --build`.
