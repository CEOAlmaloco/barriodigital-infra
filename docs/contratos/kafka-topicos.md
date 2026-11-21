<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: tópicos y eventos Kafka (EP3-01)

Define qué tópicos de Kafka existen, quién publica y consume en cada uno, con qué parámetros, y la forma exacta de cada evento. Kafka **no reemplaza** a RabbitMQ: los comandos hacia notify (correos, tickets y PDF) siguen por RabbitMQ según EP2-01, EP2-02 y EP2-03, sin cambios. Kafka transporta los hechos del sistema para analítica (report) y auditoría (audit).

Cómo se publican y se consumen estos eventos (outbox, relay, reintentos, DLT e idempotencia) está en EP3-02. La API de administración de Kafka está en EP3-03.

### 1. Tópicos

| Tópico | Contenido | Productores | Consumidores (grupo) |
|---|---|---|---|
| `requests.events` | Hechos del trámite: alta, cambio de estado, gestión y asignación | requests | report (`report-group`), audit (`audit-group`) |
| `audit.timeline` | Operaciones administrativas exitosas: cambios del catálogo y operaciones sobre RabbitMQ y Kafka | catalog, mq-admin, kafka-admin | audit (`audit-group`) |
| `requests.events.report.DLT` | Mensajes de `requests.events` que report no pudo procesar | report | Ninguno. Se revisan y reprocesan desde kafka-admin |
| `requests.events.audit.DLT` | Mensajes de `requests.events` que audit no pudo procesar | audit | Ninguno |
| `audit.timeline.audit.DLT` | Mensajes de `audit.timeline` que audit no pudo procesar | audit | Ninguno |

report y audit leen `requests.events` con grupos distintos, así que cada uno recibe todos los eventos. Dentro de un mismo grupo, las particiones se reparten entre las instancias.

EP3.5 suma los tópicos `field.events` ([`dominio-contextos.md`](dominio-contextos.md), sección 5.1) y `notify.events` ([`comunicaciones.md`](comunicaciones.md), sección 8), con los mismos parámetros que `requests.events`.

Hay una DLT por consumidor y no una por tópico: `requests.events` tiene dos consumidores, y una sola DLT mezclaría sus fallas.

Solo kafka-admin crea tópicos. El broker tiene `auto.create.topics.enable=false`, y los demás servicios no declaran `NewTopic` y llevan `spring.kafka.admin.auto-create=false`.

### 2. Parámetros

| Parámetro | `requests.events` | `audit.timeline` | DLT |
|---|---|---|---|
| Particiones | 3 | 3 | 3 |
| Réplicas | 3 | 3 | 3 |
| `min.insync.replicas` | 2 | 2 | 2 |
| `cleanup.policy` | `delete` | `compact,delete` | `delete` |
| `retention.ms` | 604800000 (7 días) | 2592000000 (30 días) | 1209600000 (14 días) |
| `min.compaction.lag.ms` | No aplica | 604800000 (7 días) | No aplica |
| `message.timestamp.type` | `CreateTime` (por defecto) | `CreateTime` (por defecto) | `LogAppendTime` |

Todos los productores usan `acks=all` y `enable.idempotence=true`. Con 3 réplicas y `min.insync.replicas=2`:
- **con un broker caído**, se sigue escribiendo y leyendo sin pérdida;
- **con dos caídos**, el productor no puede escribir. En requests los eventos esperan en el outbox (EP3-02).

**`requests.events`, `delete` y 7 días.** Son hechos para analítica. Siete días permiten que report reconstruya sus KPIs desde cero reiniciando sus offsets. Está dentro del rango de 3 a 7 días del caso base.

**`audit.timeline`, `compact,delete` y 30 días.** El registro histórico definitivo de la auditoría vive en Oracle: audit guarda cada evento y recién después confirma el offset (EP3-02). El tópico cumple dos funciones:
- durante **al menos 7 días** conserva el historial completo, porque `min.compaction.lag.ms` impide compactar antes;
- después, y hasta los 30 días, conserva el último evento de cada recurso.

Está dentro del rango de 14 a 30 días del caso base. La compactación nunca afecta lo ya guardado en Oracle.

**DLT, `delete` y 14 días.** Es el plazo para diagnosticar y reprocesar. Está dentro del rango de 7 a 14 días del caso base.

- **`LogAppendTime`:** el recoverer publica en la DLT con el timestamp del registro original. Con `CreateTime`, un mensaje que falla el día 7 llegaría con fecha del día 0 y se borraría el día 14, con 7 días para revisarlo y no 14. Con `LogAppendTime`, el broker reemplaza el timestamp por la hora de llegada, así que los 14 días se cuentan desde que el mensaje entra a la DLT. El timestamp original queda en el header `kafka_dlt-original-timestamp` (EP3-02).
- **Particiones:** cada DLT tiene al menos tantas particiones como su tópico de origen, porque el recoverer publica en la partición con el mismo número que la de origen. Si la DLT tuviera menos, el envío fallaría y la partición de origen quedaría detenida (EP3-02). Como a los tópicos del sistema no se les aumentan particiones (EP3-03), la regla no se puede romper desde la API.

**Regla entre retenciones.** Report reconoce un duplicado mientras su `eventId` siga en `processed_events`, que conserva 30 días (EP3-02). El peor caso de llegada de un duplicado a report es:

1. **Día 0:** report procesa el evento.
2. **Hasta el día 7:** audit, atrasado, lo lee, falla y lo envía a `requests.events.audit.DLT`.
3. **Hasta el día 21:** se reprocesa desde esa DLT al final de sus 14 días, y vuelve a `requests.events`, donde lo leen todos los grupos.
4. **Hasta el día 28:** report, atrasado otra vez, lee esa copia.

Por eso: **2 × la retención de `requests.events` + la retención de su DLT ≤ 30 días**. Con los valores actuales da 28 días. Los rangos editables de EP3-03 (`requests.events` de 3 a 7 días y DLT de 7 a 14 días) cumplen la regla en su máximo. La regla vale para un solo replay del mismo mensaje (EP3-02, sección 10).

### 3. Keys y orden

| Tópico | Key | Efecto |
|---|---|---|
| `requests.events` | `requestId` | Todos los eventos de un trámite van a la misma partición y se consumen en orden |
| `audit.timeline` | `<resourceType>:<resourceId>` | Ordena los eventos de un mismo recurso y define qué conserva la compactación |
| DLT | La del mensaje original | El replay vuelve a la misma partición del tópico original |

A los tópicos del sistema no se les aumentan particiones (EP3-03). Hacerlo cambiaría la partición que corresponde a cada key, y los eventos nuevos de un trámite podrían procesarse antes que los anteriores.

Ejemplos de key en `audit.timeline`: `procedure-type:bache`, `queue:q.demo.avisos`, `binding:demo.topic/q.demo.avisos/aviso.nuevo`, `topic:pruebas.carga`, `consumer-group:report-group`.

### 4. Sobre

Todos los eventos de los dos tópicos comparten el mismo sobre.

| Campo | Tipo | Nulo | Nota |
|---|---|---|---|
| `eventId` | uuid | No | Único por evento. Base de la idempotencia de los consumidores |
| `eventType` | string | No | Tipo de evento (secciones 6 y 7) |
| `schemaVersion` | entero ≥ 1 | No | Versión del formato de ese `eventType` (sección 11) |
| `occurredAt` | instant | No | Momento en que ocurrió el hecho, no el de la publicación |
| `producer` | string | No | `requests`, `catalog`, `mq-admin` o `kafka-admin` |
| `traceId` | uuid | No | Identifica la operación que originó el evento |
| `sequence` | entero | No | **Solo en `requests.events`.** Número del outbox |
| `actor.id` | string | No | `oid` del JWT, o `sub` si falta |
| `actor.name` | string | No | Nombre del usuario. Si falta, el id o "Sin nombre", con el mismo respaldo que requests |
| `actor.role` | string | No | El rol de quien actuó. Cada usuario tiene un solo rol (EP3-04, sección 4) |
| `actor.sourceIp` | string | Sí | **Solo en `audit.timeline`.** IP de origen (sección 9) |
| `payload` | objeto | No | Datos del caso, según el `eventType` |

**Diferencias con el sobre de RabbitMQ (EP2-01), deliberadas:**
- **`eventType` y no `type`:** distingue el tipo del evento de dominio del nombre del comando de RabbitMQ.
- **`occurredAt` y no `timestamp`:** en RabbitMQ `timestamp` es el momento de la publicación. En Kafka, con el outbox, la publicación puede ocurrir segundos o minutos después del hecho (por ejemplo, con Kafka caído), y los KPIs y plazos tienen que medirse con la hora real del hecho.
- **No hay `correlationId`:** en `requests.events` la key y `payload.requestId` cumplen ese rol.

No se deben unificar estos nombres con los de EP2-01.

**`sequence`.** Se obtiene de la columna `event_sequence` de `outbox_events`, que es identity con `ORDER` (la columna no se llama `sequence` porque es palabra clave de Oracle; EP3-02). El relay la incorpora al sobre en el momento de publicar, porque el número se conoce recién al insertar la fila en el outbox. Garantiza el orden real de los eventos de un mismo trámite (EP3-02). Los consumidores que mantienen el estado actual de un trámite ignoran un evento con `sequence` menor al último aplicado para ese trámite, sin dejar de contarlo en las métricas históricas. En report, la comparación es por aspecto del trámite (EP3-02, sección 9.3).

**`traceId`.** Lo genera cada productor como un UUID al iniciar la operación. En requests, el evento de Kafka y los comandos de RabbitMQ que salen del mismo cambio comparten el mismo `traceId`. Un evento reprocesado desde la DLT conserva el suyo.

### 5. Formatos y nulos

| Tipo | Formato en el JSON |
|---|---|
| uuid | String en minúsculas de 36 caracteres |
| instant | String ISO-8601 en UTC con `Z`. Los consumidores aceptan fracciones de segundo de cualquier precisión |
| enum | String en mayúsculas con el nombre del enum Java (`EN_TERRENO`, `LLAMADA`, `NO_CONTESTA`) |
| rol | `Admin`, `Funcionario`, `Vecino` o `Auditor`, sin el prefijo `ROLE_` |
| número | Number de JSON: `latitude` y `longitude` decimales, `sequence` y `slaBusinessDays` enteros |

Reglas:

1. **Un campo opcional se envía siempre**, con `null` si no aplica. Todos los eventos de un mismo tipo tienen la misma forma.
2. **Los campos propios de un tópico no aparecen en el otro.** `sequence` no existe en `audit.timeline` y `actor.sourceIp` no existe en `requests.events`: no se envían como `null`, simplemente no están.
3. **`latitude` y `longitude` van juntos:** los dos con valor o los dos en `null`. Un evento con uno solo es malformado.
4. **Los consumidores ignoran los campos que no conocen.** No se activa `FAIL_ON_UNKNOWN_PROPERTIES` de Jackson. Esto permite agregar campos opcionales sin romper consumidores (sección 11).
5. **El JSON se publica sin headers de tipo Java** (`spring.json.add.type.headers=false`). Cada servicio tiene sus propios records, y este contrato es la única definición compartida.

### 6. Eventos de `requests.events`

Los publica requests. Todos son versión 1.

| `eventType` | Cuándo |
|---|---|
| `request.created` | Alta del trámite, que queda en `INGRESADO` |
| `request.status-changed` | Cualquier cambio de estado válido vía PUT `/status`, incluidos `EN_GESTION` y `RECHAZADO` |
| `request.cancelled` | Cancelación del titular: `INGRESADO` → `CANCELADO` (EP3-76) |
| `request.contact-logged` | Registro de una gestión de contacto |
| `request.assigned` | Toma, asignación o reasignación del responsable del trámite |
| `request.rated` | Encuesta del titular sobre un trámite `RESUELTO` (EP3-74) |
| `request.citizen-comment` | Comentario del titular, con o sin foto, en un trámite abierto (EP3-64) |

Una transición rechazada (409) o una operación revertida no genera evento. El evento se escribe en el outbox dentro de la misma transacción del cambio (EP3-02).

**Campos del payload:**

| Campo | Tipo | `created` | `status-changed` | `cancelled` | `contact-logged` | `assigned` | `rated` | `citizen-comment` |
|---|---|---|---|---|---|---|---|---|
| `requestId` | uuid | No nulo | No nulo | No nulo | No nulo | No nulo | No nulo | No nulo |
| `folio` | string | No nulo | No nulo | No nulo | No nulo | No nulo | No nulo | No nulo |
| `procedureType` | string | No nulo | No nulo | No nulo | | | | |
| `procedureLabel` | string | No nulo | | | | | | |
| `sector` | string | Nulo si no se indicó | Nulo si no se indicó | Nulo si no se indicó | | | | |
| `latitude`, `longitude` | número | Ambos nulos o ambos con valor | | | | | | |
| `status` | enum | Siempre `INGRESADO` | | | | | | |
| `slaBusinessDays` | entero | Nulo si el tipo no tiene plazo | | | | | | |
| `fromStatus`, `toStatus` | enum | | No nulos | No nulos (`INGRESADO` → `CANCELADO`) | | | | |
| `reason` | string | | Con valor solo si `toStatus` es `RECHAZADO` | | | Ver regla de asignación | | |
| `interventionReason` | string | | Nulo si el actor no es Admin | | Nulo si el actor no es Admin | | | |
| `channel` | enum `ContactChannel` | | | | No nulo | | | |
| `result` | enum `ContactResult` | | | | No nulo | | | |
| `nextAttemptAt` | instant | | | | Nulo si no se programó | | | |
| `assigneeId`, `assigneeName` | string | | | | | No nulos | | |
| `previousAssigneeId` | string | | | | | Ver regla de asignación | | |
| `score` | entero 1..5 | | | | | | No nulo | |
| `comment` | string | | | | | | Nulo si no hubo comentario | |
| `hasAttachment` | boolean | | | | | | | No nulo |

Notas por campo:
- **`folio`:** su formato y generación se definen en EP3-05.
- **`procedureLabel`:** es el snapshot del alta, con el respaldo de `ProcedureTypes.labelOf`.
- **`slaBusinessDays`:** es el snapshot del plazo del tipo al momento del alta. Su regla de negocio está en EP3-06.
- **`interventionReason`:** motivo interno de una intervención del Admin (EP3-04, sección 3). Es un campo opcional agregado de forma compatible, así que `schemaVersion` sigue en 1 (sección 11).

**Regla de asignación.** Depende de si el trámite tenía responsable antes de la operación:
- **Sin responsable previo** (primera asignación): `previousAssigneeId` y `reason` van en `null`.
- **Con responsable previo** (reasignación): `previousAssigneeId` y `reason` son obligatorios.

Los permisos y el motivo se definen en EP3-05.

**Ejemplos.** El `folio` sigue el formato de EP3-05. Como manda la regla 1 de la sección 5, cada ejemplo trae todos los campos de su tipo, también los que van en `null`.

`request.created`:

```json
{
  "eventId": "3c9e2f10-7a4b-4c1d-9e8f-0a1b2c3d4e5f",
  "eventType": "request.created",
  "schemaVersion": 1,
  "occurredAt": "2026-11-10T13:05:12.481Z",
  "producer": "requests",
  "traceId": "c3a91e22-0d44-4f6b-8a17-55e2b0c4d901",
  "sequence": 1041,
  "actor": { "id": "5d2b8e61-3f4a-4c7b-9a10-2e3f4a5b6c7d", "name": "Vecino Test", "role": "Vecino" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "sector": "ralco",
    "latitude": -37.9946,
    "longitude": -71.4962,
    "status": "INGRESADO",
    "slaBusinessDays": 5
  }
}
```

`request.status-changed`, rechazo:

```json
{
  "eventId": "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d",
  "eventType": "request.status-changed",
  "schemaVersion": 1,
  "occurredAt": "2026-11-10T15:40:03.112Z",
  "producer": "requests",
  "traceId": "aa11bb22-cc33-4dd5-8ee6-ff0011223344",
  "sequence": 1057,
  "actor": { "id": "8e7f6a5b-4c3d-4e2f-9a1b-0c9d8e7f6a5b", "name": "Funcionario Test", "role": "Funcionario" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "procedureType": "bache",
    "sector": "ralco",
    "fromStatus": "ADMITIDO",
    "toStatus": "RECHAZADO",
    "reason": "Direccion fuera de la comuna",
    "interventionReason": null
  }
}
```

`request.cancelled`:

```json
{
  "eventId": "1b2c3d4e-5f60-4789-8abc-def012345678",
  "eventType": "request.cancelled",
  "schemaVersion": 1,
  "occurredAt": "2026-11-11T12:10:00.000Z",
  "producer": "requests",
  "traceId": "bb22cc33-dd44-4ee5-8ff6-001122334455",
  "sequence": 1060,
  "actor": { "id": "5d2b8e61-3f4a-4c7b-9a10-2e3f4a5b6c7d", "name": "Vecino Test", "role": "Vecino" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "procedureType": "bache",
    "sector": "ralco",
    "fromStatus": "INGRESADO",
    "toStatus": "CANCELADO"
  }
}
```

`request.rated`:

```json
{
  "eventId": "2a3b4c5d-6e7f-4890-9abc-def123456789",
  "eventType": "request.rated",
  "schemaVersion": 1,
  "occurredAt": "2026-11-12T18:00:00.000Z",
  "producer": "requests",
  "traceId": "cc33dd44-ee55-4ff6-9001-112233445566",
  "sequence": 1088,
  "actor": { "id": "5d2b8e61-3f4a-4c7b-9a10-2e3f4a5b6c7d", "name": "Vecino Test", "role": "Vecino" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "score": 5,
    "comment": "Rapido"
  }
}
```

`request.citizen-comment`:

```json
{
  "eventId": "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f",
  "eventType": "request.citizen-comment",
  "schemaVersion": 1,
  "occurredAt": "2026-11-12T15:30:00.000Z",
  "producer": "requests",
  "traceId": "dd44ee55-ff66-4007-8112-233445566778",
  "sequence": 1075,
  "actor": { "id": "5d2b8e61-3f4a-4c7b-9a10-2e3f4a5b6c7d", "name": "Vecino Test", "role": "Vecino" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "hasAttachment": true
  }
}
```

`request.contact-logged`:

```json
{
  "eventId": "1f2e3d4c-5b6a-4978-8a9b-0c1d2e3f4a5b",
  "eventType": "request.contact-logged",
  "schemaVersion": 1,
  "occurredAt": "2026-11-10T14:12:45.009Z",
  "producer": "requests",
  "traceId": "bb22cc33-dd44-4ee5-9ff6-001122334455",
  "sequence": 1049,
  "actor": { "id": "8e7f6a5b-4c3d-4e2f-9a1b-0c9d8e7f6a5b", "name": "Funcionario Test", "role": "Funcionario" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "channel": "LLAMADA",
    "result": "NO_CONTESTA",
    "nextAttemptAt": "2026-11-11T13:00:00Z",
    "interventionReason": null
  }
}
```

`request.assigned`, reasignación:

```json
{
  "eventId": "6b5a4f3e-2d1c-4b0a-9f8e-7d6c5b4a3f2e",
  "eventType": "request.assigned",
  "schemaVersion": 1,
  "occurredAt": "2026-11-10T14:30:00.250Z",
  "producer": "requests",
  "traceId": "dd44ee55-ff66-4077-8899-aabbccddeeff",
  "sequence": 1052,
  "actor": { "id": "2a3b4c5d-6e7f-4a8b-9c0d-1e2f3a4b5c6d", "name": "Admin Test", "role": "Admin" },
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "folio": "BD-2026-000123",
    "assigneeId": "4f5e6d7c-8b9a-4c0d-9e1f-2a3b4c5d6e7f",
    "assigneeName": "Funcionaria Sector Norte",
    "previousAssigneeId": "8e7f6a5b-4c3d-4e2f-9a1b-0c9d8e7f6a5b",
    "reason": "Redistribucion de carga del sector"
  }
}
```

En una primera asignación, el mismo evento lleva `previousAssigneeId` y `reason` en `null`.

Los tipos de evento del procedimiento de EP3.5 (subsanación, desistimiento, duplicados, derivación, reapertura, recursos, suspensión y prórroga) están en [`procedimiento-estados.md`](procedimiento-estados.md), sección 8, y [`procedimiento-plazos.md`](procedimiento-plazos.md), sección 8.

### 7. Eventos de `audit.timeline`

Los publican catalog, mq-admin y kafka-admin, **solo cuando la operación terminó con éxito**. Los intentos fallidos o denegados (por ejemplo, un 403 o un 409) no se publican: quedan en el log del servicio que los rechazó. Todos son versión 1.

**Combinaciones válidas.** El `eventType` es `<resourceType>.<action>`, por ejemplo `procedure-type.updated` o `queue.purged`.

| Productor | `resourceType` | `action` |
|---|---|---|
| catalog | `procedure-type` | `created`, `updated` |
| mq-admin | `queue` | `created`, `deleted`, `purged` |
| mq-admin | `exchange`, `binding` | `created`, `deleted` |
| kafka-admin | `topic` | `created`, `updated`, `deleted` |
| kafka-admin | `consumer-group` | `offsets-reset` |
| kafka-admin | `topic` (una DLT) | `dlt-replayed` |

`reserve` y `release` de catalog no se auditan. Son operaciones de alta frecuencia del flujo de admisión, y el cambio de estado que las provoca ya queda en `requests.events`.

**Campos del payload:**

| Campo | Tipo | Nulo | Nota |
|---|---|---|---|
| `resourceType` | string | No | Uno de la tabla anterior |
| `resourceId` | string | No | Nombre del recurso. En un binding: `<exchange>/<queue>/<routingKey>`. El `/` no está permitido en los nombres (EP2-04 y EP3-03), así que no genera ambigüedad |
| `action` | string | No | Una de la tabla anterior |
| `before` | objeto | Sí | Estado anterior con los campos que expone la API del recurso. `null` en `created` y en `dlt-replayed` |
| `after` | objeto | Sí | Estado posterior. `null` en `deleted`. En `purged`, `offsets-reset` y `dlt-replayed` lleva el detalle de la operación: mensajes eliminados, offsets resultantes por partición o `eventId` reenviados con su resultado |

La key del mensaje es `<resourceType>:<resourceId>` (sección 3).

**Ejemplos.**

`procedure-type.updated`:

```json
{
  "eventId": "5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b",
  "eventType": "procedure-type.updated",
  "schemaVersion": 1,
  "occurredAt": "2026-11-12T12:20:31.774Z",
  "producer": "catalog",
  "traceId": "ee55ff66-0011-4223-9445-566778899aab",
  "actor": {
    "id": "2a3b4c5d-6e7f-4a8b-9c0d-1e2f3a4b5c6d",
    "name": "Admin Test",
    "role": "Admin",
    "sourceIp": "203.0.113.25"
  },
  "payload": {
    "resourceType": "procedure-type",
    "resourceId": "bache",
    "action": "updated",
    "before": { "label": "Bache en calle", "active": true, "dailyQuota": 20, "slaBusinessDays": null },
    "after": { "label": "Bache en calle", "active": true, "dailyQuota": 15, "slaBusinessDays": 5 }
  }
}
```

`queue.purged`:

```json
{
  "eventId": "7c8d9e0f-1a2b-4c3d-9e4f-5a6b7c8d9e0f",
  "eventType": "queue.purged",
  "schemaVersion": 1,
  "occurredAt": "2026-11-12T12:45:08.003Z",
  "producer": "mq-admin",
  "traceId": "ff667700-1122-4334-8556-6778899aabbc",
  "actor": {
    "id": "2a3b4c5d-6e7f-4a8b-9c0d-1e2f3a4b5c6d",
    "name": "Admin Test",
    "role": "Admin",
    "sourceIp": "203.0.113.25"
  },
  "payload": {
    "resourceType": "queue",
    "resourceId": "q.demo.avisos",
    "action": "purged",
    "before": { "messages": 12 },
    "after": { "messagesRemoved": 12 }
  }
}
```

**Si Kafka no está disponible**, la operación administrativa igual responde, y el productor registra en su log `ERROR evento-auditoria-no-publicado` con el evento completo en JSON (EP3-02).

### 8. Minimización de datos personales

Cada evento lleva solo lo que sus consumidores necesitan, en línea con los principios de la Ley 21.719 de protección de datos personales.

| Dato | ¿Viaja? | Motivo |
|---|---|---|
| Correo del solicitante | No | report y audit no envían correos. Los correos siguen por RabbitMQ (EP2-01) |
| Dirección textual | No | Ningún consumidor la necesita. El análisis geográfico usa `sector` y coordenadas |
| Nota libre de una gestión | No | Puede contener datos personales del contacto. Se conservan `channel` y `result` |
| Texto e imagen de un comentario del vecino | No | Pueden contener datos personales y ningún consumidor los necesita. Se conserva `hasAttachment` |
| Motivo de rechazo y de reasignación | Sí | Explica la decisión. Es parte de la trazabilidad que pide la auditoría |
| Motivo de intervención del Admin | Sí | Explica por qué el Admin operó un trámite. Es la trazabilidad que el Auditor fiscaliza. Viaja solo en Kafka: nunca en RabbitMQ, los correos ni los PDF (EP3-04, sección 6) |
| Coordenadas | Sí | Ubican el problema (un bache, una luminaria), no a la persona. Alimentan el mapa de reportes |
| Nombre e id del actor | Sí | Necesarios para saber quién hizo qué |
| IP de origen | Solo en `audit.timeline` | Ver sección 9 |

### 9. "Desde dónde" y la IP de origen

El caso base pide que la auditoría registre quién, qué, cuándo y desde dónde. En BarrioDigital, `audit.timeline` lleva las operaciones administrativas, y esas incluyen `actor.sourceIp`. Los eventos de `requests.events` no la incluyen.

**Por qué:** las operaciones administrativas (cambiar cupos, borrar colas, reiniciar offsets) son las que más trazabilidad requieren, y ningún consumidor de `requests.events` necesita la IP. Así se minimiza un dato personal más.

**Consecuencia aceptada:** en el timeline de un trámite, el Auditor ve quién, qué y cuándo, pero no desde qué IP.

**Origen de la IP.** El API Gateway sobrescribe el header `X-Source-Ip` con `$context.identity.sourceIp` en la integración hacia el BFF. El BFF lee solo ese header y lo reenvía a catalog, mq-admin y kafka-admin. Nunca se usa `X-Forwarded-For`: si el cliente lo envía, el Gateway agrega la IP real al final sin borrar lo anterior, y el primer valor podría ser inventado. Si `X-Source-Ip` no llega, por ejemplo en local, `actor.sourceIp` va en `null`.

### 10. Recepción: desconocidos, malformados e incompatibles

| Caso | Ejemplo | Acción del consumidor |
|---|---|---|
| `eventType` desconocido | Un `request.rated` futuro que el consumidor aún no maneja | Log WARN, confirma el offset y sigue |
| Malformado | JSON roto, sobre sin `eventId`, solo una de las dos coordenadas, campo obligatorio en `null` | A su DLT sin reintentos |
| Incompatible | `schemaVersion` mayor que la soportada por el consumidor para ese `eventType` | A su DLT sin reintentos. Se reprocesa desde kafka-admin cuando el consumidor se actualiza |
| Campo desconocido | Un campo opcional agregado en una versión compatible | Se ignora (sección 5) |

El detalle de reintentos, DLT y logs está en EP3-02.

### 11. Versionado con `schemaVersion`

1. **La versión es independiente por `eventType`.** Todos parten en 1.
2. **Cambios compatibles, que no suben la versión:** agregar un campo opcional, o agregar un `eventType` nuevo.
3. **Cambios incompatibles, que suben la versión:**
   - quitar o renombrar un campo;
   - cambiar su tipo o su significado;
   - volver obligatorio un campo opcional;
   - cambiar qué representa la key.
4. **Cada consumidor declara, por `eventType`, las versiones que soporta.** Una versión mayor es incompatible (sección 10).
5. **Orden de despliegue ante un cambio incompatible:** primero los consumidores, que pasan a soportar la versión nueva y la anterior; después el productor. Los consumidores mantienen la versión anterior al menos mientras dure la retención del tópico.

`slaBusinessDays` forma parte de la versión 1 de `request.created` como campo nullable.

### 12. Límites y mejoras futuras

1. **`traceId` por servicio:** cada productor genera el suyo. Una misma operación que pasa por el BFF y varios servicios no comparte un único `traceId`. Mejora futura: que el BFF genere `X-Trace-Id` por request HTTP y lo propague.
2. **Auditoría de fallos:** no se auditan las operaciones administrativas fallidas ni las denegadas. Quedan solo en los logs.
3. **IP solo en lo administrativo:** la IP de origen se registra solo en `audit.timeline`.
4. **Acceso directo al BFF:** el puerto 8080 del BFF en la EC2 es público para la integración del Gateway. Alguien que llegue directo, sin pasar por el Gateway, podría enviar un `X-Source-Ip` falso, aunque igual necesita un JWT válido.
5. **Compactación y audit detenido:** si audit estuviera detenido más de 7 días, podría perder eventos intermedios de `audit.timeline` ya compactados. El lag del grupo `audit-group` en Kafka UI lo anticipa.
