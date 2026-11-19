<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: publicación y consumo de eventos Kafka (EP3-02)

Define cómo salen los eventos de EP3-01 hacia Kafka sin perderse y cómo los procesan report y audit sin perderlos ni contarlos dos veces. Cubre:
- el outbox de requests y su relay;
- la publicación directa de los productores de `audit.timeline`;
- la configuración de productores y consumidores;
- reintentos y DLT;
- idempotencia y limpieza.

RabbitMQ no cambia: los comandos hacia notify siguen con la publicación después del commit de EP2-01, con su política de ACK de EP2-03.

### 1. Garantía de entrega

El modelo es **al menos una vez más idempotencia**:
- **Al menos una vez:** el outbox y la confirmación del offset después de guardar aseguran que ningún evento se pierda.
- **Idempotencia:** como consecuencia, un evento puede llegar más de una vez a un consumidor, y la idempotencia por `eventId` (sección 9) evita que se procese dos veces.

No se usan transacciones de Kafka ni la semántica "exactly-once" de Kafka. Las transacciones de este contrato son **transacciones de Oracle**.

### 2. Publicación en requests: outbox

#### 2.1 Tabla `outbox_events`

| Columna | Tipo | Nulo | Nota |
|---|---|---|---|
| `event_id` | VARCHAR2(36) | No | Clave primaria. Es el `eventId` del sobre |
| `event_sequence` | NUMBER, `GENERATED ALWAYS AS IDENTITY` con `ORDER` | No | Único. Orden de publicación. `ORDER` mantiene el orden real aunque Oracle Autonomous corra en varias instancias. Es el valor del campo `sequence` del JSON |
| `aggregate_id` | VARCHAR2(36) | No | `requestId`. Es la key del mensaje |
| `event_type` | VARCHAR2(60) | No | Por ejemplo `request.status-changed` |
| `payload` | CLOB | No | JSON del sobre completo de EP3-01, **sin** el campo `sequence` |
| `created_at` | TIMESTAMP WITH TIME ZONE | No | Momento de la escritura en el outbox |
| `published_at` | TIMESTAMP WITH TIME ZONE | Sí | `null` mientras el evento está pendiente |
| `attempts` | NUMBER | No | Envíos fallidos. Parte en 0 |
| `last_error` | VARCHAR2(500) | Sí | Último error de envío, recortado a 500 caracteres |

Índice `idx_outbox_pending` sobre (`published_at`, `event_sequence`) para leer los pendientes en orden.

La columna se llama `event_sequence` y no `sequence` porque `SEQUENCE` es palabra clave de Oracle. No es reservada, pero puede dar problemas con Hibernate al generar SQL. El campo del JSON sigue llamándose `sequence` (EP3-01).

En la entidad JPA, la clave primaria es `event_id`. `event_sequence` se mapea con `@Column(insertable = false, updatable = false)` y `@Generated`, para que Oracle lo asigne y Hibernate lo lea después del insert.

**Orden de aplicación del script.** La tabla, con el identity con `ORDER`, el índice y los nombres de las restricciones, la crea `db/outbox-events.sql` de requests, porque `ddl-auto: update` no sabe crear el identity. `db/schema.sql` la repite como referencia. El script se aplica en Oracle **antes del primer arranque** de requests con esta versión, también en una base nueva. Si Hibernate crea primero la tabla, la crea sin identity, y la primera alta falla porque `event_sequence` es `NOT NULL`. En ese caso la tabla está vacía, y el script la elimina y la recrea. Con filas o ya con identity, el script se detiene sin tocarla.

Las fechas van con zona, como el resto de las tablas de requests y como Hibernate mapea `Instant` en Oracle.

#### 2.2 Una sola transacción

Toda operación que genera un evento guarda **en la misma transacción**:
1. el cambio de negocio en `municipal_requests`;
2. la fila de `request_activity`;
3. la fila de `outbox_events`.

O quedan las tres, o ninguna. Un rollback no deja evento, y una transición rechazada (409) tampoco.

| Operación | Método | Evento |
|---|---|---|
| Alta | `RequestService.create` | `request.created` |
| Cambio de estado | `RequestService.changeStatus` | `request.status-changed` |
| Encuesta de satisfacción | `RequestService.rate` | `request.rated` |
| Cancelación del titular | `RequestService.cancel` | `request.cancelled` |
| Comentario del titular | `RequestActivityService.comment` | `request.citizen-comment` |
| Gestión de contacto | `RequestActivityService.registerGestion` | `request.contact-logged` |
| Toma o reasignación | Asignación (EP3-29) | `request.assigned` |

#### 2.3 Bloqueo previo por trámite

Toda operación que genera un evento sobre un trámite **existente** toma antes el bloqueo `PESSIMISTIC_WRITE` de su fila (`findByIdForUpdate`). Así, dos operaciones sobre el mismo trámite se ejecutan una después de la otra, y la segunda recibe un `sequence` mayor.

Hoy ya lo hacen `changeStatus`, `rate`, `cancel`, `registerGestion` y `comment`. La asignación debe hacerlo también. El alta no lo necesita porque la fila es nueva.

**Cualquier operación nueva que genere eventos de un trámite debe seguir esta regla.**

#### 2.4 Separación negocio y mensajería

`RequestService` y `RequestActivityService` llaman a `DomainEventRecorder`, en el paquete de mensajería. `DomainEventRecorder` arma el sobre de EP3-01 y escribe la fila del outbox. Ninguna clase de negocio importa clases de Kafka.

El `traceId` del evento es el mismo que llevan los comandos de RabbitMQ del mismo cambio (EP3-01, sección 4).

### 3. Relay

#### 3.1 Ciclo

1. **Lectura:** un `@Scheduled` con `fixedDelay` de 1 segundo lee hasta **100** eventos con `published_at` nulo, ordenados por `event_sequence`.
2. **Envío:** por cada evento, en orden, agrega al sobre el campo `sequence` con el valor de `event_sequence`, publica en `requests.events` con key `aggregate_id` y espera la confirmación del broker, como máximo 10 segundos.
3. **Marca:** con la confirmación, marca `published_at`.
4. **Falla:** si un envío falla o no se confirma a tiempo, incrementa `attempts`, guarda `last_error` y **detiene el lote**. No sigue con los eventos siguientes, porque los publicaría antes que el que falló.

Si requests se cae después de publicar pero antes de marcar `published_at`, el evento se vuelve a publicar en el siguiente ciclo. Ese duplicado lo absorben los consumidores (sección 9).

#### 3.2 Kafka no disponible

Tras un lote fallido, el relay espera cada vez más antes de reintentar: 1, 2, 4, 8 y 16 segundos, hasta un máximo de 30. Al primer envío exitoso vuelve al ciclo de 1 segundo.

Log al empezar la falla, una sola vez por racha:

```text
ERROR relay-detenido sequence=1057 eventId=9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d motivo="Topic requests.events not present in metadata after 5000 ms."
```

Log al recuperarse:

```text
INFO relay-reanudado pendientes=14
```

Mientras Kafka está caído, el HTTP responde normal y los eventos esperan en el outbox. requests arranca aunque Kafka no esté disponible.

#### 3.3 Configuración del productor

| Propiedad | Valor | Motivo |
|---|---|---|
| `acks` | `all` | Confirma cuando lo tienen las réplicas en sincronía (`min.insync.replicas=2`) |
| `enable.idempotence` | `true` | Un reintento interno del productor no duplica el mensaje en el broker |
| `max.in.flight.requests.per.connection` | 5 (valor por defecto) | Con idempotencia activada, mantiene el orden por partición |
| `max.block.ms` | 5000 | Sin esto, un envío con Kafka caído puede bloquear 60 s esperando metadatos |
| `request.timeout.ms` | 5000 | |
| `delivery.timeout.ms` | 10000 | Tiempo máximo total de un envío, incluidos los reintentos internos |
| Serializador de key y valor | `StringSerializer` | El outbox ya guarda el JSON. Sin headers de tipo Java |

Las propiedades van en `application.yml`, junto con los nombres de los tópicos en `barriodigital.kafka.*`, igual que `barriodigital.rabbit.*`. requests no declara `NewTopic` y lleva `spring.kafka.admin.auto-create=false`.

#### 3.4 Hilos programados

El pool de tareas programadas tiene **2 hilos**. Spring usa uno por defecto, y con uno solo un relay esperando a Kafka bloquearía la limpieza.

#### 3.5 Instancia única

El relay asume una sola instancia de requests. Si se escalara a más de una, la lectura de pendientes debería usar `SELECT ... FOR UPDATE SKIP LOCKED`, que Oracle soporta, para que dos relays no tomen el mismo evento.

### 4. Limpieza

Una tarea diaria a las 03:30 en `America/Santiago`:

| Tabla | Servicio | Qué borra |
|---|---|---|
| `outbox_events` | requests | Solo eventos **publicados** con `published_at` de más de 7 días. Un evento sin publicar no se borra nunca, aunque sea antiguo |
| `processed_events` | report | Registros del consumidor `report` con más de 30 días |
| Tabla de auditoría | audit | Nada. Es el registro histórico definitivo |

Los 30 días de `processed_events` cubren el tiempo en que un duplicado puede llegar a report. El replay desde una DLT vuelve a `requests.events`, así que el peor caso es 2 × 7 + 14 = 28 días (EP3-01, sección 2, "Regla entre retenciones").

### 5. Visibilidad del outbox

El health de requests (`/actuator/health`) incluye un componente `outbox` con la cantidad de eventos pendientes y la antigüedad del más viejo. Es informativo: no cambia el estado `UP` del servicio.

```json
{
  "status": "UP",
  "components": {
    "outbox": {
      "status": "UP",
      "details": { "pendientes": 14, "antiguedadMasViejoSegundos": 37 }
    }
  }
}
```

Con Kafka caído, `pendientes` crece. Al volver, baja a 0.

### 6. Publicación directa en `audit.timeline`

catalog, mq-admin y kafka-admin publican sus eventos (EP3-01, sección 7) sin outbox:

1. **Cuándo se encola:** solo después de que la operación terminó con éxito.
   - En catalog, el evento se encola **después del commit** de la transacción (`@TransactionalEventListener(phase = AFTER_COMMIT)` o `TransactionSynchronization.afterCommit`), nunca antes. Un rollback no encola nada.
   - mq-admin y kafka-admin no tienen base de datos: encolan cuando la operación sobre RabbitMQ o Kafka respondió bien.
2. **Executor de un solo hilo por servicio, fuera del hilo HTTP.** La respuesta al usuario no espera a Kafka, ni siquiera los 5 segundos de `max.block.ms`. Un solo hilo **mantiene el orden** de los eventos de un mismo recurso. Esto importa porque `audit.timeline` es compactado: si dos `procedure-type.updated` seguidos se publicaran al revés, la compactación conservaría el penúltimo cambio como si fuera el último. El volumen administrativo es bajo, así que un hilo alcanza.
3. **Envío en orden y con confirmación:** el hilo publica un evento, espera su confirmación (máximo 10 segundos, como el relay) y recién después toma el siguiente. Así cada falla se detecta y se registra para el evento que corresponde.
4. **Cola acotada de 1000 eventos.** Con Kafka caído, cada envío tarda hasta 5 segundos (`max.block.ms`) en fallar, y la cola crece. Si se llena, el evento nuevo se rechaza y se registra con el mismo log de respaldo, con `motivo="cola de auditoria llena"`.
5. **Configuración del productor:** la misma de la sección 3.3.
6. **Si el envío falla o la cola está llena**, se registra el evento completo para poder reconstruirlo, y la operación ya respondió con éxito:

```text
ERROR evento-auditoria-no-publicado eventType=procedure-type.updated eventId=5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b motivo="Topic audit.timeline not present in metadata after 5000 ms." evento={"eventId":"5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b","eventType":"procedure-type.updated", ...}
```

7. **Apagado ordenado:** al detenerse el servicio de forma ordenada (`@PreDestroy`), los eventos que quedaron en la cola se escriben en el log con `ERROR evento-auditoria-no-publicado` y su JSON, con `motivo="apagado del servicio"`. Lo mismo ocurre con el evento que se estaba enviando, si su confirmación no llegó. Un reinicio controlado, como `docker compose restart`, no pierde eventos: quedan reconstruibles desde el log.
8. **Separación:** `CatalogService`, `RabbitAdminService` y `KafkaAdminService` llaman a un componente de mensajería y no conocen el productor de Kafka.

### 7. Consumo

#### 7.1 Grupos y listeners

| Servicio | Grupo | Tópico | Listener | Concurrencia |
|---|---|---|---|---|
| report | `report-group` | `requests.events` | Uno | 3 |
| audit | `audit-group` | `requests.events` | Uno | 3 |
| audit | `audit-group` | `audit.timeline` | Uno, separado del anterior | 3 |

Concurrencia 3 es un hilo por partición. Si se levanta una segunda instancia de report, el grupo reparte las 3 particiones entre las dos.

#### 7.2 Configuración del consumidor

| Propiedad | Valor | Motivo |
|---|---|---|
| `enable-auto-commit` | `false` | El offset lo confirma Spring, no un temporizador |
| `ack-mode` | `RECORD` | Se confirma cada mensaje después de que el listener terminó bien |
| `auto-offset-reset` | `earliest` | Un grupo nuevo, o un reset de offsets, lee desde el inicio de la retención |
| `max-poll-records` | 50 | Acota el tiempo de procesamiento entre lecturas y la cantidad de registros que se vuelven a leer tras un fallo. Ante un error, `DefaultErrorHandler` vuelve al offset del mensaje fallido y descarta el resto del lote, que se relee en la siguiente lectura. Entre dos lecturas hay como máximo una espera de reintento (4 s o menos), muy lejos del límite de `max.poll.interval.ms` (5 minutos) |
| Deserializador de key | `StringDeserializer` | |
| Deserializador de valor | `ErrorHandlingDeserializer` sobre `StringDeserializer` | Red de seguridad ante bytes ilegibles, para que no tumben el listener. El JSON inválido lo detecta la validación del componente de mensajería, y va a la DLT sin reintentos |

La validación del sobre y del payload (EP3-01, sección 10) ocurre en el componente de mensajería, antes de llamar al dominio. Ese componente convierte el JSON al record del `eventType`.

#### 7.3 Orden y transacción

1. **Secuencial por partición:** cada partición se procesa en un solo hilo. El listener no usa `@Async`, no crea hilos y no procesa en paralelo los mensajes de un lote.
2. **Transacción dentro del listener:** la transacción de Oracle empieza y termina **dentro** de la llamada al servicio de dominio, antes de que el listener retorne. Recién después Spring confirma el offset.

Si el servicio se cae con la transacción ya confirmada pero antes de confirmar el offset, el mensaje se relee y la idempotencia lo descarta.

#### 7.4 Separación negocio y mensajería

El `@KafkaListener` vive en el paquete de mensajería: recibe, valida, convierte y delega. `KpiService` (report) y `AuditTrailService` (audit) no conocen Kafka.

### 8. Errores, reintentos y DLT

#### 8.1 Clasificación

| Situación | Ejemplo | Acción |
|---|---|---|
| Procesó bien | KPI actualizado | Confirma el offset |
| `eventId` ya procesado | El relay publicó dos veces el mismo evento | Confirma el offset sin reprocesar, log INFO `duplicado` |
| `eventType` desconocido | `request.rated` antes de que el consumidor lo soporte | Confirma el offset, log WARN `evento-desconocido` |
| Error recuperable | Oracle no responde | Reintenta a 1, 2 y 4 segundos. Son 3 reintentos además del primer intento: 4 ejecuciones en total |
| Recuperable agotado | Oracle sigue sin responder tras el cuarto intento | A la DLT del consumidor |
| No recuperable | JSON ilegible, sobre o payload inválido, una sola coordenada, `schemaVersion` no soportada | A la DLT sin reintentos |

En código, `DefaultErrorHandler` usa `ExponentialBackOffWithMaxRetries(3)` con intervalo inicial de 1000 ms y multiplicador 2, lo que da las esperas de 1, 2 y 4 segundos aprobadas en K5. A diferencia de RabbitMQ (EP2-03, 3 intentos en total), aquí son **4 ejecuciones**: el primer intento más 3 reintentos.

Los errores no recuperables se modelan con una excepción propia que se registra como **no reintentable** en `DefaultErrorHandler`.

#### 8.2 Por qué los reintentos son bloqueantes

Mientras se reintenta, la partición espera. No se usan tópicos de reintento (`@RetryableTopic`): esos sacan el mensaje de su partición y lo procesan más tarde, y un `RESUELTO` podría procesarse antes que su `EN_TERRENO`. Detener la partición unos segundos es preferible a desordenar la historia de un trámite.

#### 8.3 DLT

1. **Envío:** `DeadLetterPublishingRecoverer` publica el mensaje fallido en `<tópico>.<consumidor>.DLT`, en la partición con el mismo número que la de origen y con la misma key y valor. Las DLT usan `LogAppendTime`, así que el timestamp del mensaje en la DLT es la hora de llegada (EP3-01, sección 2).
2. **Diagnóstico:** Spring agrega estos headers:
   - `kafka_dlt-exception-fqcn`, `kafka_dlt-exception-cause-fqcn`, `kafka_dlt-exception-message` y `kafka_dlt-exception-stacktrace`;
   - `kafka_dlt-original-topic`, `kafka_dlt-original-partition` y `kafka_dlt-original-offset`;
   - `kafka_dlt-original-timestamp` y `kafka_dlt-original-timestamp-type`;
   - `kafka_dlt-original-consumer-group`, el grupo que falló.

   Si falla la deserialización de la key, usa los equivalentes `kafka_dlt-key-exception-*`. Con `StringDeserializer` en la key no debería ocurrir.
3. **Confirmación:** el envío a la DLT usa `acks=all` y espera confirmación. El mensaje original **solo se da por recuperado** cuando la DLT confirmó. Si el envío a la DLT falla, el offset no se confirma, el mensaje vuelve a intentarse y la partición queda detenida hasta que la DLT esté disponible.
4. **Reprocesamiento:** los mensajes de una DLT se revisan y reprocesan desde kafka-admin (EP3-03).

| DLT | Origen | Consumidor |
|---|---|---|
| `requests.events.report.DLT` | `requests.events` | report |
| `requests.events.audit.DLT` | `requests.events` | audit |
| `audit.timeline.audit.DLT` | `audit.timeline` | audit |

#### 8.4 Logs

Mensaje enviado a la DLT, en ERROR:

```text
ERROR evento-muerto topic=requests.events partition=1 offset=2045 eventId=9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d motivo="Oracle no disponible" intentos=4
```

Mensaje ilegible, sin `eventId`, rechazado sin procesarse:

```text
ERROR evento-muerto topic=audit.timeline partition=0 offset=88 eventId=desconocido motivo="JSON invalido" intentos=0
```

`intentos` cuenta las veces que se ejecutó el procesamiento, con la misma regla de EP2-03: en un rechazo directo vale 0.

Duplicado, en INFO:

```text
INFO duplicado topic=requests.events consumidor=report eventId=3c9e2f10-7a4b-4c1d-9e8f-0a1b2c3d4e5f
```

`eventType` desconocido, en WARN:

```text
WARN evento-desconocido topic=requests.events consumidor=audit eventType=request.rated eventId=0b1c2d3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e
```

### 9. Idempotencia

#### 9.1 Dónde se registra

| Servicio | Tabla | Restricción | Columnas |
|---|---|---|---|
| report | `processed_events` | `pk_processed_events`, clave primaria (`consumer`, `event_id`) | `consumer` VARCHAR2(40), `event_id` VARCHAR2(36), `processed_at` TIMESTAMP WITH TIME ZONE |
| audit | Tabla de auditoría | `uk_audit_entries_event_id`, única sobre `event_id` | La propia fila de auditoría |

En report, la fila de `processed_events` y la actualización de los KPI van en **la misma transacción**: o se cuenta el evento y se marca como procesado, o ninguna de las dos cosas. En audit, la fila de auditoría es a la vez el registro y la marca de idempotencia.

Las restricciones llevan esos nombres explícitos en el `db/schema.sql` de cada servicio.

En report, `ddl-auto: update` no sabe nombrar una clave primaria, y con otro nombre ningún duplicado se reconocería. Por eso las tablas las crea `db/report-tables.sql`, que se aplica en Oracle **antes del primer arranque**. Si Hibernate creó la tabla antes, el script renombra la clave sin tocar las filas. report no arranca si la clave tiene otro nombre.

#### 9.2 Cómo se reconoce un duplicado

Solo una violación de `pk_processed_events` o de `uk_audit_entries_event_id` se trata como duplicado. Cualquier otra violación de restricción o error de base de datos se propaga y entra al flujo de reintentos de la sección 8.

La detección ocurre **fuera** del método `@Transactional`: una excepción dentro de la transacción la marca para rollback, así que el listener la captura después de que la transacción terminó.

#### 9.3 Eventos atrasados

Un evento reprocesado desde la DLT puede llegar después de eventos más nuevos del mismo trámite.

- **report:** guarda en su proyección el último `sequence` aplicado a cada aspecto del trámite. Un evento con `sequence` menor que el de su aspecto **no modifica** ese aspecto, pero **sí cuenta** en las métricas históricas (trámites por hora, tipos más demandados). Las reglas están más abajo.
- **audit:** guarda todos los eventos y ordena el timeline por `occurredAt`, así que el atraso no le afecta.

**Aspectos en report.** Se compara por aspecto y no por trámite: con un solo `sequence`, una encuesta (sequence 6) aplicada antes del replay de un `RESUELTO` (sequence 5) haría ignorar el cierre, y el trámite quedaría abierto para siempre en los KPIs.

| Aspecto | Eventos | Columna |
|---|---|---|
| Estado | `request.created` (`INGRESADO`), `request.status-changed`, `request.cancelled` | `status_sequence` |
| Responsable | `request.assigned` | `assignee_sequence` |

1. **Un evento atrasado para su aspecto no lo modifica.** Un evento de otro aspecto no lo bloquea.
2. **Los hechos con fecha fija se completan si faltan, aunque el evento llegue atrasado.** Son los datos del alta (`created_at`, tipo, label, sector, coordenadas, `sla_business_days`) y `closed_at`.
3. **`last_sequence` y `last_event_at`** guardan el mayor `sequence` y el mayor `occurredAt` aplicados, y no retroceden.
4. **`request.contact-logged`, `request.rated` y `request.citizen-comment`** no cambian el estado ni el responsable: solo actualizan `last_sequence` y `last_event_at`, o crean la proyección parcial.

### 10. Límites conocidos

1. **Relay de instancia única:** con más de una instancia de requests, habría que leer con `SELECT ... FOR UPDATE SKIP LOCKED`.
2. **Retraso del relay:** hasta 1 segundo entre el commit y la publicación en condiciones normales, y más mientras Kafka está caído.
3. **Auditoría administrativa sin outbox:** los eventos de `audit.timeline` se publican sin outbox, así que hay dos formas de perder un evento:
   - **Kafka caído o cola llena:** el evento queda solo en el log `evento-auditoria-no-publicado`, desde donde se puede reconstruir.
   - **Corte abrupto del servicio** (proceso terminado sin apagado ordenado, falla de la máquina): los eventos que estaban esperando en la cola en memoria se pierden **sin** log. En un apagado ordenado, en cambio, se escriben en el log (sección 6) y no se pierden.

   Mejora planificada: outbox en catalog (EP3-68).
4. **Audit detenido más de 7 días:** podría perder eventos intermedios de `audit.timeline` ya compactados. El lag de `audit-group` lo anticipa.
5. **Duplicados muy antiguos:** un duplicado que llegara después de 30 días no se reconocería en report. Con un solo replay, el peor caso es 28 días (EP3-01, sección 2). Si el mismo mensaje se reprocesa, vuelve a fallar y se reprocesa otra vez, la ventana se alarga y report podría contarlo dos veces. audit no tiene este límite, porque `uk_audit_entries_event_id` es permanente.
6. **Retención mínima de `requests.events`:** EP3-03 permite bajarla hasta 3 días. Con ese valor, report o audit detenidos más de 3 días pierden eventos de `requests.events`. El lag del grupo en Kafka UI lo anticipa.
