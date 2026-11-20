<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: API de kafka-admin (EP3-03)

Endpoints de administración de Kafka: tópicos, consumer groups y DLT. Los implementa `ms-barriodigital-kafka-admin` (EP3-17 a EP3-23). `KafkaAdminService` concentra todo el uso de `AdminClient`, y ningún controlador depende de clases de Kafka. El BFF es el único cliente (EP3-44).

Los tópicos, sus parámetros y los eventos están en EP3-01. La publicación, el consumo y las DLT están en EP3-02.

### 1. Servicio y seguridad

1. **Red:** puerto 8085, con `expose` y sin `ports`. Solo lo alcanza el BFF, con `KAFKA_ADMIN_BASE_URL=http://kafka-admin:8085`. No se publica en el API Gateway. El Gateway llega al BFF en `/api/kafka/{proxy+}` (EP3-55).
2. **Token interno:** un filtro valida `X-Internal-Token` contra una variable de entorno antes que cualquier otra cosa. Sin token o con un valor distinto, 401. Ningún header `X-User-*` se lee sin un token válido.
3. **Rol:** después del token, `X-User-Roles` debe incluir `Admin` o `ROLE_Admin`, sin distinguir mayúsculas, con la misma regla de mq-admin (EP2-04). Si no, 403.
4. **Identidad para la auditoría:** `X-User-Id`, `X-User-Name` (codificado en URL, EP3-09) y `X-Source-Ip` (EP3-01, sección 9).
5. **Cuerpo de error:** `status`, `error`, `message` y `path`, igual que mq-admin. `server.error.include-message: always`.
6. **Orden de las comprobaciones:** 401, 403, 400, 404, 409. Los 401, 403 y 400 se resuelven sin Kafka. Los 404 y 409 requieren consultar a Kafka.
7. **Kafka no disponible:** cualquier endpoint cuya llamada a Kafka no responda dentro del timeout responde 503 con el mensaje `Kafka no esta disponible`.

### 2. Endpoints

Todos responden 401 sin token interno válido, 403 sin rol Admin y 503 si Kafka no responde. La tabla muestra solo los códigos propios de cada endpoint.

| Método y ruta | Éxito | 400 | 404 | 409 |
|---|---|---|---|---|
| GET `/api/kafka/topics` | 200, lista con `system` | | | |
| GET `/api/kafka/topics/{name}` | 200, particiones (líder, réplicas, ISR) y configuraciones con `value`, `source` y `editable` | Nombre inválido (1) | No existe | |
| POST `/api/kafka/topics` | 201, el detalle | Nombre, particiones, réplicas (2), o configuración fuera de la lista o del rango | | Ya existe, termina en `.DLT`, o choque `.`/`_` |
| PATCH `/api/kafka/topics/{name}/configs` | 200, el detalle | Nombre inválido (1), configuración fuera de la lista o del rango | No existe | Configuración no editable en un tópico del sistema |
| PATCH `/api/kafka/topics/{name}/partitions` | 200, el detalle | Nombre inválido (1), no aumenta o supera 12 | No existe | Tópico del sistema |
| DELETE `/api/kafka/topics/{name}` | 204, sin cuerpo | Nombre inválido (1) | No existe | Tópico del sistema, o con consumidores activos |
| GET `/api/kafka/consumer-groups` | 200, lista con estado, miembros y `system` | | | |
| GET `/api/kafka/consumer-groups/{groupId}` | 200, por tópico y partición: confirmado, final, lag y `lagBasis` | | No existe (salvo los grupos del sistema) | |
| POST `/api/kafka/consumer-groups/{groupId}/offsets/reset` | 200, por partición: actual, resultante y lag resultante | Falta `topic` o `dryRun`, estrategia inválida, `timestamp` ausente o futuro | Grupo (salvo los del sistema) o tópico inexistente | Miembros activos, tópico fuera de la lista del grupo, sin offsets (otros grupos), avance en un grupo del sistema |
| GET `/api/kafka/dlt/{name}/messages` | 200, por partición con `nextOffset` | No es una DLT del sistema, partición inexistente, `fromOffset` sin `partition`, `limit` fuera de rango | | |
| POST `/api/kafka/dlt/{name}/replay` | 200, estado por mensaje | No es una DLT del sistema, `offsets` y `eventIds` juntos o ninguno, más de 100 | | |

Notas:

1. Los endpoints con `{name}` usan la misma validación de nombre del alta (sección 3.1), incluida la exclusión de `.` y `..`.
2. Las réplicas no pueden superar el número de brokers del clúster.

No hay un endpoint para listar las DLT. Las tres aparecen en `GET /api/kafka/topics` con `system: true`.

### 3. Validaciones

#### 3.1 Nombre de tópico

1. Cumple `^[A-Za-z0-9._-]{1,249}$`.
2. No empieza por `__`, que es el prefijo de los tópicos internos de Kafka.
3. No es `.` ni `..`. Kafka los rechaza aunque cumplan la expresión regular.

Si no cumple, 400.

#### 3.2 Alta

| Campo | Regla |
|---|---|
| `name` | Sección 3.1 |
| `partitions` | Entero de 1 a 12 |
| `replicationFactor` | Entero de 1 a 3, sin superar el número de brokers del clúster |
| `configs` | Opcional. Solo claves de la lista de los tópicos del Admin (sección 3.3), con sus rangos |

#### 3.3 Configuraciones editables

Los valores viajan como string, igual que en Kafka, y se validan como enteros cuando corresponde. `PATCH /configs` es parcial: solo cambian las claves enviadas. Una clave fuera de la lista responde 400. kafka-admin aplica los cambios con `incrementalAlterConfigs` (`SET`), no con `alterConfigs`, que reemplaza todas las configuraciones del tópico. Un valor `null` responde 400: la API no restaura valores por defecto.

| Config | Tópicos del Admin | Tópicos del sistema |
|---|---|---|
| `retention.ms` | 3600000 (1 h) a 2592000000 (30 días) | `requests.events`: 259200000 a 604800000 (3 a 7 días). `audit.timeline`: 1209600000 a 2592000000 (14 a 30 días). DLT: 604800000 a 1209600000 (7 a 14 días) |
| `cleanup.policy` | `delete`, `compact` o `compact,delete` | 409 |
| `min.insync.replicas` | 1 a `max(1, min(2, réplicas − 1))` | 409 |
| `min.compaction.lag.ms` | 0 a 604800000 (7 días) | 409 |
| `segment.ms` | 3600000 (1 h) a 604800000 (7 días) | 409 |

Motivos:

- **`retention.ms` del sistema:** los rangos son los del caso base que cita EP3-01, sección 2, y cumplen la regla entre retenciones en su máximo.
- **`cleanup.policy` del sistema:** si `requests.events` pasara a `compact`, se perdería el historial con el que report reconstruye sus KPIs.
- **`min.insync.replicas` del sistema:** si bajara a 1, se rompería la garantía de un broker caído sin pérdida (EP3-01, sección 2).
- **`min.compaction.lag.ms` del sistema:** si bajara de 7 días, dejaría de valer la ventana de historial completo de `audit.timeline`.
- **`min.insync.replicas` del Admin:** con 3 réplicas, un valor de 3 bloquearía la escritura apenas cae un broker. Con 1 réplica, el único valor posible es 1.
- **`segment.ms` del Admin:** la retención por tiempo sí borra el segmento activo. El broker abre un segmento nuevo y borra los anteriores, siempre que el high watermark haya alcanzado el final del log. La compactación, en cambio, nunca toca el segmento activo. Con el valor por defecto de 7 días, una demo de `compact` en un tópico de prueba no mostraría nada. Se verifica en la prueba de EP3-14.

`message.timestamp.type` no es editable en ningún tópico. En las DLT queda fijo en `LogAppendTime` (EP3-01, sección 2).

#### 3.4 Nombres reservados y choques

| Caso | Código | `message` |
|---|---|---|
| El tópico ya existe | 409 | `El topico ya existe` |
| El nombre termina en `.DLT`, la convención de las DLT del sistema | 409 | `El nombre esta reservado para el sistema` |
| Choque `.`/`_` con un tópico existente | 409 | `El nombre no esta disponible` |

Kafka rechaza `a_b` si existe `a.b`, y al revés, porque los nombres chocan en las métricas. kafka-admin lo revisa **antes** de llamar a Kafka: reemplaza `.` por `_` en el nombre pedido y en los existentes, y compara. El resultado es determinista y no depende del texto de la excepción del broker.

Queda un caso residual: dos altas simultáneas pasan la revisión y el broker rechaza la segunda. Como la sección 3.1 ya filtró los nombres inválidos, un `InvalidTopicException` o `TopicExistsException` posterior solo puede ser un choque, y se responde 409 `El nombre no esta disponible`, no 500.

### 4. Tópicos del sistema

Son los cinco de EP3-01: `requests.events`, `audit.timeline` y las tres DLT. Se declaran en `barriodigital.kafka.topics.*`, igual que `barriodigital.rabbit.*`.

| Operación | Respuesta | `message` |
|---|---|---|
| Eliminar | 409 | `El topico es del sistema y no se puede eliminar` |
| Aumentar particiones | 409 | `El topico es del sistema y no admite mas particiones` |
| Modificar una configuración que no sea `retention.ms` | 409 | `La configuracion no es editable en un topico del sistema` |

**Por qué no se aumentan particiones:** cambiaría la partición que corresponde a cada key. Los eventos nuevos de un trámite podrían procesarse antes que los anteriores, y el replay de una DLT dejaría de volver a la partición correcta (EP3-01, secciones 2 y 3).

### 5. Tópicos

#### 5.1 Listado

`GET /api/kafka/topics` usa `listInternal=false`, que excluye `__consumer_offsets` y `__transaction_state`.

```json
[
  { "name": "requests.events", "partitions": 3, "replicationFactor": 3, "system": true },
  { "name": "pruebas.carga", "partitions": 2, "replicationFactor": 2, "system": false }
]
```

#### 5.2 Detalle

`GET /api/kafka/topics/{name}` devuelve las particiones y las configuraciones de la lista de la sección 3.3, más las que no están en su valor por defecto. Las más de 30 configuraciones restantes no se devuelven.

```json
{
  "name": "requests.events.report.DLT",
  "system": true,
  "partitions": [
    { "partition": 0, "leader": 1, "replicas": [1, 2, 3], "isr": [1, 2, 3] },
    { "partition": 1, "leader": 2, "replicas": [2, 3, 1], "isr": [2, 3, 1] },
    { "partition": 2, "leader": 3, "replicas": [3, 1, 2], "isr": [3, 1, 2] }
  ],
  "configs": [
    { "name": "retention.ms", "value": "1209600000", "source": "TOPIC", "editable": true },
    { "name": "cleanup.policy", "value": "delete", "source": "TOPIC", "editable": false },
    { "name": "min.insync.replicas", "value": "2", "source": "TOPIC", "editable": false },
    { "name": "message.timestamp.type", "value": "LogAppendTime", "source": "TOPIC", "editable": false },
    { "name": "segment.ms", "value": "604800000", "source": "DEFAULT", "editable": false }
  ]
}
```

`editable` ya considera si el tópico es del sistema, así que el panel no repite la regla.

**Fuente de cada configuración:**

| Fuente de `AdminClient` | `source` |
|---|---|
| `DYNAMIC_TOPIC_CONFIG` | `TOPIC` |
| `DEFAULT_CONFIG` | `DEFAULT` |
| Cualquier otra (`STATIC_BROKER_CONFIG`, `DYNAMIC_BROKER_CONFIG`, `DYNAMIC_DEFAULT_BROKER_CONFIG`, `UNKNOWN` y las que agreguen versiones futuras) | `BROKER` |

kafka-admin crea los tópicos del sistema con los parámetros de EP3-01 explícitos, así que esos valores aparecen como `TOPIC` y no como `BROKER`.

#### 5.3 Alta

```json
{
  "name": "pruebas.carga",
  "partitions": 2,
  "replicationFactor": 2,
  "configs": { "retention.ms": "3600000", "segment.ms": "3600000" }
}
```

Respuesta 201 con el detalle de la sección 5.2.

#### 5.4 Modificaciones

`PATCH /api/kafka/topics/{name}/configs`:

```json
{ "configs": { "retention.ms": "259200000" } }
```

`PATCH /api/kafka/topics/{name}/partitions`:

```json
{ "partitions": 6 }
```

El valor tiene que ser mayor que el actual y no superar 12. Las particiones no disminuyen, porque Kafka no lo permite.

Las dos responden 200 con el detalle de la sección 5.2.

#### 5.5 Eliminación

`DELETE /api/kafka/topics/{name}` responde 204. Antes de eliminar, kafka-admin lista los consumer groups y los describe. Si algún grupo con miembros conectados tiene particiones asignadas de ese tópico, responde 409 `El topico tiene consumidores activos`.

### 6. Consumer groups

#### 6.1 Grupos del sistema

`report-group` y `audit-group` se declaran en `barriodigital.kafka.*`, con los tópicos que consume cada uno:

| Grupo | Tópicos |
|---|---|
| `report-group` | `requests.events` |
| `audit-group` | `requests.events`, `audit.timeline` |

Se tratan como existentes aunque el broker los haya borrado. Kafka borra los offsets de un grupo vacío después de `offsets.retention.minutes` (7 días por defecto), y después borra el grupo. Ese es justo el caso en que hace falta reconstruir. El listado los muestra siempre: si el broker ya no los tiene, con estado `DEAD` y 0 miembros. `alterConsumerGroupOffsets` los vuelve a crear al escribir los offsets.

#### 6.2 Listado

```json
[
  { "groupId": "report-group", "state": "STABLE", "members": 1, "system": true },
  { "groupId": "audit-group", "state": "DEAD", "members": 0, "system": true }
]
```

#### 6.3 Detalle y lag

`GET /api/kafka/consumer-groups/{groupId}` devuelve, por tópico y partición, el offset confirmado, el offset final y el lag. Los tópicos son los declarados para los grupos del sistema, y los que tienen offsets confirmados para los demás grupos.

```json
{
  "groupId": "report-group",
  "state": "STABLE",
  "members": 1,
  "system": true,
  "topics": [
    {
      "topic": "requests.events",
      "partitions": [
        { "partition": 0, "committedOffset": 1402, "endOffset": 1410, "lag": 8, "lagBasis": "COMMITTED" },
        { "partition": 1, "committedOffset": 2045, "endOffset": 2045, "lag": 0, "lagBasis": "COMMITTED" },
        { "partition": 2, "committedOffset": 988, "endOffset": 991, "lag": 3, "lagBasis": "COMMITTED" }
      ]
    }
  ]
}
```

| Caso | `lag` | `lagBasis` |
|---|---|---|
| Partición con offset confirmado | Offset final − confirmado | `COMMITTED` |
| Grupo del sistema, partición sin offset | Offset final − primer offset disponible | `EARLIEST` |
| Otro grupo, partición sin offset | `null` | `null` |

En los grupos del sistema, el lag sin offset es el real: con `auto-offset-reset=earliest`, eso es lo que leerán al conectarse. En los demás grupos, kafka-admin no conoce su política de reset y no inventa un número.

**El lag es una distancia de offsets, no una cantidad exacta de mensajes.** En `audit.timeline`, que es compactado, algunos offsets ya no tienen mensaje, y el lag puede ser mayor que lo que realmente falta leer.

#### 6.4 Reset de offsets

```
POST /api/kafka/consumer-groups/{groupId}/offsets/reset
```

```json
{
  "topic": "requests.events",
  "strategy": "TIMESTAMP",
  "timestamp": "2026-11-10T00:00:00Z",
  "dryRun": true
}
```

| Campo | Regla |
|---|---|
| `topic` | Obligatorio. El reset aplica a todas las particiones de ese tópico para ese grupo. No se elige partición por partición |
| `strategy` | `EARLIEST`, `LATEST` o `TIMESTAMP` |
| `timestamp` | Obligatorio con `TIMESTAMP`. Instant ISO-8601 en UTC. Si es futuro, 400 |
| `dryRun` | Obligatorio. En el DTO es `Boolean` con `@NotNull`, no `boolean`: con un primitivo, Jackson pone `false` si falta y el 400 nunca salta |

**Cálculo con `TIMESTAMP`:**
- si una partición no tiene mensajes desde esa fecha, queda en su offset final;
- si la fecha es anterior a la retención, queda en su primer offset disponible.

**Restricciones en los grupos del sistema.** Mover un offset hacia adelante salta eventos. En `report-group` los KPIs quedarían mal sin aviso. En `audit-group` los eventos saltados nunca llegarían a Oracle, la fuente histórica definitiva. Mover hacia atrás es seguro, porque los consumidores son idempotentes (EP3-02, sección 9).

| Estrategia | Partición con offset confirmado | Partición sin offset confirmado |
|---|---|---|
| `EARLIEST` | Permitido | Permitido |
| `LATEST` | 409 | 409 |
| `TIMESTAMP` | Permitido si no supera el offset confirmado | 409 |

Una partición sin offset confirmado solo acepta `EARLIEST`. Si los offsets expiraron, no se sabe hasta dónde había llegado el grupo, y un `TIMESTAMP` podría saltar eventos. Los grupos que no son del sistema no tienen estas restricciones.

**Errores:**

| Código | Caso | `message` |
|---|---|---|
| 400 | Falta `topic` | `topic es obligatorio` |
| 400 | Falta `dryRun` | `dryRun es obligatorio` |
| 400 | Estrategia inválida | `La estrategia debe ser EARLIEST, LATEST o TIMESTAMP` |
| 400 | Falta `timestamp` con `TIMESTAMP` | `timestamp es obligatorio con TIMESTAMP` |
| 400 | `timestamp` futuro | `timestamp no puede ser futuro` |
| 404 | Grupo inexistente que no es del sistema | `El grupo no existe` |
| 404 | Tópico inexistente | `El topico no existe` |
| 409 | El grupo tiene miembros activos | `El grupo tiene miembros activos` |
| 409 | Grupo del sistema y tópico fuera de su lista | `El grupo no consume ese topico` |
| 409 | Otro grupo sin offsets confirmados en el tópico | `El grupo no tiene offsets en ese topico` |
| 409 | Grupo del sistema y el reset adelantaría offsets | `El reset adelantaria offsets en las particiones 0, 2` |

**El dry run aplica las mismas validaciones que la operación real**, incluidos los 409. Así predice exactamente lo que va a pasar.

**Respuesta**, con la misma forma con y sin `dryRun`:

```json
{
  "groupId": "report-group",
  "topic": "requests.events",
  "strategy": "TIMESTAMP",
  "dryRun": true,
  "partitions": [
    { "partition": 0, "currentOffset": 1402, "targetOffset": 1210, "lagAfter": 200 },
    { "partition": 1, "currentOffset": 2045, "targetOffset": 1830, "lagAfter": 215 },
    { "partition": 2, "currentOffset": 988, "targetOffset": 860, "lagAfter": 131 }
  ]
}
```

**Procedimiento operativo, en una ventana de mantenimiento:**
1. Detener el consumidor (por ejemplo, `docker compose stop report`), para que el grupo quede sin miembros.
2. Ejecutar el reset con `dryRun: true` y revisar los offsets resultantes.
3. Ejecutarlo con `dryRun: false`.
4. Levantar el consumidor y seguir el lag en Kafka UI hasta que llegue a 0.

### 7. DLT

#### 7.1 Listado

```
GET /api/kafka/dlt/{name}/messages?partition=1&fromOffset=2040&limit=20
```

1. **Lectura sin grupo:** kafka-admin lee con un consumidor asignado directamente a las particiones, sin `group.id` y sin confirmar offsets. Así no aparece un grupo extra con lag propio en Kafka UI ni en el listado de grupos.
2. **Paginación por partición, del más antiguo al más nuevo:**

| Parámetro | Regla |
|---|---|
| `partition` | Opcional. Sin él, se leen las 3 particiones |
| `fromOffset` | Opcional. Exige `partition`; si no, 400. Por defecto, el primer offset disponible. Si es anterior a la retención, se ajusta al primer offset disponible |
| `limit` | Por partición. Por defecto 20, de 1 a 100 |

La respuesta se agrupa por partición, con `nextOffset` para la página siguiente, o `null` al llegar al final. No hay paginación global, porque mezclar particiones obligaría a ordenar por timestamp sin reflejar el orden real de procesamiento.

3. **Campos de cada mensaje:**

| Campo | Origen |
|---|---|
| `partition`, `offset`, `key` | El registro |
| `receivedAt` | Timestamp del registro: la hora de llegada a la DLT (`LogAppendTime`) |
| `eventId`, `eventType` | Leídos del JSON. `null` si el valor es ilegible |
| `value` | El JSON como texto. Ya viene minimizado (EP3-01, sección 8) |
| `originalTopic`, `originalPartition`, `originalOffset`, `originalTimestamp` | Headers `kafka_dlt-original-*` |
| `consumerGroup` | `kafka_dlt-original-consumer-group` |
| `exceptionClass`, `exceptionCause`, `exceptionMessage` | Headers `kafka_dlt-exception-*` |

El stacktrace no va en el listado: puede pesar varios KB por mensaje y no sirve para decidir el replay. Queda en el header, visible en Kafka UI.

```json
{
  "dlt": "requests.events.report.DLT",
  "partitions": [
    {
      "partition": 1,
      "nextOffset": null,
      "messages": [
        {
          "partition": 1,
          "offset": 2040,
          "key": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
          "receivedAt": "2026-11-12T14:02:11.390Z",
          "eventId": "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d",
          "eventType": "request.status-changed",
          "value": "{\"eventId\":\"9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d\", ...}",
          "originalTopic": "requests.events",
          "originalPartition": 1,
          "originalOffset": 2045,
          "originalTimestamp": "2026-11-10T15:40:03.112Z",
          "consumerGroup": "report-group",
          "exceptionClass": "org.springframework.kafka.listener.ListenerExecutionFailedException",
          "exceptionCause": "java.sql.SQLRecoverableException",
          "exceptionMessage": "Oracle no disponible"
        }
      ]
    }
  ]
}
```

4. **Tope de tiempo:** la lectura termina al completar `limit` o al llegar al offset final de la partición, con un tope de 5 segundos.
5. **Errores:**

| Código | Caso | `message` |
|---|---|---|
| 400 | `name` no es una de las 3 DLT del sistema | `El nombre no corresponde a una DLT del sistema` |
| 400 | La partición no existe en esa DLT | `La particion no existe` |
| 400 | `fromOffset` sin `partition` | `fromOffset exige partition` |
| 400 | `limit` fuera de rango | `limit debe estar entre 1 y 100` |

#### 7.2 Replay

```
POST /api/kafka/dlt/{name}/replay
```

Por offset:

```json
{ "offsets": [ { "partition": 1, "offset": 2040 }, { "partition": 1, "offset": 2041 } ] }
```

Por `eventId`:

```json
{ "eventIds": ["9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"] }
```

1. **Selección:** `offsets` o `eventIds`, uno de los dos y nunca ambos, con un máximo de 100 en total. Los mensajes ilegibles, sin `eventId`, solo se eligen por offset. Si un mismo `eventId` aparece varias veces en la DLT porque falló más de una vez, se reenvía una sola vez, la ocurrencia más reciente, y las demás quedan `OMITIDO`.
2. **Búsqueda por `eventId`:** Kafka no indexa por contenido, así que la búsqueda recorre las 3 particiones del offset más antiguo al más nuevo, hasta su offset final, con un tope de 5 segundos.
3. **Destino:** el tópico de `kafka_dlt-original-topic` y la partición de `kafka_dlt-original-partition`, no el particionador del productor. Hoy dan el mismo resultado, porque las particiones de los tópicos del sistema no cambian, pero el header no depende de esa coincidencia.
4. **Contenido del mensaje reenviado:**
   - la misma key y el mismo valor, así que se conservan `eventId` y `occurredAt`;
   - **timestamp del registro con la hora actual**, para que la retención no borre la copia apenas publicada;
   - se quitan todos los headers `kafka_dlt-*`;
   - se agregan `x-replayed-from-dlt` (nombre de la DLT) y `x-replayed-at` (instant UTC).
5. **Orden:** la selección se ordena por partición y offset, y se publica en ese orden. Cada envío espera su confirmación antes del siguiente.
6. **Falla:** ante la primera falla, la operación se detiene, con el mismo criterio del relay (EP3-02, sección 3.1): seguir podría publicar un evento posterior del mismo trámite antes que el que falló. Esto también frena las particiones que no tienen relación con la falla. Es más estricto de lo necesario, pero es simple.
7. **Tope de tiempo:** la operación completa tiene un tope de **23 segundos**, que incluye la verificación previa de brokers, la búsqueda y la publicación. Antes de cada envío tienen que quedar al menos **15 segundos**, el peor caso de un envío del productor de EP3-02:
   - `max.block.ms` (5 s): `send()` puede bloquearse esperando metadatos antes de que el mensaje salga;
   - `delivery.timeout.ms` (10 s): empieza a contar cuando `send()` retorna.

   Si no quedan 15 segundos, el mensaje no se envía y queda `NO_INTENTADO`. Un envío sin confirmación dentro de su espera queda `FALLIDO` con motivo `sin confirmacion`, y la operación se detiene: puede haberse publicado, y la idempotencia de los consumidores absorbe el posible duplicado. Con esto, `NO_INTENTADO` significa siempre que el mensaje no salió de kafka-admin, y se puede reintentar sin riesgo.

8. **Estados por mensaje:**

| Estado | Cuándo |
|---|---|
| `REENVIADO` | Publicado y confirmado |
| `OMITIDO` | Offset inexistente o fuera de retención, `eventId` no encontrado tras la búsqueda completa, u ocurrencia repetida del mismo `eventId` en la DLT |
| `FALLIDO` | El envío falló o no se confirmó a tiempo. Puede haber uno solo, porque ahí se detiene la operación |
| `NO_INTENTADO` | Venía después del fallido, no quedaban 15 segundos antes del tope, o la búsqueda se agotó antes de encontrarlo (motivo `busqueda agotada`) |

La búsqueda avanza en cada partición del offset más antiguo al más nuevo, así que lo que no se alcanzó a buscar está después de lo encontrado en esa partición. Reenviar lo encontrado no adelanta ningún evento.

9. **Respuesta:** 200 con el detalle, aunque haya mensajes `FALLIDO` o `NO_INTENTADO`.

```json
{
  "dlt": "requests.events.report.DLT",
  "targetTopic": "requests.events",
  "resent": 1,
  "skipped": 0,
  "failed": 1,
  "notAttempted": 1,
  "results": [
    { "partition": 1, "offset": 2040, "eventId": "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d", "status": "REENVIADO", "reason": null },
    { "partition": 1, "offset": 2041, "eventId": "0c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f", "status": "FALLIDO", "reason": "sin confirmacion" },
    { "partition": 2, "offset": 377, "eventId": "1d2e3f4a-5b6c-4d7e-9f80-a1b2c3d4e5f6", "status": "NO_INTENTADO", "reason": "operacion detenida" }
  ]
}
```

10. **Errores:**

| Código | Caso | `message` |
|---|---|---|
| 400 | `name` no es una de las 3 DLT del sistema | `El nombre no corresponde a una DLT del sistema` |
| 400 | `offsets` y `eventIds` juntos, o ninguno | `Indica offsets o eventIds, no ambos` |
| 400 | Más de 100 mensajes | `El replay admite hasta 100 mensajes` |
| 503 | Ningún broker disponible en la verificación previa | `Kafka no esta disponible` |

11. **Efecto en los otros grupos:** el replay vuelve al tópico original, así que lo leen todos sus grupos, también los que ya lo habían procesado. La idempotencia descarta esas copias (EP3-02, sección 9). Este es el caso que acota la regla entre retenciones (EP3-01, sección 2).

### 8. Tiempos

| Tramo | Tope | Motivo |
|---|---|---|
| API Gateway (HTTP API) | 30 s | Límite de la integración |
| BFF → kafka-admin, lectura | 25 s | Menor que el del Gateway (EP3-44) |
| Replay completo | 23 s | Menor que el del BFF. Incluye la verificación de brokers, la búsqueda y la publicación |
| Reserva antes de cada envío del replay | 15 s | `max.block.ms` + `delivery.timeout.ms` |
| Búsqueda por `eventId` y listado de la DLT | 5 s | |
| Cada llamada de `AdminClient` | 5 s | `default.api.timeout.ms`. El valor por defecto de 60 s dejaría el endpoint colgado y el BFF cortaría antes |

Las operaciones de varias llamadas quedan dentro de los 25 s del BFF:
- el reset hace hasta cuatro llamadas (describir el grupo, leer sus offsets, calcular los nuevos y aplicarlos), 20 s en el peor caso;
- la eliminación hace tres (listar los grupos, describirlos y eliminar), 15 s en el peor caso.

**Comportamiento degradado del replay:** si la verificación de brokers y la búsqueda agotan sus 5 s cada una, quedan 13 s, menos que la reserva de 15 s, y no se envía ningún mensaje. Todos quedan `NO_INTENTADO`, que se puede reintentar sin riesgo. En condiciones normales la verificación tarda milisegundos, y la ventana de envío es de al menos 3 s.

### 9. Creación inicial de tópicos

Al arrancar, kafka-admin crea los tópicos del sistema que falten, con los parámetros de EP3-01, sección 2, incluido `message.timestamp.type=LogAppendTime` en las DLT.

1. **Tópico existente con diferencias:** no lo modifica y registra un WARN por cada configuración distinta:

```text
WARN topico-con-diferencias topic=requests.events config=retention.ms esperado=604800000 actual=259200000
```

Un `retention.ms` cambiado desde la API dentro de su rango no es un error, pero igual se informa.

2. **Kafka no disponible al arrancar:** el servicio arranca igual, reintenta la creación cada 10 segundos hasta lograrla, y mientras tanto los endpoints responden 503.

Ningún otro servicio crea tópicos (EP3-01, sección 1). Por eso, en el despliegue, kafka-admin va antes que report, audit y requests (EP3-56).

### 10. Auditoría

Las operaciones exitosas publican en `audit.timeline` según EP3-01, sección 7, y EP3-02, sección 6.

| Operación | `eventType` | `before` | `after` |
|---|---|---|---|
| Alta de tópico | `topic.created` | `null` | Particiones, réplicas y configuraciones |
| Cambio de configuraciones | `topic.updated` | Valores anteriores de las claves cambiadas | Valores nuevos |
| Aumento de particiones | `topic.updated` | `{ "partitions": 3 }` | `{ "partitions": 6 }` |
| Eliminación de tópico | `topic.deleted` | Particiones, réplicas y configuraciones | `null` |
| Reset de offsets con `dryRun: false` | `consumer-group.offsets-reset` | Offsets anteriores por partición | Tópico, estrategia y offsets resultantes por partición |
| Replay | `topic.dlt-replayed` | `null` | Estado de cada `eventId`, aunque la operación se haya detenido a mitad |

Las consultas y los dry run no generan eventos. El replay se audita aunque se detenga, porque lo que sí se reenvió ya cambió el sistema.

### 11. Límites conocidos

1. **Replays repetidos:** kafka-admin no tiene base de datos y Kafka no permite borrar un mensaje individual de la DLT. Un segundo replay del mismo mensaje lo reenvía otra vez. La idempotencia lo absorbe, salvo el caso de los 30 días en report (EP3-02, sección 10). El panel de EP3-73 podría marcar los `eventId` ya reenviados consultando los eventos `topic.dlt-replayed` en audit. Es opcional.
2. **El replay se detiene ante la primera falla**, también en particiones no relacionadas con ella.
3. **Replay degradado:** con una verificación de brokers y una búsqueda lentas, puede no enviarse nada dentro del tope (sección 8).
4. **Búsqueda por `eventId`:** recorre la DLT completa dentro de un tope de 5 segundos. Con 14 días de retención y el volumen de la demo, el costo es bajo.
5. **Lag en tópicos compactados:** es una distancia de offsets y puede ser mayor que lo que falta leer (sección 6.3).
6. **Tópicos `_confluent-*`:** con las imágenes comunitarias de Confluent no deberían aparecer. Si aparecieran en la nube, convendría excluirlos del listado como los internos.
7. **Sin cambio de réplicas:** el factor de replicación no se modifica desde la API. Requiere una reasignación de particiones, fuera de alcance.
8. **Replay en `audit.timeline`:** un evento antiguo reprocesado después de uno más nuevo con la misma key queda como el último valor compactado. audit no se afecta, porque guarda todos los eventos y ordena por `occurredAt`; Oracle sigue siendo la fuente definitiva (EP3-01, sección 2).
