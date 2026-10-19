# Estado de las funcionalidades

Corte del 18 de octubre de 2026. Se actualiza cuando se cierra cada parte.

Una fila está **implementada** solo si el comportamiento está en el código mergeado y, cuando corresponde a un servicio o al frontend, corre en el lab. Si falta evidencia, o si solo funciona en local, queda **parcial**. **No implementada** significa que el código de `develop` no hace esa función.

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
| Pantalla de Reportería | parcial | frontend | Placeholder. [PR 101](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/101) |
| Pantalla de Auditoría | parcial | frontend | Scaffold, sin datos de auditoría. [PR 102](https://github.com/CEOAlmaloco/frontend-barriodigital/pull/102) |

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
