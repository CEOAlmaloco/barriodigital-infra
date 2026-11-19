# Estado de las funcionalidades

Corte del 18 de noviembre de 2026 (EP3.5-01). Se actualiza cuando se cierra cada parte.

Una fila está **implementada** solo si el comportamiento está en el código mergeado y, cuando corresponde a un servicio o al frontend, corre en el lab. Si falta evidencia, o si solo funciona en local, queda **parcial**. **No implementada** significa que el código de `develop` no hace esa función.

EP3: el backlog EP3 está cerrado. El código de los servicios está en `develop` y el recorrido en la nube ([EP3-56](https://github.com/CEOAlmaloco/frontend-barriodigital/issues/166)) quedó cerrado. El inventario EP3 es histórico: ver [`INVENTARIO_EP3.md`](INVENTARIO_EP3.md). El trabajo nuevo va en el hito EP3.5.

| Estado | Significado |
|---|---|
| implementada | El código está en `develop` y, si es un servicio o el frontend, está en la EC2 o en Amplify |
| parcial | Falta una parte, no está desplegada, o la evidencia no cierra el criterio |
| no implementada | `develop` no lo hace |

## Acceso y borde

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Login con Microsoft en local (`http://localhost:4200`) | implementada | frontend | [PR 25](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/25) |
| Sesión en Amplify | implementada | frontend, Entra | [PR 104](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/104). Con la cuenta vecino, `/inicio` abre la sesión y `/tramites` lista trámites del Gateway |
| JWT en el API Gateway y rechazo por rol en el BFF | implementada | API Gateway, BFF | [PR 34](https://github.com/CEOAlmaloco/barriodigital-infra/pull/34), [PR 1](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/1), [PR 2](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/2) |
| CORS del Gateway y del BFF, sin `*` | implementada | API Gateway, BFF | [PR 34](https://github.com/CEOAlmaloco/barriodigital-infra/pull/34), [PR 4](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/4) |

## Trámites

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Alta de trámite, validando el tipo contra catalog | implementada | BFF, catalog, requests | `POST /api/requests`. [PR 14](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/14), [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/3). El jar desplegado respondió 201 por el Gateway |
| Listar y ver un trámite según el rol | implementada | frontend, BFF, requests | [PR 29](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/29), [PR 4](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/4) |
| Cambio de estado por Funcionario, con transiciones válidas | implementada | frontend, BFF, requests | `PUT /api/requests/{id}/status`. [PR 58](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/58), [PR 11](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/11), [PR 8](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/8) |
| Nombre y correo del solicitante en el alta y en la columna | implementada | requests, BFF, frontend | [PR 12](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/12), [PR 14](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/14), [PR 103](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/103) |
| Aviso «Se envió la notificación al vecino» al cambiar el estado | parcial | frontend | [PR 105](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/105). En admisión, terreno y resolución el snack dice «Estado actualizado. La notificación al vecino se procesa en segundo plano.» en [`requests.component.ts`](https://github.com/CEOAlmaloco/frontend-barriodigital/blob/develop/src/app/features/requests/requests.component.ts). No es el texto del issue [#87](https://github.com/CEOAlmaloco/frontend-barriodigital/issues/87) |

## Catálogo y cupos

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Listar tipos persistidos en Oracle | implementada | catalog | `GET /api/catalog/procedures`. [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/3) |
| Alta y edición de tipos, solo Admin | implementada | catalog, BFF, frontend | [PR 4](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/4), [PR 5](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/5), [PR 60](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/60) |
| El formulario de trámites usa el catálogo, no una lista fija | implementada | frontend | [PR 59](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/59) |
| Cupo diario, reset en hora de Chile, y descuento al admitir | implementada | catalog, BFF, frontend | [PR 7](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/7), [PR 17](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/17), [PR 100](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/100) |
| Reservar y liberar cupo dentro de la red del compose | implementada | catalog | `POST /api/catalog/procedures/{value}/reserve`. [PR 8](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/8) |
| Plazo en días hábiles por tipo de trámite | implementada | catalog, BFF | [PR catalog 14](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/14), [PR BFF 26](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/26). Contrato [`contratos/requests-plazos.md`](contratos/requests-plazos.md) |

## Mensajería

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Topología `cmd.topic`, `cmd.direct`, `cmd.dead.dlx` y las tres colas con DLQ | implementada | notify, requests, infra | [PR 24](https://github.com/CEOAlmaloco/barriodigital-infra/pull/24), [PR 2](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/2) |
| Publicar `email.admitted` y `email.resolved` después del commit | implementada | requests | [PR 17](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/17). En la nube, notify registró los dos en el recorrido de [`rabbitmq.md`](rabbitmq.md) |
| Publicar `crew.ticket` y `email.visit` al pasar a `EN_TERRENO` | implementada | requests | [PR 18](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/18). Un `EN_TERRENO` produjo el ticket y `email.visit` con el mismo `requestId`. [`rabbitmq.md`](rabbitmq.md) |
| Publicar `certificate.receipt` al crear y `certificate.resolved` al resolver | implementada | requests | [PR 19](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/19). notify escribió los dos PDF en el volumen `certificates`. [`rabbitmq.md`](rabbitmq.md) |
| Consumir email, cuadrilla y certificado, con ACK manual y log `mensaje-muerto` | implementada | notify | [PR 4](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/4), [PR 5](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/5), [PR 6](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/6), [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/3). En el clúster de la nube hay un consumidor en cada cola de trabajo |
| Tests de qué se publica en cada transición y de broker caído | implementada | requests | [`RequestStatusEventsHttpTest`](https://github.com/CEOAlmaloco/ms-barriodigital-requests/blob/develop/src/test/java/cl/duoc/barriodigital/requests/web/RequestStatusEventsHttpTest.java) cubre alta, admisión, `EN_TERRENO`, resolución y el fallo de publicación con HTTP 200. [PR 18](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/18), [PR 19](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/19) |
| API de mq-admin detrás del BFF, solo Admin | implementada | mq-admin, BFF | [PR 2](https://github.com/CEOAlmaloco/ms-barriodigital-mq-admin/pull/2), [PR 20](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/20). `bd-mq-admin` corre en la EC2 de apps, sin puerto público. El BFF usa `http://mq-admin:8084`. Por el Gateway, sin token `GET /api/mq/queues` responde 401; con el Admin, 200 y las seis colas; con Funcionario, 403 |

## Despliegue

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Clúster RabbitMQ de dos nodos en la EC2 | implementada | infra | [PR 32](https://github.com/CEOAlmaloco/barriodigital-infra/pull/32). `rabbit@rabbitmq-1` y `rabbit@rabbitmq-2` healthy. El registro de IPs está en el [PR 35](https://github.com/CEOAlmaloco/barriodigital-infra/pull/35) |
| catalog, notify, requests y BFF en la EC2, catalog antes que el BFF | implementada | infra | [PR 27](https://github.com/CEOAlmaloco/barriodigital-infra/pull/27), [PR 31](https://github.com/CEOAlmaloco/barriodigital-infra/pull/31), [PR 35](https://github.com/CEOAlmaloco/barriodigital-infra/pull/35) |
| Frontend de Amplify llamando al Gateway de este lab | implementada | frontend | [PR 104](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/104). La sesión abre en `/inicio` |
| Diagrama de colas y procedimiento para un mensaje muerto | implementada | infra | [`rabbitmq-mensaje-muerto.md`](rabbitmq-mensaje-muerto.md), [PR 36](https://github.com/CEOAlmaloco/barriodigital-infra/pull/36). El mismo sobre se publicó en este lab y quedó en `q.cmd.email.dlq` |
| Flujo completo de trámites con las colas de la nube | implementada | requests, notify, catalog | Recorrido anotado en [`rabbitmq.md`](rabbitmq.md). Issue [#92](https://github.com/CEOAlmaloco/frontend-barriodigital/issues/92) |

## Folio, roles y asignación (EP3)

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Folio legible anual en el trámite | implementada | requests | [PR 24](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/24). Contrato en [`contratos/requests-folio.md`](contratos/requests-folio.md). EP3-56 cerrado |
| Tomar, asignar/reasignar y listar funcionarios | implementada | requests, BFF | [PR requests 25](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/25), [PR BFF 28](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/28). Rutas Gateway en [PR infra 68](https://github.com/CEOAlmaloco/barriodigital-infra/pull/68) |
| Listado paginado, orden y búsqueda | implementada | requests, BFF | [PR requests 26](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/26), [PR BFF 28](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/28) |
| Matriz de capacidades por rol (EP3-04) en el BFF | implementada | BFF | Contrato [`contratos/capacidades-roles.md`](contratos/capacidades-roles.md); [PR infra 50](https://github.com/CEOAlmaloco/barriodigital-infra/pull/50); proxy [PR BFF 28](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/28) |
| Cancelación por el vecino | implementada | requests | [PR 29](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/29), [`contratos/requests-cancelacion.md`](contratos/requests-cancelacion.md) |
| Encuesta de satisfacción | implementada | requests | [PR 30](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/30), [`contratos/requests-encuesta.md`](contratos/requests-encuesta.md) |
| Preferencias de aviso del usuario | implementada | requests | [PR 31](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/31), [`contratos/requests-preferencias.md`](contratos/requests-preferencias.md) |
| Correo `email.rejected` con motivo y folio en notify | implementada | requests, notify | [PR requests 32](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/32), [PR notify 9](https://github.com/CEOAlmaloco/ms-barriodigital-notify/pull/9) |

## Kafka, outbox y administración (EP3)

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Clúster Kafka local (3 ZK + 3 brokers + UI) | implementada | infra | [PR 53](https://github.com/CEOAlmaloco/barriodigital-infra/pull/53) |
| Clúster Kafka en EC2 (`ec2-kafka`) | implementada | infra | [PR 56](https://github.com/CEOAlmaloco/barriodigital-infra/pull/56), evidencias en [`evidencias/EP3-15-ec2-kafka.md`](evidencias/EP3-15-ec2-kafka.md) |
| Outbox + relay a `requests.events` | implementada | requests | [PR 27](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/27), [PR 28](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/28). EP3-56 cerrado |
| kafka-admin: tópicos, groups, DLT, replay, audit | implementada | kafka-admin, BFF | PRs [1](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/1)–[10](https://github.com/CEOAlmaloco/ms-barriodigital-kafka-admin/pull/10); proxy BFF [PR 29](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/29) |
| Publicar cambios de catalog/mq-admin en `audit.timeline` | implementada | catalog, mq-admin | [PR catalog 16](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/16)/[17](https://github.com/CEOAlmaloco/ms-barriodigital-catalog/pull/17), [PR mq-admin 7](https://github.com/CEOAlmaloco/ms-barriodigital-mq-admin/pull/7) |
| Compose apps con report, audit y kafka-admin | implementada | infra | [PR 67](https://github.com/CEOAlmaloco/barriodigital-infra/pull/67). EP3-56 cerrado |
| Rutas Gateway kafka/report/audit + `X-Source-Ip` | implementada | infra, API Gateway | [PR 68](https://github.com/CEOAlmaloco/barriodigital-infra/pull/68). Evidencias [`ep3-55-gateway-401.txt`](evidencias/ep3-55-gateway-401.txt) / [`ep3-55-gateway-403.txt`](evidencias/ep3-55-gateway-403.txt) |

## Report y audit (servicios)

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| report: consumidor + KPIs + plazos | implementada | report | [PR 2](https://github.com/CEOAlmaloco/ms-barriodigital-report/pull/2), [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-report/pull/3), [PR 4](https://github.com/CEOAlmaloco/ms-barriodigital-report/pull/4). Contrato [`contratos/report-audit.md`](contratos/report-audit.md) |
| audit: consumidor `audit.timeline` | implementada | audit | [PR 3](https://github.com/CEOAlmaloco/ms-barriodigital-audit/pull/3). EP3 cerrado en `develop` |
| Proxy BFF `/api/report`, `/api/audit`, `/api/kafka` | implementada | BFF | [PR 29](https://github.com/CEOAlmaloco/ms-barriodigital-bff/pull/29). EP3-56 cerrado |

## Reportería y Auditoría (pantallas)

| Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|
| Pantalla de Reportería | implementada | frontend | [EP3-50](https://github.com/CEOAlmaloco/frontend-barriodigital/issues/160) cerrado; backend report en `develop` |
| Pantalla de Auditoría | implementada | frontend | [EP3-51](https://github.com/CEOAlmaloco/frontend-barriodigital/issues/161) cerrado |
