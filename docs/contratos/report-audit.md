<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: APIs de report y audit (EP3-07)

Define los endpoints de solo lectura de report (`/api/report/*`) y audit (`/api/audit/*`): KPIs, plazos, puntos del mapa, timeline y búsqueda de auditoría. Es la base de EP3-35 a EP3-38 y EP3-61 (report), EP3-39 a EP3-42 (audit), EP3-44 (BFF) y EP3-50 a EP3-53 y EP3-62 (frontend). Parte de los endpoints del caso base (`GET /api/report/kpis?range=last24h` y `GET /api/report/top-procedures?range=last7d`), de los roles de EP3-04 y de la proyección de EP3-06.

**Nombres:** los campos, parámetros y rutas van en inglés (convención 13 del backlog). Los valores de los enums de dominio van en español (`VENCIDO`, `EN_GESTION`).

### 1. Servicios y seguridad

| | report | audit |
|---|---|---|
| Puerto | 8086, con `expose` y sin `ports` | 8087, con `expose` y sin `ports` |
| Variable del BFF | `REPORT_BASE_URL=http://report:8086` | `AUDIT_BASE_URL=http://audit:8087` |
| Ruta pública | `/api/report/**`, por el Gateway (`/api/report/{proxy+}`, EP3-55) y el BFF | `/api/audit/**`, igual |

1. **Solo el BFF los llama**, con los timeouts de `CatalogClientConfig` (EP3-44). El BFF reenvía `X-User-Id` y `X-User-Roles`, nunca el JWT.
2. **Los servicios vuelven a comprobar el rol** (EP3-04, principio 2). `X-User-Roles` tiene que traer exactamente un rol, y ese rol tiene que estar permitido en el endpoint. Si no, 403 `No tienes el rol necesario para este recurso`, el mismo mensaje del BFF.
3. **Sin token interno.** EP3-43 manda `X-Internal-Token` solo a mq-admin y kafka-admin. report y audit, como catalog, confían en los headers del BFF, y los protege que no publican puerto. Es un límite conocido (sección 8).

**Roles por endpoint:**

| Endpoint | Roles |
|---|---|
| `GET /api/report/kpis` y `GET /api/report/top-procedures` | Admin, Auditor |
| `GET /api/report/sla` y `GET /api/report/sla/batch` | Funcionario, Admin, Auditor |
| `GET /api/report/map-points` | Funcionario, Admin, Auditor |
| `GET /api/audit/timeline` y `GET /api/audit/events` | Admin, Auditor |

Coincide con la tabla "Roles por endpoint de report y audit" de EP3-04, sección 2. El Vecino recibe 403 en todos: no ve el estado del plazo (EP3-04, sección 2) ni la auditoría.

### 2. Reglas comunes

#### 2.1 Paginación

Los endpoints paginados (`/api/report/sla`, `/api/audit/timeline` y `/api/audit/events`) usan los mismos parámetros y la misma forma de página que el listado de requests (EP3-30), así el frontend usa un solo componente:

| Parámetro | Regla |
|---|---|
| `page` | Entero desde 0. Por defecto 0 |
| `size` | Entero de 1 a 50. Por defecto 20 |

La respuesta lleva `content`, `page`, `size`, `totalElements` y `totalPages`. En report, además, `lastEventAt`.

#### 2.2 Parámetros de varios valores

`status` en `/api/report/sla` y `/api/report/map-points`, `requestIds` en `/api/report/sla/batch` y `eventType` en `/api/audit/events` aceptan varios valores **separados por coma**, sin espacios. Un valor desconocido o mal formado responde 400, y un valor repetido también.

#### 2.3 Errores

El cuerpo de error lleva `status`, `error`, `message` y `path`, igual que el BFF (`BffExceptionHandler`) y kafka-admin. Los mensajes van en español, sin tildes.

| Paso | Código | Caso |
|---|---|---|
| 1 | 403 | Rol no permitido, sin rol o con más de un rol |
| 2 | 400 | Parámetro inválido (sección 6) |

No hay 404 de negocio: una consulta sin resultados responde 200 con una lista vacía. El 401 lo responden el Gateway y el BFF, y el 503 por servicio caído, el BFF (EP3-44).

### 3. report

#### 3.1 Lecturas livianas (K8)

**Los KPIs son consultas agregadas indexadas sobre la proyección materializada de EP3-06, y ninguna petición reprocesa eventos.** La proyección por trámite es lo que está materializado: cada evento se aplica una sola vez, al consumirlo (EP3-36), y las consultas solo la leen.

Se eligió así, y no con contadores, por tres razones:
- **no hay filas compartidas** entre los hilos del listener, así que no hay riesgo de deadlock (EP3-06, sección 5.3);
- **no hay doble conteo:** un contador sumaría dos veces un duplicado que llegue después de los 30 días de `processed_events` (EP3-02, límite 5), y una proyección es idempotente por trámite;
- **calza con la proyección parcial:** todas las consultas cuentan solo proyecciones con `createdAt`, así que quedan fuera las que EP3-06, sección 6.1, ya excluye.

La proyección necesita índices sobre `created_at`, `closed_at`, el estado del trámite, `sla_status`, `due_date`, `assignee_id` y `last_event_at`. Los fija EP3-36.

#### 3.2 `lastEventAt`

Es el `occurredAt` más reciente que report aplicó. Cada proyección guarda su `last_event_at`, el `occurredAt` del último evento aplicado a ese trámite, y la respuesta usa `MAX(last_event_at)` sobre todas las proyecciones, incluidas las parciales. Va `null` si todavía no llegó ningún evento. No se usa una fila compartida, por la misma razón de la sección 3.1.

Va en todas las respuestas de report (K8). El frontend lo muestra como "datos al" (EP3-50).

#### 3.3 Ventanas de tiempo (`range`)

| `range` | Ventana | Tramos de `requestsOverTime` |
|---|---|---|
| `last24h` | Desde el inicio de la hora de hace 23 horas hasta ahora | 24 tramos de 1 hora. Se alinean a la hora UTC: el desfase de Chile es de horas enteras, así que coinciden con la hora local |
| `last7d` | Desde el inicio del día, en `America/Santiago`, de hace 6 días hasta ahora | 7 tramos de 1 día en `America/Santiago` |

El tramo actual va incompleto. Cualquier otro valor de `range` responde 400. El valor por defecto es `last24h` en `kpis` y `last7d` en `top-procedures`, como en el caso base.

#### 3.4 `GET /api/report/kpis?range=last24h|last7d`

| Campo | Cálculo |
|---|---|
| `range` | El valor usado |
| `requestsOverTime` | `{ bucket, points }`. `bucket` es `HOUR` o `DAY`. `points` es la lista de tramos, cada uno con `bucketStart` (instante UTC) y `count` (altas con `createdAt` en el tramo). Van todos los tramos, también los que tienen 0 |
| `activeByStatus` | Trámites abiertos por estado, con los cuatro estados abiertos siempre presentes (`INGRESADO`, `ADMITIDO`, `EN_GESTION`, `EN_TERRENO`), en 0 si no hay. Es una foto del momento y **no depende de `range`** |
| `averageResolutionHours` | Promedio de `closedAt − createdAt`, en horas con un decimal, de los trámites **resueltos** (`RESUELTO`) con `closedAt` en la ventana. Un rechazo no es una resolución. `null` si no hubo ninguno |
| `resolvedCount` | Cuántos trámites entraron en ese promedio |
| `slaCompliance` | `{ rate, onTime, late }`. `onTime` y `late` cuentan los trámites con `closedAt` en la ventana y `slaStatus` `CUMPLIDO` o `FUERA_DE_PLAZO`. `rate` es `onTime / (onTime + late)`, con 4 decimales, o `null` si el denominador es 0. Los trámites `SIN_PLAZO` y `NO_APLICA` no cuentan (EP3-06, secciones 2.3 y 6.2) |
| `lastEventAt` | Sección 3.2 |

```json
{
  "range": "last24h",
  "requestsOverTime": {
    "bucket": "HOUR",
    "points": [
      { "bucketStart": "2026-11-09T15:00:00Z", "count": 3 },
      { "bucketStart": "2026-11-09T16:00:00Z", "count": 0 }
    ]
  },
  "activeByStatus": { "INGRESADO": 12, "ADMITIDO": 7, "EN_GESTION": 5, "EN_TERRENO": 2 },
  "averageResolutionHours": 31.5,
  "resolvedCount": 8,
  "slaCompliance": { "rate": 0.8750, "onTime": 7, "late": 1 },
  "lastEventAt": "2026-11-10T14:58:12.004Z"
}
```

El ejemplo muestra 2 de los 24 tramos.

#### 3.5 `GET /api/report/top-procedures?range=last24h|last7d&limit=5`

Altas por tipo de trámite en la ventana. `limit` va de 1 a 20, con 5 por defecto.

1. **Se agrupa por `procedureType`.** El label es un snapshot de cada alta (EP3-01), y si el Admin renombró el tipo, los trámites tienen labels distintos. Se devuelve el `procedureLabel` del **alta más reciente dentro de la ventana**. Si varias altas del tipo comparten ese instante, gana el label mayor por code point de Unicode.
2. **La consulta es portable entre Oracle y H2.** La forma natural en Oracle, `MAX(...) KEEP (DENSE_RANK LAST ORDER BY created_at)`, no existe en H2, y los tests tienen que probar la misma lógica que corre en Oracle (el principio de EP3-05, sección 1.3). Se usa una subconsulta sobre el `created_at` máximo por tipo, o dos consultas.
3. **Orden:** por `count` descendente, y después por `procedureType` por code point. El orden, el `limit` y el desempate del label se resuelven en el servicio, sobre el conteo agrupado de la base: en Oracle, `ORDER BY` y `MAX` sobre texto dependen de `NLS_SORT` y `NLS_COMP`, y el driver toma `NLS_SORT` del locale, así que no coincidirían con H2.

```json
{
  "range": "last7d",
  "items": [
    { "procedureType": "bache", "procedureLabel": "Bache en calle", "count": 41 },
    { "procedureType": "alumbrado", "procedureLabel": "Alumbrado publico", "count": 27 }
  ],
  "lastEventAt": "2026-11-10T14:58:12.004Z"
}
```

#### 3.6 `GET /api/report/sla`: listado de plazos

`GET /api/report/sla?status=VENCIDO,POR_VENCER&assignee=me|none&page=0&size=20`

| Parámetro | Regla |
|---|---|
| `status` | `VENCIDO`, `POR_VENCER` o los dos. Por defecto, los dos. Los demás `slaStatus` no son alertas y responden 400 |
| `assignee` | Opcional. `me` usa el `X-User-Id` que reenvía el BFF: para el Admin y el Auditor devuelve una lista vacía, porque nunca son responsables (EP3-05, sección 8), y también sin `X-User-Id`: nunca se convierte en un listado sin filtro. `none` devuelve los trámites sin responsable. Otro valor, 400 |
| `page`, `size` | Sección 2.1 |

Solo considera trámites abiertos con `slaStatus` en los valores pedidos, que por construcción tienen `dueDate` (EP3-06, sección 5.1).

**Ítem:** `requestId`, `folio`, `procedureType`, `procedureLabel`, `assigneeId`, `assigneeName`, `dueDate` y `slaStatus`. El nombre del responsable viene de `request.assigned` (EP3-01). El folio basta para enlazar al detalle.

**Orden:** por `dueDate` ascendente y después por `folio`. Con los dos estados, los vencidos quedan primero, porque su `dueDate` ya pasó.

Cubre los bloques de `/inicio` de EP3-04, sección 7: el Funcionario usa `assignee=me` con los dos estados, y el Admin usa `status=VENCIDO` sin `assignee`, para toda la comuna.

#### 3.7 `GET /api/report/sla/batch`: plazos por lote

`GET /api/report/sla/batch?requestIds=<uuid>,<uuid>,...`

1. **Entrada:** de 1 a 50 UUID, sin repetir. Un UUID en mayúsculas se normaliza a minúsculas, como lo guarda requests, y cuenta como repetido de su par. 50 es el `size` máximo del listado de requests (EP3-30), así una página completa entra en una sola consulta. Con 50 UUID, la URL tiene menos de 2 KB.
2. **Salida:** un ítem por cada `requestId` pedido, en el mismo orden, con `requestId`, `slaStatus` y `dueDate`, más `lastEventAt`.
3. **Un trámite que report no tiene, o que tiene solo como proyección parcial,** responde con `slaStatus: null` y `dueDate: null`, no con 404. Quien consulta es staff, que ve todos los trámites, así que no se revela nada.

```json
{
  "items": [
    { "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc", "slaStatus": "POR_VENCER", "dueDate": "2026-11-11" },
    { "requestId": "1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f", "slaStatus": "SIN_PLAZO", "dueDate": null },
    { "requestId": "9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a", "slaStatus": null, "dueDate": null }
  ],
  "lastEventAt": "2026-11-10T14:58:12.004Z"
}
```

#### 3.8 `GET /api/report/map-points`: puntos del mapa

`GET /api/report/map-points?range=last24h|last7d&status=<estados>&procedureType=<codigo>`

Alimenta el mapa de trámites de EP3-62.

| Parámetro | Regla |
|---|---|
| `range` | Sección 3.3, con `last7d` por defecto. Filtra por `createdAt` |
| `status` | Opcional. Uno o varios de los siete estados del trámite, sobre el estado actual. Sin él, todos |
| `procedureType` | Opcional. Un código con el formato del catálogo: de 1 a 40 caracteres entre minúsculas, dígitos, `_` y `-`. Un código bien formado que no existe responde 200 con todo en cero |

Los filtros se combinan con un Y lógico y solo consideran proyecciones con `createdAt` (sección 3.1).

1. **Ubicación utilizable:** un trámite la tiene si trae `latitude` y `longitude`. Si le falta cualquiera de las dos, cuenta como sin ubicación. EP3-01 ya exige que viajen juntas, y esta regla impide que una fila incompleta llegue al mapa.
2. **`items`:** como máximo **1000** trámites con ubicación, del alta más reciente a la más antigua, y después por `requestId`. Cada ítem lleva `requestId`, `folio`, `latitude`, `longitude`, `status`, `procedureType`, `procedureLabel` y `sector`. No incluye el responsable, la dirección ni datos del vecino (EP3-01, sección 8). Un mapa necesita todos sus puntos en una sola respuesta, así que no se pagina, y el tope acota el tamaño de la respuesta y la cantidad de marcadores de Leaflet.
3. **`locatedTotal`:** cuántos trámites con ubicación cumplen los filtros, sin tope. Si supera el largo de `items`, hubo recorte, y el frontend lo informa.
4. **`withoutLocation`:** cuántos trámites cumplen los filtros sin ubicación utilizable.
5. **`bySector`:** concentración por sector, con ítems `{ sector, count }`, calculada sobre **todos** los trámites que cumplen los filtros: con ubicación y sin ella, incluidos los que el tope dejó fuera de `items`. La suma de los `count` es `locatedTotal + withoutLocation`. Los trámites sin sector forman un ítem con `sector: null`. Orden: por `count` descendente y después por `sector` por code point. El ítem `null` va siempre al final, aunque tenga el `count` más alto. Se ordena en el servicio, por la misma razón de la sección 3.5.
6. **Una sola foto:** las consultas de una respuesta corren en una transacción de solo lectura con aislamiento serializable. Un evento que llega entremedio no descuadra `items`, los totales ni `bySector`.
7. **Roles:** Funcionario, Admin y Auditor. El Funcionario ya ve todos los trámites (EP3-04, sección 2). El mapa le sirve para organizar el trabajo en terreno y no le muestra indicadores de gestión.

```json
{
  "range": "last7d",
  "items": [
    {
      "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
      "folio": "BD-2026-000123",
      "latitude": -37.9946,
      "longitude": -71.4962,
      "status": "EN_GESTION",
      "procedureType": "bache",
      "procedureLabel": "Bache en calle",
      "sector": "Centro"
    }
  ],
  "locatedTotal": 1,
  "withoutLocation": 2,
  "bySector": [
    { "sector": "Centro", "count": 2 },
    { "sector": null, "count": 1 }
  ],
  "lastEventAt": "2026-11-10T14:58:12.004Z"
}
```

### 4. El plazo en el listado y el detalle

**El frontend combina las dos fuentes**, no el BFF:
1. pide la página a requests (`GET /api/requests`, EP3-30);
2. con los `requestId` de esa página, pide `GET /api/report/sla/batch` y pinta la columna de plazo. El detalle usa el mismo endpoint con un solo `requestId`.

**Por qué el frontend:**
- **Falla por separado** (EP3-04, sección 7): si report está caído, el listado se muestra igual y solo la columna de plazo queda sin datos. Si combinara el BFF, una caída o una demora de report afectaría a todo el listado, y los timeouts se sumarían.
- **El BFF sigue siendo un proxy**, como en el resto de sus rutas.
- **El listado no se filtra por plazo.** "Vencidos" y "por vencer" salen del listado de plazos (sección 3.6), así que no hay que paginar cruzando dos servicios.

La columna solo se muestra al staff. El Vecino ve el plazo en días desde `RequestView` (EP3-06, sección 7).

**Las tres situaciones de la columna:**

| Caso | Respuesta | Pantalla |
|---|---|---|
| Sin plazo | `slaStatus: "SIN_PLAZO"` | "Sin plazo", texto neutro (EP3-06, sección 6.2) |
| Proyección parcial o trámite que report no conoce | `slaStatus: null` | "—", con tooltip y `aria-label` "Sin información de plazo" |
| report caído o con timeout | Error en la consulta por lote | "No disponible" en la columna. El resto del listado funciona |

Los demás valores se muestran con su texto de EP3-06, sección 4.1.

### 5. audit

#### 5.1 Normalización de los eventos

audit guarda los eventos de los dos tópicos en una sola tabla (EP3-40 y EP3-41). A los de `requests.events`, que no traen `resourceType` (EP3-01, sección 7, lo define solo para `audit.timeline`), audit les asigna valores **al guardarlos**:

| Campo | Eventos de `requests.events` | Eventos de `audit.timeline` |
|---|---|---|
| `resourceType` | `request` | El del evento |
| `resourceId` | `requestId` | El del evento |
| `requestId`, `folio` | Los del payload | `null` |
| `sequence` | El del sobre | `null` |
| `producer` | `requests` | El del evento |
| `actor.sourceIp` | `null`: `requests.events` no la trae (EP3-01, sección 9) | La del evento |

Ningún evento de Kafka trae `resourceType = request`: es una normalización interna de audit.

El `summary` lo arma audit al guardar el evento, en español, para mostrarlo en pantalla. Por ejemplo: "Cambio de estado de ADMITIDO a RECHAZADO" o "Edición del tipo de trámite bache". El correo, la dirección y la nota de las gestiones nunca llegan a audit, porque no viajan en Kafka (EP3-01, sección 8).

#### 5.2 Ítem

| Campo | Contenido |
|---|---|
| `eventId`, `eventType`, `occurredAt`, `producer` | Los del sobre |
| `actor` | `id`, `name`, `role` y `sourceIp` (sección 5.1) |
| `resourceType`, `resourceId`, `requestId`, `folio`, `sequence` | Sección 5.1 |
| `summary` | Sección 5.1 |
| `details` | En un evento de `audit.timeline`, `before` y `after` (EP3-51). En un evento de trámite, los campos de su payload (EP3-01, sección 6), incluido `interventionReason` |

`interventionReason` aparece porque los dos roles de audit lo pueden ver (EP3-04, sección 6.3). Es lo que muestra el bloque del Auditor en `/inicio`.

#### 5.3 `GET /api/audit/timeline`: timeline de un trámite

`GET /api/audit/timeline?requestId=<uuid>` o `?folio=BD-AAAA-NNNNNN`, con `page` y `size`.

1. **Exactamente uno de los dos.** Los dos juntos, o ninguno, responden 400. El folio lo pide EP3-51 ("consultable por folio o desde el detalle").
2. **Orden:** `occurredAt` ascendente, después `sequence` y después `eventId`.
3. **Sin eventos:** 200 con una lista vacía, no 404. audit no puede saber si el trámite existe o si es anterior a EP3-31 (EP3-06, sección 6.1).
4. **Paginado** con las reglas de la sección 2.1, para que un trámite con muchas gestiones no devuelva una respuesta sin tope. Esta regla no estaba en las decisiones previas y se agrega aquí.

Solo incluye eventos de `requests.events`: los de `audit.timeline` no tienen `requestId`.

#### 5.4 `GET /api/audit/events`: búsqueda

Ordenada por `occurredAt` descendente, y después por `eventId`. Todos los filtros son opcionales y se combinan con un Y lógico:

| Filtro | Regla |
|---|---|
| `actorId` | Exacto |
| `actorRole` | `Admin`, `Funcionario`, `Vecino` o `Auditor` (EP3-01, sección 5) |
| `resourceType` | `request`, o uno de EP3-01, sección 7: `procedure-type`, `queue`, `exchange`, `binding`, `topic`, `consumer-group` |
| `eventType` | Uno o varios de los tipos de EP3-01, secciones 6 y 7, separados por coma |
| `requestId` | UUID exacto |
| `from`, `to` | Instantes ISO-8601. `from` no puede ser posterior a `to` |
| `page`, `size` | Sección 2.1 |

Un valor fuera de esas listas responde 400, así el frontend puede usar listas desplegables sin texto libre.

**Las intervenciones del Admin** (bloque del Auditor en `/inicio`, EP3-04, sección 7) se consultan con `actorRole=Admin&eventType=request.status-changed,request.contact-logged&from=<hace 7 días>`. Toda operación del Admin sobre un trámite es una intervención (EP3-04, sección 3), salvo la asignación, que es su función normal. Filtrar solo por `actorRole=Admin` traería también sus operaciones administrativas (catálogo, RabbitMQ y Kafka) y sus asignaciones. Agregar `resourceType=request` deja fuera las operaciones administrativas, pero no las asignaciones (`request.assigned`). Por eso `eventType` acepta varios valores.

### 6. Mensajes de error

| Caso | `message` |
|---|---|
| Rol no permitido, sin rol o con más de uno | `No tienes el rol necesario para este recurso` |
| `range` inválido | `range debe ser last24h o last7d` |
| `limit` fuera de rango | `limit debe estar entre 1 y 20` |
| `status` inválido | `status solo acepta VENCIDO y POR_VENCER` |
| `assignee` inválido | `assignee debe ser me o none` |
| `page` negativo | `page debe ser 0 o mayor` |
| `size` fuera de rango | `size debe estar entre 1 y 50` |
| `requestIds` vacío, con más de 50, repetidos o con un valor que no es UUID | `requestIds debe tener entre 1 y 50 UUID sin repetir` |
| `requestId` que no es UUID | `requestId no es un UUID valido` |
| `folio` con otro formato | `folio debe tener el formato BD-AAAA-NNNNNN` |
| `requestId` y `folio` juntos, o ninguno | `Indica requestId o folio, solo uno` |
| `actorRole`, `resourceType` o `eventType` desconocido | `<filtro> no es valido`, por ejemplo `eventType no es valido` |
| `status` o `procedureType` no válido en `/api/report/map-points` | `status no es valido` o `procedureType no es valido` |
| `from` o `to` mal formado | `from y to deben ser instantes ISO-8601` |
| `from` posterior a `to` | `from no puede ser posterior a to` |
| Valor repetido en un parámetro de varios valores | `<parametro> tiene valores repetidos` |

### 7. Cambios por capa

| Capa | Cambio | Issue |
|---|---|---|
| **report**, base | Puerto 8086 | EP3-35 |
| **report**, consumidor | Proyección por trámite con `last_event_at` y los índices de la sección 3.1, sin contadores | EP3-36 |
| **report**, KPIs | `kpis` y `top-procedures` (secciones 3.3 a 3.5), con la consulta portable del label, la comprobación del rol y el cuerpo de error de la sección 2.3 | EP3-37 |
| **report**, plazos | Listado y consulta por lote (secciones 3.6 y 3.7), con la misma comprobación del rol y el mismo cuerpo de error | EP3-38 |
| **report**, mapa | Puntos, totales y concentración por sector (sección 3.8), con la misma comprobación del rol y el mismo cuerpo de error | EP3-61 |
| **audit**, base | Puerto 8087 | EP3-39 |
| **audit**, consumidores | Normalización de la sección 5.1, `sequence` y `summary` | EP3-40, EP3-41 |
| **audit**, API | Timeline y búsqueda (secciones 5.3 y 5.4), con la comprobación del rol y el cuerpo de error | EP3-42 |
| **BFF** | Proxy de `/api/report/**` y `/api/audit/**` con los roles de la sección 1, `REPORT_BASE_URL` y `AUDIT_BASE_URL`, y 503 si el servicio no responde | EP3-44 |
| **BFF** | Autorización y reenvío de `GET /api/report/map-points` | EP3-61 |
| **frontend** | Columna de plazo en el listado y el detalle, con la consulta por lote y sus tres situaciones (sección 4) | EP3-53 |
| **frontend** | Reportería con `kpis` y `top-procedures`, y "datos al" con `lastEventAt` | EP3-50 |
| **frontend** | Auditoría con la búsqueda y el timeline por folio | EP3-51 |
| **frontend** | Bloques de `/inicio` con el listado de plazos y la búsqueda de intervenciones | EP3-52 |
| **frontend** | Mapa de trámites en `/reportes`, con los totales, el aviso de recorte y la concentración por sector de la sección 3.8. El Funcionario entra solo al mapa | EP3-62 |

**Cambios en otros contratos:**

| Contrato | Cambio |
|---|---|
| EP3-04, sección 4 | El filtro de intervenciones nombra también los `eventType` de la sección 5.4 |
| EP3-04, sección 7 | El bloque del Auditor usa `actorRole=Admin` con esos `eventType` |
| EP3-06, sección 5.3 | Corrección de formato (doble acento grave), sin cambio de contenido |

**Tests que pide este contrato**, además de los de cada ficha:
- KPIs sin proyecciones parciales, con tramos en 0 y con `slaCompliance` en `null`;
- label de `top-procedures` después de renombrar un tipo, en H2;
- listado de plazos con los dos estados y con `assignee=me` para el Admin (lista vacía);
- consulta por lote con un trámite desconocido (`null`, no 404) y con 51 ids (400);
- timeline con empate de `occurredAt` desempatado por `sequence`;
- búsqueda de intervenciones del Admin, sin sus asignaciones;
- 403 por rol en cada endpoint, incluido el Vecino.

### 8. Límites conocidos

1. **Sin token interno en report y audit** (por plazo): confían en los headers del BFF, como catalog, y los protege que no publican puerto. audit expone IPs y motivos internos, así que es el primero al que conviene extenderlo. Mejora futura: enviar `X-Internal-Token` también a report y audit, como en EP3-43.
2. **KPIs por funcionario** (por plazo): no se calculan. EP3-04 los menciona como consecuencia de que el Admin no tome trámites, pero ninguna ficha los pide.
3. **Trámites anteriores a EP3-31** (heredado de EP3-06, límite 1): no aparecen en los KPIs ni en los plazos, y su timeline en audit empieza en el despliegue.
4. **Ventanas fijas:** solo `last24h` y `last7d`, que son las que usa la pantalla (EP3-50). Una ventana configurable queda como mejora futura.
