<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: folio y asignación (EP3-05)

Define el folio que identifica un trámite ante el vecino, y cómo un trámite se toma, se asigna y se reasigna. Es la base de EP3-28 (folio en requests), EP3-29 (asignación en requests), EP3-45 (BFF), EP3-47 (frontend) y EP3-55 (Gateway). Parte de la matriz y de la regla de operación de EP3-04, secciones 2 y 3.

Las rutas nuevas van en inglés (`take`, `assignee`, `assignees`), según la convención 13 del backlog. Las existentes en español (`/actividad`, `/gestiones`) se mantienen.

### 1. Folio

#### 1.1 Formato

`BD-AAAA-NNNNNN`. Por ejemplo, `BD-2026-000123`, el mismo valor que usan los ejemplos de EP3-01.

- `AAAA` es el año de `created_at` en `America/Santiago`, la misma zona que usan los cupos (EP1.5-03). Un trámite creado el 31-dic a las 22:00 en Chile es del año que termina, aunque en UTC ya sea 1-ene.
- `NNNNNN` es un correlativo de 6 dígitos con ceros a la izquierda, que reinicia cada año.

Es el número de seguimiento del vecino, como en los sistemas 311 y en las OIRS. No es un folio legal: los PDF de notify lo muestran como identificación del trámite, sin cambiar lo que declara la sección de certificados.

#### 1.2 Numeración sin huecos

La numeración usa la tabla `folio_counter`:

| Columna | Tipo | Regla |
|---|---|---|
| `folio_year` | `NUMBER(4)` | PK |
| `last_number` | `NUMBER` | `NOT NULL`. Último número entregado en ese año |

**Por qué una tabla y no secuencias de Oracle:** una secuencia no reinicia sola cuando cambia el año, y exigiría crear `seq_folio_AAAA` cada año. Además deja huecos con cada rollback y puede saltar números por el caché entre instancias de Oracle Autonomous. Un folio que el vecino ve tiene que ser correlativo: un salto en la numeración genera preguntas en una auditoría. Con la tabla, el contador se incrementa en la misma transacción del alta, y un alta revertida devuelve su número.

**Nombres:** se evitan `year` y `value`, que son palabras reservadas en H2 2.x (el caso de `sequence` en EP3-02), y `last_value`, que es una función analítica en Oracle y en H2.

**Costo aceptado:** el bloqueo de la fila del año pone las altas simultáneas en fila, una tras otra. Con el volumen de una comuna no pesa.

#### 1.3 Generación

La generación usa solo JPA, sin SQL nativo, para que los tests en H2 prueben la misma lógica que corre en Oracle.

1. **Un solo instante.** `created_at`, el año del folio y el `occurred_at` de la fila `CREADO` salen del mismo `Instant`, tomado de un `Clock` inyectado. Con EP3-31, también el `occurredAt` de `request.created`. Si se leyera el reloj dos veces, un alta en el borde del año podría preparar la fila de un año y guardar el trámite en el siguiente. Hoy `MunicipalRequest` toma `Instant.now()` en su constructor y en `@PrePersist`; el instante pasa a recibirse desde afuera.
2. **La fila del año existe antes del alta.** `FolioCounterService.ensureYear(year)`, en un bean propio con `REQUIRES_NEW`, consulta `existsById` y solo inserta `(year, 0)` si falta. No captura excepciones.
   - Se llama **antes** de abrir la transacción del alta, desde un orquestador sin transacción. Así el alta no ocupa dos conexiones del pool y no tiene ningún bloqueo mientras corre la transacción interna.
   - El orquestador es el **único punto de entrada** de las dos altas, la JSON y la multipart. `RequestController` lo llama en vez de `RequestService.create`.
   - Si dos altas crean la fila del año al mismo tiempo, una recibe `DataIntegrityViolationException`. La captura el llamador, fuera de toda transacción, y sigue: la fila ya existe.
   - Por qué el `catch` no va dentro de `ensureYear`: con `persist`, la violación salta en el commit, después del cuerpo del método. Con `saveAndFlush`, cruza el proxy del repositorio y deja la transacción interna *rollback-only*. Dentro de la transacción del alta, el error dejaría el alta *rollback-only*.
3. **El número se toma dentro del alta.** `findByIdForUpdate(year)` con `PESSIMISTIC_WRITE`, `last_number + 1` y el folio formateado, justo antes de guardar el trámite, después de sanear la imagen, para que el bloqueo dure lo menos posible. Si la fila no existe, cosa que no debería pasar después de `ensureYear`, se lanza `IllegalStateException("Falta el contador de folio del año AAAA")`, que responde 500 y revierte el alta. Nunca se toma un número de otra forma.
4. **Unicidad e inmutabilidad.** `municipal_requests.folio` es `UNIQUE` y `NOT NULL`, con `@Column(updatable = false)`. Ningún endpoint lo modifica.
5. **Tope.** Si un año pasa de 999.999 trámites, el alta responde 500 con un error explícito en el log. Es un límite por diseño (sección 10).

#### 1.4 Trámites existentes

Un script en `db/` de requests, documentado en su README. Corre en una **ventana de mantenimiento**, como el reset de offsets de EP3-03, sección 6.4:

0. **Detener requests.** La versión anterior no conoce `folio`: si sigue creando trámites durante el script, el `NOT NULL` hace fallar cada alta, o deja trámites sin folio y `folio_counter` desfasado.
1. Agrega `folio` como columna nullable y crea `folio_counter`.
2. Numera con `ROW_NUMBER() OVER (PARTITION BY folio_year ORDER BY created_at, id)`, donde `folio_year = EXTRACT(YEAR FROM (created_at AT TIME ZONE 'America/Santiago'))`. `created_at` es `TIMESTAMP WITH TIME ZONE`, así que `AT TIME ZONE` convierte desde el offset guardado, sin suponer UTC. `id` desempata los trámites con el mismo `created_at`, para que el resultado sea determinista.
3. Aplica `NOT NULL` y `UNIQUE`. `ddl-auto: update` no agrega un `NOT NULL` sobre filas existentes (el mismo caso de `daily_quota`), por eso va en el script.
4. Inicializa `folio_counter` con el máximo de cada año, más una fila para el año en curso y otra para el siguiente. Con eso, `ensureYear` casi nunca inserta. Sigue como respaldo si el lab se recrea.
5. **Desplegar EP3-28 y levantar requests.**

Notify no necesita desplegarse antes (sección 1.5).

#### 1.5 Dónde aparece

`folio` va en `RequestView` para los cuatro roles, en los eventos de `requests.events` (EP3-01) y en `RequestEventPayload` de RabbitMQ, para los correos y PDF de notify.

**Compatibilidad con RabbitMQ:** agregar `folio` al payload es un cambio compatible. El `EnvelopeParser` de notify lee el `payload` como `JsonNode` y cada consumidor toma solo los campos que conoce, así que un campo nuevo se ignora y no manda el mensaje a la DLQ. Por eso EP3-28 se puede desplegar antes que el cambio de notify que lo muestra. EP2-01, sección 2, se actualiza con el campo.

### 2. Responsable

1. **A lo más un responsable por trámite**, en las columnas `assignee_id` (`oid`) y `assignee_name` (snapshot del nombre) de `municipal_requests`. Se exponen solo a través de `RequestView` (EP3-04, sección 6.1).
2. **El responsable siempre es un Funcionario** de la lista de la sección 5. El Admin asigna, pero nunca es responsable (EP3-04, sección 2, regla 1).
3. **No se puede soltar un trámite.** Nadie, ni el Admin, devuelve un trámite a "sin responsable". Un trámite que se toma y vuelve a la bandeja general queda sin nadie a cargo, y la celeridad de la Ley 19.880 exige que alguien responda por él. Además, `assigneeId` es no nulo en `request.assigned` (EP3-01, sección 6). Si un Funcionario no puede seguir con un trámite, se lo entrega a un colega con motivo. Si deja la municipalidad, el Admin reasigna sus trámites.

### 3. Endpoints

| Endpoint | Roles | Body | Respuesta |
|---|---|---|---|
| `POST /api/requests/{id}/take` | Funcionario | Sin body | 200 con `RequestView` |
| `PUT /api/requests/{id}/assignee` | Admin (cualquier trámite) y Funcionario (solo los suyos) | `{ "assigneeId": "...", "reason": "..." }` | 200 con `RequestView` |
| `GET /api/requests/assignees` | Funcionario, Admin | | 200 con `[{ "id": "...", "name": "..." }]` |

#### 3.1 Tomar

El Funcionario se asigna a sí mismo un trámite **sin responsable**. Es la acción principal en un trámite sin asignar (EP3-04, sección 3, regla 5). El Admin no toma trámites: los asigna.

#### 3.2 Asignar y reasignar

Un solo endpoint cubre los dos casos, y la operación se distingue por el estado del trámite dentro del bloqueo:

| Caso | Quién | `reason` |
|---|---|---|
| **Primera asignación** (el trámite no tiene responsable) | Solo el Admin. El Funcionario toma, no asigna | Se ignora |
| **Reasignación** (el trámite tiene responsable) | El Admin, en cualquier trámite. El Funcionario, solo si es el responsable | Obligatorio |

- **Asignar no es una intervención.** Es la función normal del Admin (EP3-04, sección 3, regla 3), y no lleva `interventionReason`.
- **El Funcionario no asigna un trámite sin responsable.** Si quiere atenderlo, lo toma. Así la derivación inicial queda en manos de quien supervisa, como en la matriz de EP3-04.

#### 3.3 Motivo

`reason` explica una reasignación, y es parte de la trazabilidad que pide la auditoría (EP3-01, sección 8):

- **En una reasignación**, es obligatorio, de 1 a 500 caracteres después de `trim`.
- **En una primera asignación, se ignora:** no se guarda y va `null` en el evento, como pide la regla de asignación de EP3-01. Sigue el precedente de `rejectionReason`, que se ignora en cualquier transición que no sea un rechazo (EP1.5-01). El frontend muestra el campo solo cuando `hasAssignee` es `true`.
- **El tope de 500 caracteres se valida siempre** con `@Valid`, aunque después el valor se ignore. Es el mismo comportamiento de `rejectionReason`, y no es una contradicción: el body se valida antes de conocer el trámite.

#### 3.4 Estados permitidos

Tomar, asignar y reasignar están permitidos en los estados abiertos: `INGRESADO`, `ADMITIDO`, `EN_GESTION` y `EN_TERRENO`. En `RESUELTO` y `RECHAZADO`, 409.

#### 3.5 Bloqueo y concurrencia

Los dos endpoints de escritura leen el trámite con `findByIdForUpdate` (`PESSIMISTIC_WRITE`) y evalúan permisos, motivo y estado dentro de ese bloqueo, en la misma transacción que el cambio, la actividad y el evento del outbox (EP3-02, sección 2.3).

| Carrera | Resultado |
|---|---|
| Dos funcionarios toman el mismo trámite | El segundo recibe 409 `El tramite ya tiene responsable` |
| El Admin asigna sin motivo un trámite que alguien tomó entretanto | 400 `reason es obligatorio al reasignar`. El frontend recarga el trámite y muestra el campo de motivo |
| Reasignación y cambio de estado del responsable anterior | Lo resuelve EP3-04, sección 3, regla 4: el cambio de estado que llega segundo ve al nuevo responsable y recibe 403 |

### 4. Orden de los errores

Sigue el esquema de EP3-04, sección 5.

| Paso | Código | Caso | Mensaje |
|---|---|---|---|
| 1 | 401 | Sin token | |
| 2 | 403 | Sin rol, con más de un rol, Vecino o Auditor | Los de EP3-04. Vecino o Auditor: `No tienes el rol necesario para este recurso`, el mismo del BFF |
| 2 | 403 | El Admin llama a `take` | `Solo un Funcionario puede tomar un tramite` |
| 3 | 400 | `assigneeId` ausente | `assigneeId es obligatorio` |
| 3 | 400 | `assigneeId` que no está en `/assignees` | `El destinatario debe ser un Funcionario de la lista` |
| 3 | 400 | `reason` de más de 500 caracteres | `reason no puede superar 500 caracteres` |
| 4 | 404 | El trámite no existe | |
| 5 | 403 | Funcionario que reasigna un trámite del que no es responsable | `Solo el responsable del tramite puede reasignarlo` |
| 5 | 403 | Funcionario que asigna un trámite sin responsable | `Un tramite sin responsable se toma, no se asigna` |
| 6 | 400 | Reasignación sin `reason` | `reason es obligatorio al reasignar` |
| 7 | 409 | Trámite en `RESUELTO`, `RECHAZADO` o `CANCELADO` | `No se puede asignar un tramite cerrado` |
| 7 | 409 | El destinatario ya es el responsable, incluido el Funcionario que se reasigna a sí mismo | `El tramite ya esta asignado a ese funcionario` |
| 7 | 409 | `take` sobre un trámite que ya tiene responsable, incluido el propio | `El tramite ya tiene responsable` |

**Diferencia con EP3-04, sección 5:** allí todo 400 va antes del 404. Aquí el paso 6 va después del bloqueo, porque saber si el motivo es obligatorio depende de si el trámite tiene responsable, y eso solo se sabe con la fila bloqueada. Es inevitable, y es lo que protege la carrera de la sección 3.5.

**Por qué 409 y no 400 cuando el responsable no cambia:** el body es válido, y el error depende del estado actual del trámite, que es lo que expresa el 409 en el resto del proyecto. No se responde 200 idempotente, porque generaría un evento sin cambio real o una respuesta que no dice lo que pasó.

**Quién aplica cada paso** (EP3-04, principio 2):
- **BFF:** pasos 1 y 2, y las validaciones de forma del paso 3 (`assigneeId` ausente, tamaño de `reason`).
- **requests:** pasos 2 a 7, de forma autoritativa. Vuelve a comprobar el rol, y comprueba que el destinatario esté en la lista, porque `staff_member` vive en requests.

**`GET /api/requests/assignees`:** 401 sin token, y 403 sin rol, con más de un rol, para el Vecino y para el Auditor, con los mensajes de EP3-04.

### 5. Lista de funcionarios

#### 5.1 Fuente

La plataforma no consulta el directorio de Entra ID. Se descartó derivar la lista de `request_activity`: la columna `actor_role` recién nace en EP3-31, que va después de EP3-29, y un Funcionario sin actividad no aparecería, así que no se le podría asignar su primer trámite.

requests guarda un registro propio, la tabla `staff_member`:

| Columna | Regla |
|---|---|
| `oid` | PK. `X-User-Id` |
| `name` | `X-User-Name`, el último visto |
| `role` | El único rol de `X-User-Roles`, el último visto |
| `first_seen_at`, `last_seen_at` | Instantes de la primera y la última llamada registrada |

1. **Se actualiza en cada llamada de staff** (Funcionario, Admin o Auditor) a requests, con los headers que reenvía el BFF después de validar el JWT. Solo cuenta una llamada a `/api/**` con `X-User-Id` y con **exactamente un** rol de staff en `X-User-Roles`: sin rol, con más de uno o con `Vecino` no se registra, porque esa llamada termina en 403 o no es de staff. Un caché en memoria limita la escritura a una vez cada 15 minutos por `oid`. Si cambia el rol o el nombre en Entra ID, la fila se actualiza en la siguiente llamada.
2. **El Vecino no se registra.** La tabla es solo de staff, por minimización de datos (Ley 21.719).
3. **Un fallo del registro no bloquea la llamada.** El upsert corre **antes** del caso de uso, en un `HandlerInterceptor`, con una transacción propia en `StaffMemberService.touch`, que no captura excepciones. El interceptor captura el error, lo registra en el log y deja seguir la llamada. Si el upsert corriera dentro de la transacción del caso de uso, una violación de PK en el primer acceso simultáneo del mismo `oid` la dejaría *rollback-only*, como en el folio (sección 1.3). Ante esa violación, `touch` no reintenta: la fila ya existe y la próxima llamada la actualiza.
4. **El Funcionario aparece desde su primera llamada a requests.**

#### 5.2 `GET /api/requests/assignees`

Devuelve los registros con rol `Funcionario`, ordenados por nombre, con solo `id` y `name`: sin correo ni fechas. Es una ruta literal, para que `{id}` no la capture, en el controlador de requests, en el BFF y en el Gateway, como `meta/transitions`.

El destinatario de `PUT /assignee` tiene que estar en esa lista. `assignee_name` se copia de `staff_member.name`.

### 6. Historial

1. **Nuevo `ActivityKind.ASIGNACION`.** Cada toma, asignación o reasignación agrega una fila `ASIGNACION` `INTERNO`, con el actor (quien la hizo) en `actor_id` y `actor_name`, y estas columnas:

   | Columna de `request_activity` | Contenido | Campo en `/actividad` (solo staff) |
   |---|---|---|
   | `assignee_id`, `assignee_name` (nuevas, nullables) | El nuevo responsable | `assigneeId`, `assigneeName` |
   | `previous_assignee_id`, `previous_assignee_name` (nuevas, nullables) | El responsable anterior. `null` en la primera asignación | `previousAssigneeId`, `previousAssigneeName` |
   | `reason` (ya existe, `VARCHAR2(500)`) | El motivo de la reasignación. `null` en la primera asignación | `reason` |

   - `reason` es la misma columna que hoy guarda el motivo de rechazo en las filas `ESTADO`: cada `kind` la usa para su propio motivo, sin agregar otra columna.
   - Los nombres son snapshots, como `actor_name`, para que el staff lea "Ana reasignó de Pedro a Luisa" aunque después cambie un nombre en Entra ID. Las columnas nuevas solo se usan en `ASIGNACION`, y el Vecino nunca las recibe.
   - El `summary` de la fila interna es "Tomó el trámite", "Asignó a {nuevo}" o "Reasignó de {anterior} a {nuevo}. Motivo: {reason}".
2. **Hito público solo en la primera asignación** (EP3-04, sección 6.2): una segunda fila `ASIGNACION` `PUBLICO`, en el mismo instante, sin actor, con el `summary` fijo "Tu solicitud fue asignada para su atención". Las reasignaciones no generan hito.
3. **Cada rol ve una sola fila.** `/actividad` le muestra al Vecino solo el hito, con `actorName: "Municipalidad"` como los demás eventos hechos por staff. Al staff le muestra solo la fila `INTERNO`, que ya tiene el detalle. El hito se deriva de una regla fija (`previousAssigneeId` nulo), así que ocultarlo al staff no pierde información. El timeline de audit se arma con eventos, no con estas filas.
4. **`actor_id` nullable, solo para el hito.** Hoy `request_activity.actor_id` es `NOT NULL`, y el hito no se podría guardar. Pasa a nullable con:
   ```sql
   CONSTRAINT ck_request_activity_actor
     CHECK (actor_id IS NOT NULL OR (kind = 'ASIGNACION' AND visibility = 'PUBLICO'))
   ```
   Ninguna acción humana queda sin autor. El cambio va en un `ALTER` manual en `db/`, porque `ddl-auto: update` no relaja un `NOT NULL`, y en `@Check` en la entidad, para que H2 lo exija en los tests. `kind` y `visibility` ya se guardan con `@Enumerated(EnumType.STRING)`. `actor_name` ya es nullable. `actor_role` (EP3-31) nace nullable por la misma razón y por las filas históricas.
   El mismo script reemplaza el `CHECK` que Hibernate creó para `kind` con `CREADO`, `ESTADO` y `GESTION`: lo busca por `SEARCH_CONDITION_VC`, porque su nombre `SYS_C…` cambia en cada base, y lo recrea con `ASIGNACION`. Sin ese paso, la primera toma falla en Oracle con ORA-02290.
5. **Tiempo de asignación:** `tiempos` lo calcula con la primera fila `ASIGNACION` `INTERNO`, que es la que ve el staff.
6. **Orden del expediente (EP3-66):** `activity_sequence`, que Oracle asigna al insertar con `request_activity_seq` (`ORDER`), ordena `/actividad`, el resumen de contacto y la última gestión del filtro `contactDue`. Cada escritura toma antes el bloqueo de la fila del trámite (EP3-02, sección 2.3), así que una operación posterior recibe un valor mayor aunque su `occurredAt` empate o el reloj retroceda. `occurredAt` es la hora informativa. La columna no sale en la API ni en Kafka. En bases existentes la crea `db/activity-sequence.sql`, sin escrituras concurrentes: el historial previo se numera por `occurred_at` e `id`, y la garantía del orden real aplica a las actividades registradas después.

### 7. Evento `request.assigned`

Se registra en el outbox en la misma transacción (EP3-02), con el payload de EP3-01, sección 6:

| Campo | Toma o primera asignación | Reasignación |
|---|---|---|
| `assigneeId`, `assigneeName` | El nuevo responsable | El nuevo responsable |
| `previousAssigneeId` | `null` | El responsable anterior |
| `reason` | `null` | El motivo |

El actor del sobre es quien hizo la operación: el Funcionario que toma o reasigna, o el Admin que asigna. En una toma, el actor y el responsable son la misma persona. El evento es interno, y el hito público no genera un evento aparte.

### 8. Filtro de listado `assignee`

`GET /api/requests` acepta `assignee=me|none`, combinado con los demás filtros por un Y lógico (EP3-30):

| Valor | Resultado |
|---|---|
| `me` | Trámites cuyo `assignee_id` es el `oid` de quien llama. Para el Admin y el Auditor, vacío, porque nunca son responsables |
| `none` | Trámites sin responsable |
| Otro valor | 400 `assignee debe ser me o none` |

Solo para staff. El Vecino que lo usa recibe 403 `El filtro assignee es solo para staff`. Es el filtro que usan los bloques de `/inicio` (EP3-04, sección 7) y los filtros rápidos de la bandeja (EP3-47).

### 9. Cambios por capa

| Capa | Cambio | Issue |
|---|---|---|
| **requests**, alta | `folio_counter`, `FolioCounterService.ensureYear`, orquestador sin transacción, `Clock` inyectado y columna `folio`. Script de trámites existentes | EP3-28 |
| **requests**, asignación | Columnas `assignee_id` y `assignee_name` en `municipal_requests`, y las de la sección 6 en `request_activity`. `staff_member` con su interceptor, endpoints de la sección 3, filtro `assignee`, `ActivityKind.ASIGNACION`, `ALTER` de `actor_id` con `ck_request_activity_actor` | EP3-29 |
| **contratos** | EP2-01, sección 2: `folio` en el payload de RabbitMQ | EP3-05 |
| **requests**, outbox | `request.assigned` desde la asignación. `actor_role` nullable | EP3-31 |
| **BFF** | Proxy de `take`, `assignee` y `assignees`, con los pasos 1 a 3 de la sección 4 | EP3-45 |
| **frontend** | "Tomar", "Asignar" y "Reasignar" con el selector de `/assignees` y el motivo solo en la reasignación. Filtros "Mis asignados" y "Sin asignar" | EP3-46, EP3-47 |
| **Gateway** | Rutas de la sección 3, con `assignees` literal | EP3-55 |

### 10. Límites conocidos

1. **Funcionario que nunca llamó a requests** (por diseño): no aparece en la lista hasta su primer inicio de sesión. Mejora futura: sincronizar `staff_member` con las asignaciones de App Roles de Entra ID por Microsoft Graph.
2. **Funcionario que dejó la municipalidad** (por diseño): sigue en la lista hasta que su rol cambie y vuelva a llamar a requests, o hasta que la sincronización con Graph exista. Sus trámites los reasigna el Admin.
3. **Devolver a la bandeja** (por plazo): nadie puede soltar un trámite. Mejora futura: "devolver a la bandeja" con motivo, con un evento `request.unassigned` y una revisión del hito público.
4. **Tope de 999.999 trámites por año** (por diseño): una comuna no llega a esa cifra. Ampliarlo cambia el formato.
5. **Altas en fila** (por diseño): el bloqueo de `folio_counter` las procesa una tras otra.
