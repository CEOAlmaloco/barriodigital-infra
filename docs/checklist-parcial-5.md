# Checklist — Evaluación Parcial N°5 (EP5 Kafka / hito EP3)

Corte: 12 de noviembre de 2026.  
Fuente: Evaluación Parcial N°5 — Encargo (DSY1107, 12%, parejas).

Leyenda: `[x]` evidencia en `develop` · `[~]` parcial (falta E2E EP3-56 o un tramo) · `[ ]` pendiente.

---

## Indicadores (100%)

| # | Indicador | % | Estado | Evidencia |
|---:|---|---:|---|---|
| 1 | Configuración completa del cliente Kafka (brokers Docker Compose, serializers, groups, props para publicar/consumir con particiones y réplicas) | 12 | [x] | `spring.kafka` + `KafkaConfig` / listeners en requests, report, audit, kafka-admin. Clúster: `kafka/compose.yml` [PR 53](https://github.com/CEOAlmaloco/barriodigital-infra/pull/53), EC2 [PR 56](https://github.com/CEOAlmaloco/barriodigital-infra/pull/56). Contrato particiones/réplicas [PR infra 45](https://github.com/CEOAlmaloco/barriodigital-infra/pull/45) |
| 2 | Productores y consumidores sobre **los dos tópicos** del sistema, con DTO tipados y lectura/escritura coherente | 12 | [~] | Tópicos `requests.events` y `audit.timeline`. Productor outbox/relay [PR requests 27](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/27)–[28](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/28); productores admin→`audit.timeline` (catalog/mq/kafka-admin). Consumidores: report [PR 2](https://github.com/CEOAlmaloco/ms-barriodigital-report/pull/2), audit timeline [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-audit/pull/3). Falta E2E en lab (EP3-56) y cierre EP3-40 si aplica |
| 3 | Microservicio administrador: crear, listar o mantener tópicos y configuraciones básicas | 6 | [x] | `TopicController` + `KafkaAdminService` [PR kafka-admin 2](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/2)–[4](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/4)/[7](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/7). Proxy BFF [PR 29](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/29) |
| 4 | Productores Kafka con DTO y serializers adecuados | 14 | [x] | `OutboxRelay` + `KafkaTemplate` (JSON); eventos tipados en outbox. Publicación admin en `audit.timeline` (catalog/mq-admin/kafka-admin) |
| 5 | Consumidores con `@KafkaListener` (o equivalente), lógica de negocio separada de la mensajería | 14 | [~] | report/audit: listeners en `messaging/`, dominio en `*Service`. Ver rúbrica §5. Completar consumidores en EC2 |
| 6 | Manejo de errores en el procesamiento (validación, logging, reintentos) sin tumbar el sistema | 12 | [x] | Error handler + DLT (`*.DLT`); replay en kafka-admin [PR 5](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/5)/[8](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/8). Contrato [PR infra 46](https://github.com/CEOAlmaloco/barriodigital-infra/pull/46) |
| 7 | Parámetros de administración de tópicos: retención, cleanup policy, particiones, factor de réplica | 12 | [x] | Contrato EP3-01/03 (3 particiones, 3 réplicas, retención/compactación). API update configs/partitions en kafka-admin. Evidencia UI: [`evidencias/ec2-kafka-ui.png`](evidencias/ec2-kafka-ui.png) |
| 8 | Consumer groups para balanceo o resiliencia entre microservicios | 12 | [x] | `report-group` y `audit-group` (grupos distintos, misma o distinta suscripción). API groups/lag/reset [PR kafka-admin 3](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/3)/[5](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/5) |
| 9 | Admin o scripts de infra: crear/actualizar/inspeccionar **tópicos y consumer groups** de forma controlada y replicable | 6 | [x] | kafka-admin (topics + groups + DLT) + compose Kafka/UI. Gateway rutas `/api/kafka/**` [PR infra 68](https://github.com/CEOAlmaloco/barriodigital-infra/pull/68) |

**Total ponderación indicadores: 100%.**

La matriz de funcionalidades **no** es un indicador de esta pauta (sí respaldo de presentación): [`matriz-funcionalidades.md`](matriz-funcionalidades.md).

---

## Requisitos transversales (páginas 1–2 del encargo)

| Requisito | Estado | Evidencia |
|---|---|---|
| Backend Spring Boot multi-MS; frontend Angular | [x] | Repos listados abajo |
| Backend compila y pasa pruebas básicas | [ ] | Correr `.\mvnw.cmd -q test` en cada MS **el día de entrega** |
| Frontend modular, sin errores de compilación, vistas funcionales | [ ] | `ng test` + `ng build` el día de entrega |
| Persistencia cloud Oracle (entidades, repos, props) | [x] | requests, catalog, report, audit |
| JWT / IDaaS (BFF + MSAL frontend) | [x] | Gateway `entra-jwt`, `AzureSecurityConfig`, Amplify |
| `.gitignore` (solo lo de la tecnología; sin `.env`/secretos) | [x] | Revisado 12-nov en los 10 repos (regla `.env` presente) |
| Productores/consumidores **RabbitMQ** + DLQ/logs | [x] | requests + notify; mq-admin; checklist Rabbit previo |
| Admin RabbitMQ: crear/eliminar colas, exchanges, bindings | [x] | `ms-barriodigital-mq-admin` |
| Productores/consumidores **Kafka** | [~] | Código en `develop`; E2E lab = EP3-56 |
| Admin Kafka: crear/modificar/eliminar tópicos y configs | [x] | kafka-admin |
| `docker-compose` clúster RabbitMQ | [x] | `mq/compose.yml` — `config --quiet` OK 12-nov |
| `docker-compose` Kafka + Zookeeper + brokers | [x] | `kafka/compose.yml` — `config --quiet` OK 12-nov |
| `docker-compose` Kafka UI | [x] | incluido en `kafka/compose.yml`; evidencia [`ec2-kafka-ui.png`](evidencias/ec2-kafka-ui.png) |
| Kafka **no rompe** RabbitMQ | [~] | Diseño: Rabbit=comandos, Kafka=hechos. Regresión E2E en EP3-56 |

---

## Entrega AVA

### Enlaces (copiar a AVA + correo docente)

- https://github.com/CEOAlmaloco/barriodigital-infra
- https://github.com/CEOAlmaloco/frontend-barriodigital
- https://github.com/CEOAlmaloco/ms-barriodigital-bff
- https://github.com/CEOAlmaloco/ms-barriodigital-requests
- https://github.com/CEOAlmaloco/ms-barriodigital-catalog
- https://github.com/CEOAlmaloco/ms-barriodigital-notify
- https://github.com/CEOAlmaloco/ms-barriodigital-mq-admin
- https://github.com/CEOAlmaloco/ms-barriodigital-report
- https://github.com/CEOAlmaloco/ms-barriodigital-audit
- https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin

- [ ] Enviar la misma lista al correo del docente.

### `main` ← `develop` (12-nov-2026)

| Repo | compare `main...develop` |
|---|---|
| barriodigital-infra | diverged (ahead 53 / behind 4) |
| frontend-barriodigital | ahead 11 |
| ms-barriodigital-bff | diverged (14 / 3) |
| ms-barriodigital-requests | diverged (33 / 3) |
| ms-barriodigital-catalog | diverged (6 / 2) |
| ms-barriodigital-notify | diverged (2 / 2) |
| ms-barriodigital-mq-admin | ahead 2 |
| ms-barriodigital-report | ahead 8 |
| ms-barriodigital-audit | ahead 6 |
| ms-barriodigital-kafka-admin | ahead 15 |

- [ ] Sincronizar `main` desde `develop` en todos antes de AVA (sin force a `main` sin acuerdo).

---

## Cierre EP3-59

1. [x] Los 9 indicadores de la pauta con evidencia marcada.
2. [~] Transversales: gitignore + compose OK; **tests/build del día** y sync `main` pendientes.
3. [~] Entrega: enlaces listos; correo y `main` pendientes.
4. [ ] EP3-56 (flujo cloud) para pasar `[~]` de Kafka E2E a `[x]`.
