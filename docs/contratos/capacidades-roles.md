<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: capacidades por rol (EP3-04)

Define qué puede hacer cada rol en cada pantalla y en cada endpoint, quién opera un trámite y qué datos ve cada uno. Es la base de EP3-05 (folio y asignación), EP3-29 (asignación en requests), EP3-45 (BFF), EP3-46, EP3-49 y EP3-52 (frontend).

Los roles son los App Roles de Entra ID: `Admin`, `Funcionario`, `Vecino` y `Auditor` (sección "Roles y usuarios de prueba").

### 1. Principios

1. **El backend decide.** El frontend oculta lo que un rol no puede hacer, pero la regla vive en el servidor. Una acción que la interfaz no ofrece igual responde 403 si se llama a mano.
2. **Dos capas.** El BFF aplica la matriz de la sección 2, y cada servicio de dominio vuelve a comprobar los roles de sus propios endpoints. requests no confía solo en el filtro del BFF.
3. **Sin rol, sin acceso.** Un token válido sin ninguno de los cuatro roles responde 403 `No tienes un rol asignado en BarrioDigital` en toda la API, salvo los health. Antes de EP3-04, ese usuario se comportaba como Vecino y podía crear trámites. En el perfil `dev` del BFF, `resolveRoles(null)` sigue devolviendo `Vecino`, solo para desarrollo.

### 2. Matriz de capacidades

| Acción | Vecino | Funcionario | Admin | Auditor |
|---|---|---|---|---|
| Crear trámite | Sí | No | No | No |
| Adjuntar imagen en el alta | Sí | No | No | No |
| Adjuntar después del alta | No | No | No | No |
| Ver sus propios trámites | Sí | No aplica | No aplica | No aplica |
| Ver todos los trámites | No | Sí | Sí | Sí |
| Ver el detalle | Solo los propios (404 en los ajenos) | Sí | Sí | Sí |
| Ver la imagen adjunta | Solo los propios | Sí | Sí | Sí |
| Historial | Público (sección 6) | Completo | Completo | Completo |
| Registrar gestión | No | Solo como responsable | Sí, con motivo | No |
| Calificar el propio trámite `RESUELTO` | Sí (titular, una vez) | No | No | No |
| Preferencias de aviso por correo | Sí (las propias) | Sí (las propias) | Sí (las propias) | Sí (las propias) |
| Cancelar el propio trámite en `INGRESADO` | Sí (titular) | No | No | No |
| Exportar el listado a CSV (EP3-63) | Solo los propios | Sí | Sí | Sí, sin correo del solicitante |
| Cambiar estado y rechazar con motivo | No | Solo como responsable | Sí, con motivo | No |
| Tomar un trámite sin responsable | No | Sí | No | No |
| Asignar o reasignar | No | Solo los suyos (EP3-05) | Cualquiera | No |
| Ver la lista de funcionarios para reasignar | No | Sí | Sí | No |
| Ver el responsable | Solo si tiene, sin nombre | Sí | Sí | Sí |
| Ver el estado del plazo (listado, detalle e `/inicio`) | No | Sí | Sí | Sí |
| Administrar catálogo, cupos y plazos | No | No | Sí | No |
| Administrar la mensajería (RabbitMQ y Kafka) | No | No | Sí | No |
| Ver reportes (`/reportes`) | No | Solo el mapa de trámites | Sí | Sí, solo lectura |
| Ver auditoría (`/auditoria`) | No | No | Sí | Sí |

Reglas que acompañan la matriz:

1. **El Admin no toma trámites, los asigna.** Así "Mis asignados" y los KPIs por funcionario reflejan atención y no supervisión, y la lista de reasignación de EP3-05 queda sin ambigüedad. El destinatario de una asignación tiene que ser un Funcionario de esa lista, y EP3-05 define el error. El Admin igual puede operar cualquier trámite como intervención (sección 3).
2. **El Auditor no tiene acciones.** Quien fiscaliza no opera.
3. **Los indicadores de `/reportes` son para el Admin y el Auditor.** Control interno revisa los indicadores de gestión. El Funcionario entra a `/reportes` solo para el mapa de trámites (EP3-62), que le sirve para organizar el trabajo en terreno. Su vista principal sigue siendo la bandeja, y recibe los plazos de report en el listado, el detalle e `/inicio`.
4. **Adjuntar después del alta:** nadie, en la prioridad Alta. Si entra EP3-64 (prioridad Media), el Vecino agrega fotos a un trámite abierto y ese contrato agrega su fila.
5. **Funciones de prioridad Media y Baja** (comentario del vecino, cancelación, encuesta, exportación) agregan su fila en su propio contrato, si se cumple la fecha de corte del 17-nov.
6. **Solo el Vecino crea.** requests también lo comprueba (principio 2): el staff que crea un trámite recibe 403 `Solo un Vecino puede crear un tramite`.

**Rutas del frontend:**

| Ruta | Roles |
|---|---|
| `/inicio` | Los cuatro roles |
| `/tramites` y `/tramites/:id` | Los cuatro roles |
| `/administracion` | Admin |
| `/reportes` | Admin y Auditor. El Funcionario, solo el mapa de trámites |
| `/auditoria` | Admin, Auditor |
| `/sin-acceso` (pantalla "sin acceso") | Sin rol, con más de un rol o con el token sin leer, con el motivo. Fuera del layout y sin navegación. Un rol válido que entra vuelve a `/inicio` |
| `/legal/privacidad`, `/legal/accesibilidad` y `/legal/condiciones-de-uso` | Públicas, con o sin sesión. El pie de todas las pantallas las enlaza |

Las rutas anteriores en inglés (`/admin`, `/reports`, `/reports/map`, `/audit` y `/no-access`) redirigen a las nuevas.

**Roles por endpoint de report y audit** (EP3-07):

| Endpoint | Roles |
|---|---|
| KPIs y tipos más demandados | Admin, Auditor |
| Plazos (vencidos y por vencer), con filtro `assignee=me` | Funcionario, Admin, Auditor |
| Puntos del mapa de trámites | Funcionario, Admin, Auditor |
| Timeline de un trámite y búsqueda de eventos de auditoría, con filtro `actorRole` | Admin, Auditor |

### 3. Responsable y operación

Un trámite tiene a lo más un responsable (EP3-05). Operar es cambiar el estado, rechazar o registrar una gestión.

1. **Funcionario:** solo opera los trámites de los que es responsable. Un trámite sin responsable hay que tomarlo antes de operarlo. Un Funcionario que no es el responsable, o un trámite sin responsable, responde 403 `Solo el responsable del tramite puede operarlo`. Leer sigue permitido.
2. **Admin:** opera cualquier trámite. Como nunca es responsable, toda operación suya es una **intervención**, y exige `interventionReason`:
   - campo de hasta 500 caracteres en `PUT /api/requests/{id}/status` y `POST /api/requests/{id}/gestiones`;
   - si falta, 400 `interventionReason es obligatorio para el Admin`;
   - se guarda en la columna `intervention_reason` de `request_activity`, y viaja como `interventionReason` en `request.status-changed` y `request.contact-logged` (EP3-01, sección 6);
   - es **interno** (sección 6), distinto de `rejectionReason`, que se le comunica al Vecino. Si el Admin rechaza, los dos son obligatorios.
3. **Asignar y reasignar no son intervenciones.** Son la función normal del Admin. El motivo de la reasignación lo define EP3-05.
4. **Dónde se aplica:**
   - **requests**, de forma autoritativa, **dentro de la misma transacción y del mismo bloqueo `PESSIMISTIC_WRITE`** que el cambio (`findByIdForUpdate`). Si se leyera antes del bloqueo, una reasignación simultánea podría dejar pasar un cambio del responsable anterior (EP3-02, sección 2.3).
   - **BFF**, como optimización antes de reservar el cupo en la admisión (sección 5).
5. **"Tomar" es la acción principal** en el detalle y el listado de un trámite sin responsable (EP3-46). Un Funcionario tampoco puede rechazar un trámite inválido (spam, duplicado) sin tomarlo: así queda registrado quién lo descartó.

### 4. Un rol por usuario

Cada usuario tiene **exactamente uno** de los cuatro roles. Un token con más de uno responde 403 `El usuario debe tener un solo rol` en toda la API, salvo los health, y el frontend muestra la pantalla "sin acceso" con el motivo.

**Por qué:** en una municipalidad real, vecinos y funcionarios son identidades distintas. El vecino entraría con una identidad ciudadana, como ClaveÚnica, y el funcionario con su cuenta corporativa, así que nadie tendría los dos roles en el mismo token. En BarrioDigital todos los usuarios, vecinos incluidos, inician sesión con Entra ID en un solo tenant, como exige el caso base, y esta regla evita que ese detalle de infraestructura genere combinaciones que el dominio no tiene. Además deja la segregación de funciones resuelta por construcción: el Auditor nunca tiene un rol operativo.

La regla es autoritativa en el **BFF**, la única puerta pública, y en **requests**, que tiene las acciones operativas. Los demás servicios quedan cubiertos por el BFF y por el token interno (EP3-43), porque no publican puerto y sus endpoints son de solo Admin o de lectura. En requests, `/api/requests/meta/**` queda fuera de la regla: el BFF la llama sin identidad y solo entrega datos fijos.

`actor.role` guarda ese único rol, en `request_activity.actor_role` (EP3-31) y en el evento (EP3-01, sección 4). Así el Auditor puede filtrar las intervenciones con `actorRole=Admin`, junto con los tipos de evento que son intervenciones (EP3-07, sección 5.4).

### 5. Orden de los errores

Para cambiar el estado y registrar una gestión, el BFF y requests responden en este orden. Tomar y reasignar siguen el mismo esquema, con su propia tabla en EP3-05.

| Paso | Código | Caso | `code` de requests en el cambio de estado (EP3-67) |
|---|---|---|---|
| 1 | 401 | Sin token | Lo responde el BFF |
| 2 | 403 | Sin rol, con más de un rol, o un rol que no opera (Vecino, Auditor) | `ROLE_REQUIRED`, `SINGLE_ROLE_REQUIRED`, `STATUS_CHANGE_FORBIDDEN` |
| 3 | 400 | Body inválido (`status`, `rejectionReason`, tamaños, `nextAttemptAt` no futura según EP3-10) e `interventionReason` ausente cuando quien llama es Admin | `STATUS_REQUIRED`, `STATUS_INVALID`, `CANCEL_REQUIRES_CANCEL_ENDPOINT`, `REJECTION_REASON_REQUIRED`, `INTERVENTION_REASON_REQUIRED`, `REQUEST_BODY_INVALID` (tamaños por `@Size` y JSON ilegible), `USER_ID_REQUIRED` |
| 4 | 404 | El trámite no existe, o es ajeno para el Vecino | `REQUEST_NOT_FOUND` |
| 5 | 403 | Funcionario que no es el responsable, o trámite sin responsable | `NOT_ASSIGNEE` |
| 6 | 409 | Transición no permitida, cupo agotado, o gestión en un trámite cerrado (EP3-10) | `STATUS_TRANSITION_NOT_ALLOWED`; el cupo agotado es `QUOTA_EXHAUSTED` del BFF |

Mantiene el orden del resto del proyecto (403, 400, 404, 409; EP2-04 y EP3-03), que es además el que impone Spring con `@Valid`. El paso 5 necesita el trámite, y en requests se evalúa dentro del bloqueo.

`code` va junto a `message`, que no cambia, y los consumidores comparan `code`. La tabla completa, con los mensajes, está en el README de requests.

Un Vecino que intenta operar un trámite ajeno recibe 403 en el paso 2, antes de cualquier 404: operar ya está prohibido por rol.

**Admisión y cupo.** Para pasar a `ADMITIDO`, el BFF reserva el cupo antes de llamar a requests (EP1.5-03). Para no consumir cupo en una operación que va a fallar:

1. **El 400 del Admin sin `interventionReason`** lo responde el BFF antes del `GET`, porque depende solo del rol y del body.
2. **El 403 de no responsable** lo responde el BFF con el `GET /api/requests/{id}` que ya hace, antes de tocar catalog.
3. **`recognizedRejection` suma dos mensajes**, como red de seguridad: `Solo el responsable del tramite puede operarlo` (el caso real es una reasignación entre el `GET` y el `PUT`) e `interventionReason es obligatorio para el Admin`. Con ellos el BFF libera el cupo. requests ya responde `code` (EP3-67); el BFF compara por texto hasta que EP3-69 use `code`.
4. **Un body rechazado por `@Valid` también es un rechazo reconocido.** Un `rejectionReason` o `interventionReason` de más de 500 caracteres lo rechaza el `@Size` del DTO antes que el servicio, con `REQUEST_BODY_INVALID` y el mensaje de Spring, y requests no guarda nada. Comparando textos, el BFF no lo reconoce: responde `ADMISSION_RESULT_UNCONFIRMED` y no libera el cupo. Al reconocer el código (EP3-69), el BFF libera el cupo.

### 6. Datos por rol

#### 6.1 Proyección por rol

requests deja de serializar la entidad `MunicipalRequest` y responde con `RequestView`, armado según el rol de quien llama. `RequestView` **conserva los nombres de campo del JSON actual** y agrega `hasAssignee`, así que el BFF y el frontend no cambian por la proyección. EP3-05 suma `folio` y EP3-06 suma `slaBusinessDays`.

| Campo | Vecino (sus trámites) | Funcionario y Admin | Auditor |
|---|---|---|---|
| Descripción, dirección, ubicación, imagen y nombre del solicitante | Sí | Sí | Sí |
| `solicitanteId` | Sí | Sí | Sí, para correlacionar actores sin el correo |
| `solicitanteEmail` | Sí | Sí | `null` |
| `hasAssignee` | Sí | Sí | Sí |
| `assigneeId` y `assigneeName` | `null` | Sí | Sí |
| `folio` (EP3-05) | Sí | Sí | Sí |
| `slaBusinessDays` (EP3-06) | Sí | Sí | Sí |

**El Auditor sin correo del solicitante:** fiscaliza quién hizo qué y con qué fundamento, y no contacta vecinos. Ocultar el correo aplica la proporcionalidad de la Ley 21.719, igual que EP3-01, sección 8. Se devuelve `null` en vez de enmascararlo, para no dejar datos parciales.

**El Vecino no ve nombres de funcionarios.** Interactúa con la municipalidad, no con una persona, como en FixMyStreet y en las OIRS. Así se protege al funcionario de presiones o contacto directo. Ve "En atención" cuando `hasAssignee` es `true`.

Las columnas del responsable que agrega EP3-29 se exponen **solo** a través de `RequestView`. El primer commit de EP3-29 es la proyección, para que esas columnas nazcan protegidas.

#### 6.2 Historial (`/actividad`)

| Dato | Vecino | Funcionario, Admin y Auditor |
|---|---|---|
| Eventos `PUBLICO` | Sí | Sí, salvo el hito de asignación (EP3-05, sección 6) |
| Eventos `INTERNO` (gestiones, asignación) | No | Sí |
| Actor de un evento hecho por staff | `actorId: null`, `actorName: "Municipalidad"`, sin `actorRole` | Completo |
| Actor de un evento hecho por el propio Vecino | Su nombre | Completo |
| `interventionReason` | Nunca, aunque la fila sea `PUBLICO` | Sí |
| `rejectionReason` | Sí | Sí |

El filtro por visibilidad es por fila, y no alcanza: el cambio de estado con intervención es una fila `PUBLICO` con un campo interno. Por eso `/actividad` omite `interventionReason` para quien no es staff, y el `summary` ("Pasó de X a Y. Motivo: ...") lleva solo `rejectionReason`.

**Hito público de asignación:** cuando un trámite pasa de no tener responsable a tenerlo, se agrega una fila `PUBLICO` con el `summary` fijo "Tu solicitud fue asignada para su atención", sin actor. El evento `request.assigned` es `INTERNO` y lleva el detalle (EP3-05). Las reasignaciones no generan hito público, para que el Vecino no las lea como desorden.

**Tiempo de asignación:** `tiempos` calcula el tiempo entre el alta y la primera asignación, visible solo para staff. Reemplaza el texto fijo "Tiempo de asignación: el expediente todavía no tiene responsable."

#### 6.3 Dónde nunca viaja el motivo interno

`interventionReason` no viaja en:
- el historial público de `/actividad`;
- los payloads `email.*` de RabbitMQ hacia notify, incluido el de rechazo de EP3-33;
- los PDF de comprobante y certificado.

Viaja en `requests.events`, porque solo lo consumen report y audit (EP3-01, sección 8).

#### 6.4 Notas de las gestiones

El Auditor ve las notas como evidencia de la diligencia del funcionario. El correo del solicitante se oculta por estructura, pero el texto libre de las notas **no se filtra**. Es responsabilidad del funcionario no escribir datos de contacto en ellas. Las notas tampoco viajan en Kafka (EP3-01, sección 8).

#### 6.5 Herencia

El CSV de EP3-63 y cualquier vista futura usan las reglas de esta sección. El CSV las toma del mismo `RequestView` (contrato de EP3-63).

### 7. Contenido de `/inicio`

| Rol | Bloques | Fuente |
|---|---|---|
| **Vecino** | "Nuevo trámite" como acción principal. Sus 5 trámites abiertos más recientes, con folio, estado y "En atención" si tiene responsable. Conteo de abiertos y cerrados | requests: `open=true`, `size=5`, orden por `createdAt` descendente. Conteos con `open=true` y `open=false`, `size=1` y `totalElements` (EP3-30) |
| **Funcionario** | Mis asignados abiertos, del más antiguo al más nuevo. Sin asignar, del más antiguo al más nuevo. Plazos por vencer y vencidos de mis asignados | requests: `assignee=me` y `assignee=none` con `open=true`, orden por `createdAt` ascendente. report: plazos con `assignee=me` |
| **Admin** | KPIs resumidos con polling cada 5 s (K8). Trámites sin asignar (supervisión). Plazos vencidos de toda la comuna | report: KPIs y plazos. requests: `assignee=none` con `open=true` |
| **Auditor** | Últimos eventos de auditoría. Intervenciones del Admin de los últimos 7 días, con `interventionReason` visible | audit: búsqueda paginada con `actorRole=Admin` y los `eventType` de intervención (EP3-07, sección 5.4) |

"Mis asignados" se ordena por antigüedad y no por plazo, porque requests no tiene la fecha límite: la calcula report (EP3-06). Cruzar las dos fuentes en el frontend rompería la paginación. Los plazos van en su propio bloque.

Criterios:

1. **Cada bloque carga y falla por separado.** Si report está caído, el Funcionario sigue viendo su bandeja de requests, y el bloque de plazos muestra "no disponible". Es el "sin bloquear el core" del caso base, llevado a la pantalla.
2. **Estados vacíos explícitos por bloque**, por ejemplo "No tienes trámites asignados", distintos del estado "no disponible" cuando la fuente falla.
3. **Polling solo en los KPIs del Admin** (K8). Se pausa con la pestaña oculta (`visibilitychange`), se detiene al salir de `/inicio`, y ante errores espera más entre intentos en vez de insistir cada 5 s. Los demás bloques cargan al entrar, con botón de actualizar y el `lastEventAt` donde la fuente es report.
4. **Cada bloque enlaza a su vista completa** con los filtros en la URL (EP3-48). Por ejemplo, "Mis asignados" abre `/tramites` con `assignee=me` y `open=true`.
5. **Sin rol o con más de un rol** no hay `/inicio`, sino la pantalla "sin acceso".

### 8. Auditoría de solo lectura

audit es **de solo lectura y de solo agregar** para todos los roles, incluido el Admin:

1. La API de audit no tiene endpoints de escritura (EP3-07), y el servicio no ejecuta `UPDATE` ni `DELETE` sobre su tabla.
2. El Admin no puede impedir que sus acciones lleguen a Oracle desde kafka-admin: no puede eliminar `audit.timeline`, ni adelantar los offsets de `audit-group`, ni bajar `min.compaction.lag.ms` (EP3-03, secciones 3.3, 4 y 6.4).

El Admin ve `/auditoria`, que registra sus propias acciones, y eso no debilita la segregación de funciones, porque no puede modificar lo registrado. El límite a nivel de base de datos está en la sección 10.

### 9. Cambios por capa

| Capa | Cambio | Issue |
|---|---|---|
| **BFF**, `AzureSecurityConfig` | `/api/**` exige exactamente uno de los cuatro roles: sin rol o con más de uno, 403. `PUT /status` y `POST /gestiones` para Funcionario o Admin (hoy solo Funcionario). Tomar, reasignar y lista de funcionarios según EP3-05. Rutas de report y audit con los roles por endpoint de la sección 2 | EP3-45, EP3-44 |
| **BFF**, `RequestStatusOrchestrationService` | Acepta al Admin (hoy compara el texto exacto `"Funcionario"`, línea 62). Corta antes de reservar el cupo según la sección 5. `recognizedRejection` suma los dos mensajes de la sección 5 | EP3-45 |
| **BFF**, cambio de estado y gestiones | Reenvía `interventionReason` en el body | EP3-45 |
| **BFF**, proxy de report y audit | Reenvía `X-User-Id` y `X-User-Roles`, para que report resuelva `assignee=me` | EP3-44 |
| **requests**, `CallerContext` | Distingue Admin, Funcionario, Vecino y Auditor. Rechaza el token sin rol o con más de uno. Expone el rol para `actor_role` | EP3-29 |
| **requests**, `RequestService.changeStatus` y `RequestActivityService.registerGestion` | Hoy exigen Funcionario (líneas 179 y 60). Pasan a la regla de la sección 3: Funcionario responsable o Admin con motivo, dentro de `findByIdForUpdate` | EP3-29 |
| **requests**, respuestas | `RequestView` reemplaza a la entidad en `RequestController`. `toEvento` anonimiza el actor de staff y omite `interventionReason` para quien no es staff | EP3-29 |
| **requests**, modelo | Columnas `intervention_reason` y `actor_role` en `request_activity` | EP3-29, EP3-31 |
| **requests**, listado | Filtro `open=true\|false`, combinado con `status` por un Y lógico | EP3-30 |
| **report** | La proyección de estado por trámite guarda `assigneeId` de `request.assigned`. El endpoint de plazos acepta `assignee=me`. Roles por endpoint | EP3-36, EP3-37, EP3-38 |
| **audit** | Filtro `actorRole` en la búsqueda. Roles Admin y Auditor. Sin escritura | EP3-42 |
| **frontend**, `shared/models/role.ts` | `REQUESTS_ROLES` incluye los cuatro roles. `resolveAccess` cuenta solo los cuatro roles, igual que el BFF | EP3-49 |
| **frontend**, `app.routes.ts` y header | `/reportes` y `/auditoria` para Admin y Auditor. Navegación del rol del usuario. Pantalla "sin acceso" con el motivo, sin rol o con más de uno | EP3-49 |
| **frontend**, detalle | Acciones por rol y por responsable, "Tomar" como acción principal, campo de motivo para el Admin, "En atención" y "Municipalidad" para el Vecino | EP3-46 |
| **frontend**, `/inicio` | Bloques de la sección 7 | EP3-52 |
| **Contratos** | EP3-05 define tomar, reasignar, la lista de funcionarios y su orden de errores. EP3-07 define los roles por endpoint de report y audit, `assignee=me` y `actorRole` | EP3-05, EP3-07 |
| **requests**, payload de RabbitMQ | `email.rejected` y los demás `email.*` no llevan `interventionReason` | EP3-33 |

### 10. Límites conocidos

1. **Ingreso asistido:** un funcionario de ventanilla u OIRS no puede ingresar un trámite a nombre de un vecino que llega en persona, aunque la Ley 19.880 lo contempla. Exige separar al solicitante del actor y capturar sus datos de contacto. Es un cambio de modelo en requests.
2. **Sin segmentación por unidad:** Entra ID entrega el rol, no la oficina ni el sector del funcionario. Todos los funcionarios ven todos los trámites de la comuna. Mejora futura: un grupo de Entra ID o un atributo por unidad.
3. **Plazo para el Vecino** (actualizado por EP3-06): ve el plazo en días hábiles (`slaBusinessDays`), no la fecha límite ni el estado del plazo, que calcula report. Mejora futura: mostrarle `dueDate`, como fecha comprometida ([`procedimiento-plazos.md`](procedimiento-plazos.md), sección 6; EP3.5-22).
4. **Evidencia de resolución:** el Funcionario no adjunta una foto del trabajo terminado.
5. **Colaboración entre funcionarios:** otro Funcionario no puede registrar una gestión en un trámite ajeno. El responsable reasigna, o el Admin interviene.
6. **Abstención (artículo 12 de la Ley 19.880):** la plataforma no detecta conflictos de interés. Con un rol por usuario, un Funcionario o un Admin no puede ser solicitante al crear, y el único caso posible es que el rol de un usuario cambie en Entra ID después de ingresar un trámite. Las causales de abstención dependen de la declaración del funcionario.
7. **Solo agregar a nivel de aplicación:** el usuario de Oracle que usa audit podría borrar filas técnicamente. Cerrarlo exige permisos de solo `INSERT` y `SELECT`, que no están disponibles con un solo esquema en Oracle Autonomous.
8. **Notas de las gestiones:** son texto libre y no se filtran. Pueden contener datos de contacto si el funcionario los escribe.
9. **Exposición hasta EP3-29:** mientras no se integre la proyección, `/actividad` le entrega al Vecino el nombre y el `oid` del funcionario que actuó, y el detalle y el listado entregan `solicitanteEmail` a todos los roles que ven el trámite.
10. **Un rol por usuario:** es consecuencia de que el proyecto usa un solo tenant de Entra ID para vecinos y funcionarios, como exige el caso base. En una municipalidad real, el vecino usaría una identidad ciudadana como ClaveÚnica y el funcionario su cuenta corporativa. La regla seguiría valiendo, porque serían identidades distintas. Integrar ClaveÚnica queda fuera del alcance del proyecto.
