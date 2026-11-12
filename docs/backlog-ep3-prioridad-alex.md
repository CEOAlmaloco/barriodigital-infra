# Backlog EP3 — tareas y qué puede hacer Alex ya

Fuente: issues del Project en `CEOAlmaloco/frontend-barriodigital` (EP3-01 … EP3-82).
Assignees: **CEOAlmaloco = Alex**, **Kuurisuu = Christian**.

## Resumen ejecutivo: qué podés hacer YA

Sin depender de Kuurisuu ni de un bloqueo grande abierto:

| Prioridad | Issue | Repo | Por qué |
|---|---|---|---|
| 1 | **EP3-41** #151 | audit | Deps cerradas; ya implementado en `feature/audit-timeline-consumer` → commit/PR |
| 2 | **EP3-43** #153 | bff | Deps EP3-09/22 cerradas. Token interno + `X-Source-Ip` |
| 3 | **EP3-45** #155 | bff | Deps EP3-04/29/30 cerradas. Reglas por rol, asignación y listado paginado |
| 4 | **EP3-68** #178 | catalog | Dep EP3-26 cerrada. Outbox de auditoría (mejora; no bloquea el camino crítico) |

### Si querés “robar” trabajo chico de Kuurisuu (deps OK, tamaño S/XS)

| Issue | Repo | Nota |
|---|---|---|
| **EP3-35** #145 | report | Esqueleto puerto 8086 (igual que audit). Desbloquea su cadena report |
| **EP3-33** #143 | requests | `email.rejected` en Rabbit. Sin deps |
| **EP3-67** #177 | requests | Códigos de error estables. Sin deps |
| **EP3-13** #123 | infra | Docs Gateway/historial (S). Coordina para no pisarse |
| **EP3-81** #191 | frontend | Aviso de privacidad al crear (XS). Sin deps |

**No conviene robar ahora:** EP3-31 (outbox, M, es el cuello de Christian), ni report consumidor/API (EP3-36…38), ni frontend bandeja/detalle (EP3-46…53).

### Bloqueadas por Kuurisuu (o por su cadena)

- **EP3-31 → 32** (requests outbox/relay) bloquea **EP3-40** (audit `requests.events`), **EP3-36…38** (report), y luego **EP3-42/44**.
- **EP3-35…38** (report) bloquean **EP3-44**, **EP3-50**, **EP3-54**.
- **EP3-46** (detalle frontend) bloquea casi todo el FE de Alex (EP3-72/73/78/80/82).

---

## Orden sugerido para Alex (esta semana)

1. Cerrar **EP3-41** (PR a `develop`; mergear antes EP3-39 si sigue abierto).
2. Hacer **EP3-43** (BFF token + IP).
3. Hacer **EP3-45** (BFF roles/asignación/listado) — desbloquea frontend de Christian.
4. Opcional: **EP3-35** (esqueleto report) si Christian no lo arrancó.
5. Opcional: **EP3-68** (outbox catalog) o **EP3-33/67**.
6. Cuando exista EP3-32: **EP3-40 → EP3-42**.

---

## Inventario OPEN (tareas por ficha)

### EP3-13 — Infra, documentar historial, gestiones, ubicación e imágenes, y verificar rutas del Gateway

- Issue: #123 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `doc/activity-attachments`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-08 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Contratos nuevos en `decisiones.md`:** `request_activity`, `/actividad`, `/gestiones`, ubicación (`LocationRules`) y adjuntos (límites e imágenes permitidas).
  - 2. **Rutas del Gateway verificadas en AWS:** `/actividad`, `/gestiones` y `/attachment` pasan por la ruta `/{proxy+}` con el authorizer, con captura en `docs/evidencias/`.
  - 3. **Contradicciones corregidas:** redirect de Amplify (AADSTS50011) y valor por defecto de `AZURE_AUDIENCES`.
  - 4. **`docs/arquitectura.md`:** muestra catalog, notify, mq-admin y `ec2-mq`.
  - 5. **READMEs** de requests y BFF con los endpoints nuevos.

### EP3-31 — Requests, outbox, rol del actor y plazo en request.created

- Issue: #141 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-outbox`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-02 (CLOSED), EP3-25 (CLOSED), EP3-28 (CLOSED), EP3-29 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Tabla:** entidad y tabla `outbox_events` según EP3-02, con `event_sequence` identity `ORDER` (columna; el campo del JSON sigue siendo `sequence`).
  - 2. **Registro en la misma transacción:** `DomainEventRecorder`, en el paquete de mensajería, registra los eventos dentro de la transacción del cambio y de la `RequestActivity`:
  - - `request.created` (en `RequestService.create`);
  - - `request.status-changed` (en `changeStatus`);
  - - `request.contact-logged` (en `RequestActivityService.registerGestion`);
  - - `request.assigned` (en la asignación).
  - 3. **Rol del actor:** columna `actor_role` nullable en `request_activity` con el único rol del usuario, según EP3-04.
  - 4. **Plazo:** `X-Procedure-Sla-Days` guardado en el trámite, incluido en `request.created` y expuesto en `RequestView`.
  - 5. **Payload:** cumple EP3-01, sin correo, dirección textual ni nota libre. `request.status-changed` y `request.contact-logged` llevan `interventionReason` (`null` si el actor no es Admin).
  - 6. **RabbitMQ:** la publicación con `afterCommit` sigue igual.
  - 7. **Tests:**
  - - un rollback no deja ni la actividad ni el evento;

### EP3-32 — Requests, relay a Kafka

- Issue: #142 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-kafka-relay`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-14 (CLOSED), EP3-31 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-31**
- Criterios / tareas:
  - 1. **Productor:** `spring-kafka` con configuración centralizada en `application.yml` (`acks=all`, idempotencia, sin `NewTopic`, `spring.kafka.admin.auto-create=false`).
  - 2. **Publicación ordenada:**
  - - un `@Scheduled` cada 1 s lee los pendientes por `event_sequence`;
  - - agrega `sequence` al sobre;
  - - publica con key `requestId` y espera la confirmación antes de marcar `published_at`.
  - 3. **Falla de envío:** incrementa `attempts`, guarda `last_error` y detiene el lote.
  - 4. **Limpieza diaria:** solo borra eventos publicados con más de 7 días.
  - 5. **Kafka caído:** el servicio arranca y el HTTP responde normal. Los eventos se acumulan y se publican en orden cuando Kafka vuelve.
  - 6. **Tests:** orden, detención ante falla, limpieza de solo publicados y arranque sin Kafka.

### EP3-33 — Requests, publicar email.rejected en RabbitMQ

- Issue: #143 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-rejected-email`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: ninguna
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Publicación:** el paso a `RECHAZADO` publica `email.rejected` en `cmd.topic` con `afterCommit`, y el payload incluye el motivo.
  - 2. **Topología:** la routing key calza con el binding `email.*`, así que la topología no cambia.
  - 3. **Contrato:** EP2-01 actualizado en `decisiones.md` con el tipo nuevo y el campo de motivo.
  - 4. **Motivo interno excluido:** ningún payload `email.*` incluye `interventionReason`; el correo de rechazo lleva solo `rejectionReason`.
  - 5. **Tests:** un rechazo publica, una transición inválida no publica, y un rechazo del Admin no expone su motivo de intervención.

### EP3-34 — Notify, correo de rechazo y folio en correos y certificados

- Issue: #144 · Servicio: **Notify** · Repo: `ms-barriodigital-notify` · Rama: `feature/notify-rejected-folio`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-33 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-33**
- Criterios / tareas:
  - 1. **Correo de rechazo:** `EmailConsumer` maneja `email.rejected` con un texto que incluye el motivo y el folio.
  - 2. **Folio en todo:** los correos existentes y los PDF de comprobante y certificado muestran el folio cuando viene en el payload.
  - 3. **Sin cambios en la política de ACK:** se mantiene EP2-03.
  - 4. **Tests** del tipo nuevo y del folio en el PDF. Los tests de EP2 siguen en verde.

### EP3-35 — Report, esqueleto del microservicio

- Issue: #145 · Servicio: **Report** · Repo: `ms-barriodigital-report` · Rama: `chore/report-skeleton`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-07 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Repo clonado** y vinculado al Project.
  - 2. **Base del proyecto:**
  - - Spring Boot 3.3.5 y Java 21;
  - - dependencias `spring-kafka`, `data-jpa`, `web`, `actuator` y el driver de Oracle;
  - - wallet configurado como en requests;
  - - puerto 8086.
  - 3. **Archivos base:** `.gitignore`, `.env.example`, `Dockerfile` y README.
  - 4. **Arranque:** `GET /actuator/health` UP con Oracle, y `mvn test` verde con H2.

### EP3-36 — Report, consumidor de requests.events y proyecciones

- Issue: #146 · Servicio: **Report** · Repo: `ms-barriodigital-report` · Rama: `feature/report-consumer`
- Assignee: **Kuurisuu** · Tamaño: L · Estimación: 8
- Depende de: EP3-32 (OPEN), EP3-35 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-32, EP3-35**
- Criterios / tareas:
  - 1. **Listener:** `@KafkaListener` sobre `requests.events`, grupo `report-group`, concurrencia 3, en un paquete de mensajería separado.
  - 2. **Configuración del consumidor (EP3-02):** `ErrorHandlingDeserializer`, validación del sobre, `AckMode.RECORD`, `DefaultErrorHandler` con 1, 2 y 4 s, y `DeadLetterPublishingRecoverer` hacia `requests.events.report.DLT`.
  - 3. **Clasificación de errores:**
  - - `eventType` desconocido: WARN y se confirma;
  - - malformado o incompatible: DLT sin reintentos;
  - - log `evento-muerto` con el formato acordado.
  - 4. **Dominio separado:** `KpiService` actualiza la proyección por trámite (estado actual, `assigneeId` tomado de `request.assigned`, fechas de alta y cierre, y `last_event_at`), sin contadores compartidos (EP3-07), y registra `processed_events` en la misma transacción.
  - 5. **Atrasos:** un evento con `sequence` menor al último aplicado no modifica el estado actual, pero sí cuenta en las métricas históricas. Un evento de un trámite sin proyección crea una proyección parcial, con `sla_status` nulo y sin DLT (EP3-06).
  - 6. **Duplicados:** detectados solo por `pk_processed_events`.
  - 7. **Tests:** duplicado, malformado a la DLT, desconocido ignorado, evento atrasado y proyección parcial completada por un `request.created` posterior.
  - 8. **Prueba de balanceo:** dos instancias en el mismo grupo se reparten las 3 particiones, visible en Kafka UI.

### EP3-37 — Report, API de KPIs

- Issue: #147 · Servicio: **Report** · Repo: `ms-barriodigital-report` · Rama: `feature/report-kpis-api`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-36 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-36**
- Criterios / tareas:
  - 1. **Endpoints:** los de EP3-07 (KPIs y tipos más demandados), calculados con consultas agregadas sobre la proyección, sin reprocesar eventos.
  - 2. **Frescura:** todas las respuestas incluyen `lastEventAt`.
  - 3. **Roles:** se revisan según EP3-07, con 403 para un rol no permitido.
  - 4. **Tests** de cada endpoint con datos de proyección precargados.

### EP3-38 — Report, vencimientos de plazo

- Issue: #148 · Servicio: **Report** · Repo: `ms-barriodigital-report` · Rama: `feature/report-sla`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-36 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-36**
- Criterios / tareas:
  - 1. **Vencimiento:** la fecha se calcula al proyectar `request.created`, con `slaBusinessDays` y el calendario de feriados de EP3-06.
  - 2. **Actualización:** un `@Scheduled` marca "por vencer" y "vencido" sobre las proyecciones, y el plazo se detiene al resolver o rechazar.
  - 3. **API:** los endpoints de plazos de EP3-07 (listado y consulta por lote), con `lastEventAt` y el filtro `assignee=me` (por el `X-User-Id` recibido).
  - 4. **Tests** con fines de semana, feriados, tipos sin plazo, trámites cerrados y filtro por responsable.

### EP3-40 — Audit, consumidor de requests.events

- Issue: #150 · Servicio: **Audit** · Repo: `ms-barriodigital-audit` · Rama: `feature/audit-requests-consumer`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-32 (OPEN), EP3-39 (CLOSED)
- Estado de avance: **BLOQUEADA por EP3-32**
- Criterios / tareas:
  - 1. **Listener:** `@KafkaListener` sobre `requests.events`, grupo `audit-group`, concurrencia 3, con la misma configuración de errores de EP3-36 y DLT `requests.events.audit.DLT`.
  - 2. **Persistencia:** `AuditTrailService` guarda cada evento en la tabla de auditoría (actor, rol, tipo, trámite, folio, `sequence`, resumen, detalle y `occurredAt`), con `uk_audit_entries_event_id`.
  - 3. **Offset:** se confirma después del commit en Oracle.
  - 4. **Tests:** duplicado, malformado y desconocido.

### EP3-41 — Audit, consumidor de audit.timeline

- Issue: #151 · Servicio: **Audit** · Repo: `ms-barriodigital-audit` · Rama: `feature/audit-timeline-consumer`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-23 (CLOSED), EP3-26 (CLOSED), EP3-27 (CLOSED), EP3-39 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Listener:** propio sobre `audit.timeline`, mismo grupo `audit-group`, concurrencia 3, DLT `audit.timeline.audit.DLT`.
  - 2. **Persistencia:** guarda `resourceType`, `resourceId`, `action`, `before`, `after`, `result` y `sourceIp`, con la misma restricción de unicidad.
  - 3. **Separación:** el dominio sigue sin conocer Kafka.
  - 4. **Tests** con eventos de catalog, mq-admin y kafka-admin.

### EP3-42 — Audit, API del timeline

- Issue: #152 · Servicio: **Audit** · Repo: `ms-barriodigital-audit` · Rama: `feature/audit-api`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-40 (OPEN), EP3-41 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-40, EP3-41**
- Criterios / tareas:
  - 1. **Endpoints de EP3-07:**
  - - timeline de un trámite ordenado por `occurredAt`;
  - - búsqueda de eventos con filtros (incluido `actorRole`) y paginación.
  - 2. **Solo lectura:** roles Admin y Auditor, con 403 para el resto.
  - 3. **Tests** de filtros (incluido `actorRole=Admin`), orden y roles.

### EP3-43 — BFF, token interno y X-Source-Ip

- Issue: #153 · Servicio: **BFF** · Repo: `ms-barriodigital-bff` · Rama: `feature/bff-internal-token`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-09 (CLOSED), EP3-22 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Token interno:** se envía `X-Internal-Token`, desde una variable de entorno, en las llamadas a mq-admin y kafka-admin.
  - 2. **IP de origen:** se reenvía `X-Source-Ip`, recibido del Gateway, a catalog, mq-admin y kafka-admin. Nunca se usa `X-Forwarded-For`.
  - 3. **Tests:** headers presentes y ausencia del header de IP cuando el Gateway no lo envía.

### EP3-44 — BFF, proxy de kafka-admin, report y audit

- Issue: #154 · Servicio: **BFF** · Repo: `ms-barriodigital-bff` · Rama: `feature/bff-streaming-proxy`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-22 (CLOSED), EP3-37 (OPEN), EP3-38 (OPEN), EP3-42 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-37, EP3-38, EP3-42**
- Criterios / tareas:
  - 1. **Rutas y roles:**
  - - `/api/kafka/**` solo Admin;
  - - `/api/report/**` con los roles de EP3-07;
  - - `/api/audit/**` para Admin y Auditor.
  - - el proxy de report y audit reenvía `X-User-Id` y `X-User-Roles` (nunca el JWT), para que report resuelva `assignee=me`.
  - 2. **Variables:** `KAFKA_ADMIN_BASE_URL`, `REPORT_BASE_URL` y `AUDIT_BASE_URL`, con timeouts como en `CatalogClientConfig`, salvo la lectura hacia kafka-admin: 25 s, mayor que el tope de 23 s del replay y menor que el límite de 30 s del API Gateway.
  - 3. **Servicio caído:** 503 con el cuerpo de `BffExceptionHandler`.
  - 4. **Tests MockMvc** de 401, 403, 200 y 503 por ruta.

### EP3-45 — BFF, reglas por rol, asignación y listado paginado

- Issue: #155 · Servicio: **BFF** · Repo: `ms-barriodigital-bff` · Rama: `feature/bff-roles-assignment`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-04 (CLOSED), EP3-29 (CLOSED), EP3-30 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Permisos:** `AzureSecurityConfig` aplica la matriz de EP3-04. El Admin puede cambiar estado, registrar gestiones y asignar.
  - 2. **Admisión:** `RequestStatusOrchestrationService` acepta al Admin (hoy compara el texto exacto `Funcionario`). Antes de reservar el cupo responde 400 si el Admin no manda `interventionReason` (sin `GET`), y con el `GET` responde 403 si el Funcionario no es el responsable (comparando el `oid` con `assigneeId`). `recognizedRejection` suma el 403 `Solo el responsable del tramite puede operarlo` y el 400 `interventionReason es obligatorio para el Admin` como red de seguridad ante una reasignación entre el `GET` y el `PUT`.
  - 3. **Asignación:** proxy de tomar, asignar o reasignar, y lista de funcionarios (`take`, `assignee` y `assignees`, según EP3-05).
  - 4. **Listado:** reenvía `page`, `size`, `sort`, `q` y los filtros nuevos, y devuelve la respuesta paginada de EP3-30.
  - 5. **Sin rol:** `/api/**` exige uno de los cuatro roles (Vecino, Funcionario, Admin, Auditor); un token válido sin rol recibe 403. El perfil `dev` mantiene `Vecino` por defecto. Un token con más de un rol recibe 403 `El usuario debe tener un solo rol`.
  - 6. **Tests** por rol de cada ruta modificada, incluido el usuario sin rol, y de que los cortes previos no reservan cupo, y del token con más de un rol.

### EP3-46 — Frontend, vista de detalle del trámite

- Issue: #156 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-request-detail`
- Assignee: **Kuurisuu** · Tamaño: L · Estimación: 8
- Depende de: EP3-45 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-45**
- Criterios / tareas:
  - 1. **Ruta:** `/tramites/:id` como hija del layout autenticado, con `roleGuard` según EP3-04, y enlace desde cada fila del listado.
  - 2. **Contenido:**
  - - folio, datos y estado, y el plazo en días, si tiene;
  - - mapa de la ubicación e imagen adjunta;
  - - línea de tiempo de `/actividad`, con el filtro por rol del backend;
  - - gestiones para staff.
  - 3. **Acciones por rol:** cambiar estado, rechazar y registrar gestión en trámites abiertos, reutilizando los diálogos existentes. El Auditor no ve acciones. "Tomar" es la acción principal de un trámite sin responsable; el Funcionario que no es el responsable solo lee. El Admin ve un campo obligatorio de motivo de intervención, distinto del motivo de rechazo. El Vecino ve "En atención" sin nombre de responsable y los eventos de staff como "Municipalidad".
  - 4. **Estados:** carga, error con reintento y 404 de trámite inexistente.
  - 5. **Estándares del frontend:** standalone, `OnPush`, signals y tokens, con targets de 44 px.
  - 6. **Tests del componente** por rol.

### EP3-47 — Frontend, asignación, delegación y bandeja

- Issue: #157 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-assignment`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-46 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-46**
- Criterios / tareas:
  - 1. **Tomar:** acción "Tomar trámite" en el detalle y el listado.
  - 2. **Asignar y reasignar:** selector de funcionario (lista de EP3-05), con motivo obligatorio solo en la reasignación.
  - 3. **Responsable visible:** en el listado y el detalle.
  - 4. **Bandeja:** "Mis asignados" y "Sin asignar" como filtros rápidos del listado.
  - 5. **Errores del backend:** 403 y 409 con mensajes claros.
  - 6. **Tests.**

### EP3-48 — Frontend, listado profesional

- Issue: #158 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-paged-list`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-45 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-45**
- Criterios / tareas:
  - 1. **Paginación y orden:** `mat-paginator` y orden por columnas con la respuesta paginada de EP3-30.
  - 2. **Búsqueda:** por folio y texto, con espera breve antes de consultar.
  - 3. **Filtros:** estado, tipo, sector y fechas, **también para el vecino**.
  - 4. **Columna de folio.**
  - 5. **Estado en la URL:** los filtros se reflejan en los parámetros de la URL, para compartir o recargar la vista.
  - 6. **Tests.**

### EP3-49 — Frontend, Admin y Auditor en trámites

- Issue: #159 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-admin-auditor-access`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-45 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-45**
- Criterios / tareas:
  - 1. **Roles:** `REQUESTS_ROLES` y la navegación del header según el único rol del usuario (EP3-04).
  - 2. **Admin:** ve todos los trámites con todas las acciones.
  - 3. **Auditor:** ve listado y detalle sin acciones.
  - 4. **Auditoría y reportes:** `/audit` y `/reports` accesibles para Admin y Auditor.
  - 5. **Sin rol o con más de un rol:** pantalla de "sin acceso" con el motivo, en vez del layout vacío.
  - 6. **Tests de guards y navegación** por rol, incluido el usuario sin rol.

### EP3-50 — Frontend, reportería real con polling

- Issue: #160 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-reports`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-44 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-44**
- Criterios / tareas:
  - 1. **Contenido:** `/reports` reemplaza el placeholder con trámites por hora, estados activos, tiempo medio de resolución y tipos más demandados.
  - 2. **Polling (K8):** cada 5 s con `timer` y `switchMap`, solo con la pestaña visible, resultado en signals y detenido al salir de la pantalla.
  - 3. **Frescura visible:** "datos al" con `lastEventAt`, y botón de actualización manual.
  - 4. **Estados:** carga, error y servicio no disponible.
  - 5. **Tests** del ciclo de polling y de la pausa con la pestaña oculta.

### EP3-51 — Frontend, auditoría real

- Issue: #161 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-audit`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-44 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-44**
- Criterios / tareas:
  - 1. **Contenido:** `/audit` reemplaza el placeholder con la búsqueda de eventos (actor, tipo de recurso, tipo de evento y fechas) paginada.
  - 2. **Timeline por trámite:** consultable por folio o desde el detalle.
  - 3. **Cambios de configuración:** muestran `before` y `after` y la IP de origen.
  - 4. **Solo lectura:** sin acciones.
  - 5. **Tests.**

### EP3-52 — Frontend, inicio real por rol

- Issue: #162 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-home`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-47 (OPEN), EP3-50 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-47, EP3-50**
- Criterios / tareas:
  - 1. **Contenido por rol:** `/inicio` reemplaza la demostración temporal con el contenido de EP3-04:
  - - Vecino: "Nuevo trámite", sus 5 trámites abiertos más recientes (folio, estado y "En atención") y conteo de abiertos y cerrados (`open`, `size=1`, `totalElements`);
  - - Funcionario: mis asignados y sin asignar, del más antiguo al más nuevo (requests), y plazos por vencer y vencidos de mis asignados (report, `assignee=me`);
  - - Admin: KPIs con polling cada 5 s, sin asignar y plazos vencidos de la comuna;
  - - Auditor: últimos eventos e intervenciones del Admin de los últimos 7 días (`actorRole=Admin` y los `eventType` de intervención de EP3-07).
  - 2. **Aislamiento:** cada bloque carga y falla por separado ("no disponible"), con estados vacíos explícitos distintos del error.
  - 3. **Polling:** solo en los KPIs del Admin; se pausa con la pestaña oculta, se detiene al salir y espera más entre intentos ante errores. Los demás bloques tienen botón de actualizar y `lastEventAt` cuando vienen de report.
  - 4. **Navegación:** cada bloque enlaza a su vista completa con los filtros en la URL (EP3-48).
  - 5. **Sin rol o con más de un rol:** pantalla "sin acceso" en vez de `/inicio`.
  - 6. **Tests** por rol y de fallo aislado de un bloque.

### EP3-53 — Frontend, estado del plazo y plazo editable

- Issue: #163 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-sla`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-24 (CLOSED), EP3-44 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-44**
- Criterios / tareas:
  - 1. **Indicador:** el `slaStatus` de EP3-06, con su texto en español, en el listado y el detalle, con los datos de report.
  - 2. **Edición:** el Admin edita `slaBusinessDays` en `procedure-type-dialog` (vacío = sin plazo).
  - 3. **Estilos** con tokens, sin colores escritos a mano.
  - 4. **Tests.**

### EP3-54 — Infra, compose de apps con report, audit y kafka-admin

- Issue: #164 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `chore/compose-apps-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-22 (CLOSED), EP3-37 (OPEN), EP3-42 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-37, EP3-42**
- Criterios / tareas:
  - 1. **Servicios nuevos:** report, audit y kafka-admin en `apps/compose.yml` y `apps/compose.ec2.yml`, con `expose` sin `ports` y `mem_limit`.
  - 2. **Variables:** `KAFKA_BOOTSTRAP_SERVERS`, `INTERNAL_TOKEN` y las URL base del BFF, en `apps/.env.example` sin secretos.
  - 3. `docker compose config` sin errores, local y EC2.

### EP3-55 — Infra, rutas del Gateway y X-Source-Ip

- Issue: #165 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `chore/apigw-routes-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-44 (MERGED)
- Estado de avance: **HECHO en Gateway** (docs + evidencias en rama). Pendiente redeploy BFF en EC2 para que kafka/report/audit/assignees dejen de 404.
- Criterios / tareas:
  - 1. **Rutas con el authorizer `entra-jwt`:** `/api/kafka/{proxy+}`, `/api/report/{proxy+}` y `/api/audit/{proxy+}`. Rutas de asignación de EP3-05, con `assignees` literal para que `{id}` no la capture.
  - 2. **IP de origen:** el mapeo de parámetros de la integración hacia el BFF sobrescribe `X-Source-Ip` con `$context.identity.sourceIp`.
  - 3. **CORS** revisado.
  - 4. **Verificación:** sin token responde 401, y un rol insuficiente recibe 403 desde el BFF.
  - 5. **Documentación:** capturas y `decisiones.md` actualizado con la lista de rutas.

### EP3-56 — Infra, despliegue en la nube y flujo completo

- Issue: #166 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `chore/deploy-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-15 (CLOSED), EP3-16 (CLOSED), EP3-54, EP3-55
- Estado de avance: **HECHO en lab (12-nov)** salvo timeline HTTP de audit (bloqueado por EP3-40/42). Docs en `docs/kafka.md` + `docs/evidencias/ep3-56-*`. Pendiente commit/PR `chore/deploy-ep3`.
- Criterios / tareas:
  - 1. **Tópicos:** OK — 3p/RF3 + 3 DLT (`ep3-56-topics.json`).
  - 2. **Flujo del trámite:** OK create→take→admit→gestión→terreno→resuelto + KPIs &lt; 5 s. Timeline HTTP audit pendiente EP3-40/42.
  - 3. **Auditoría de configuración:** OK cupo + cola con `sourceIp` en `audit.timeline`.
  - 4. **Un broker detenido:** OK ISR=2; altas 201.
  - 5. **Todos los brokers detenidos:** OK HTTP 200; outbox + `relay-reanudado` al volver.
  - 6. **report detenido:** OK lag↑; al subir lag=0.
  - 7. **Mensaje malformado:** OK DLT + list/replay kafka-admin (replay OMITIDO sin destino).
  - 8. **Regresión de RabbitMQ:** OK email/ticket/PDF en notify.
  - 9. **Evidencias** en `docs/evidencias/ep3-56-*` y `docs/kafka.md`.

### EP3-57 — Infra, documentación de Kafka y arquitectura

- Issue: #167 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `doc/kafka-architecture`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-56 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-56**
- Criterios / tareas:
  - 1. **`docs/kafka.md`:** diagrama de tópicos, productores, consumidores y grupos; casos de uso; demos paso a paso; límites conocidos (sección 9).
  - 2. **`docs/arquitectura.md`:** incluye Kafka, report, audit, kafka-admin y `ec2-kafka`.
  - 3. **Contratos y READMEs:** `decisiones.md` con todos los contratos de EP3 en su versión final, y README de infra con los repos nuevos.
  - 4. **Prueba de uso:** alguien que no escribió la documentación la siguió y funcionó.

### EP3-58 — Infra, matriz de funcionalidades

- Issue: #168 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `doc/matriz-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-56 (OPEN) — se documenta el estado real aunque EP3-56 siga abierto
- Estado de avance: **EN CURSO** (matriz EP3 + pantallas report/audit + enlace README)
- Criterios / tareas:
  - 1. **Contenido:** la matriz incluye las funcionalidades de EP3, con estado, componente y evidencia verificable (PR, test, endpoint o captura en `docs/evidencias/`).
  - 2. **Pantallas:** las de Reportería y Auditoría pasan a reflejar su implementación real.
  - 3. **Enlace** desde el README de infra.

### EP3-59 — Infra, checklist de la rúbrica de la Parcial 5

- Issue: #169 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `chore/checklist-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: XS · Estimación: 1
- Depende de: EP3-58 (OPEN — PR #69)
- Estado de avance: **EN CURSO** — checklist creado; faltan PDF EP5, suite tests del día y sync `main`
- Criterios / tareas:
  - 1. **Indicadores:** cada uno de los 9 indicadores de la Parcial 5 tiene su evidencia marcada (sección 6.1).
  - 2. **Requisitos transversales verificados:**
  - - compilación y `mvn test` verde en todos los backends;
  - - `ng build` y `ng test` sin errores;
  - - `.gitignore` correcto en todos los repos, incluidos los tres nuevos;
  - - compose de RabbitMQ, Kafka y Kafka UI funcionales.
  - 3. **Entrega:** enlaces a los repos listos para AVA y el correo del docente, y `main` actualizado desde `develop` en todos los repos.

### EP3-60 — Infra, guion y evidencias de la Parcial 6

- Issue: #170 · Servicio: **Infra** · Repo: `barriodigital-infra` · Rama: `doc/guion-ep3`
- Assignee: **CEOAlmaloco, Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-57 (OPEN), EP3-58 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-57, EP3-58**
- Criterios / tareas:
  - 1. **Guion en `docs/guion-ep3.md`:** orden con tiempos y responsable de cada parte, cubriendo los 12 elementos exigidos (sección 6.2) y los indicadores de evaluación.
  - 2. **Capturas de respaldo** de cada punto en `docs/evidencias/`.
  - 3. **Preguntas probables con respuesta:**
  - - por qué 3 Zookeeper y 3 brokers;
  - - por qué 3 particiones y 3 réplicas;
  - - qué es el lag y qué indica;
  - - por qué compactar la auditoría;
  - - qué resuelve el outbox;
  - - cómo se mantiene el orden por trámite;
  - - diferencia entre RabbitMQ y Kafka en esta solución.
  - 4. **Ensayo cronometrado** completo.
  - 5. **Datos de acceso listos:** usuarios por rol, URL de Amplify, Invoke URL, Kafka UI y Management UI de RabbitMQ.

### EP3-61 — Report, puntos para el mapa de trámites

- Issue: #171 · Servicio: **Report** · Repo: `ms-barriodigital-report` · Rama: `feature/report-map-points`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-36 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-36**
- Criterios / tareas:
  - 1. **Endpoint:** devuelve los puntos (latitud, longitud, estado, tipo y sector) de la proyección, con filtros por rango, estado y tipo, e incluye `lastEventAt`.
  - 2. **Tests.**

### EP3-62 — Frontend, mapa de trámites en reportería

- Issue: #172 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-requests-map`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-50 (OPEN), EP3-61 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-50, EP3-61**
- Criterios / tareas:
  - 1. **Mapa:** Leaflet (ya incluido en el proyecto) con marcadores y concentración por sector, filtros y enlace al detalle de cada trámite.
  - 2. **Tests.**

### EP3-63 — Requests, exportar el listado a CSV

- Issue: #173 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-csv-export`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-30 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Endpoint:** exporta con los mismos filtros, reglas de visibilidad y proyección por rol del listado (EP3-04; sin correo para el Auditor), en `text/csv` UTF-8 compatible con Excel, con un tope de filas.
  - 2. **Tests.**

### EP3-64 — Requests, comentario y fotos del vecino

- Issue: #174 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-citizen-comment`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-31 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-31**
- Criterios / tareas:
  - 1. **Comentario:** el titular agrega un comentario en un trámite abierto, con imagen opcional sanitizada como en el alta.
  - 2. **Historial y evento:** queda en el historial público y genera `request.citizen-comment` en el outbox.
  - 3. **Trámites cerrados:** responde 409.
  - 4. **Tests.**

### EP3-65 — Requests, preferencias de aviso del usuario

- Issue: #175 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-notification-prefs`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-31 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-31**
- Criterios / tareas:
  - 1. **Preferencias:** cada usuario guarda si recibe avisos por correo.
  - 2. **Efecto:** requests no publica comandos de correo a RabbitMQ para quien los desactivó. El comprobante PDF se genera igual.
  - 3. **Tests.**

### EP3-66 — Requests, recordatorio de reintento de contacto

- Issue: #176 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-contact-reminder`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-29 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Filtro de pendientes:** el listado filtra los trámites con `nextAttemptAt` vencido o del día, para la bandeja del funcionario.
  - 2. **Tests.**

### EP3-67 — Requests, códigos de error estables

- Issue: #177 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-error-codes`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: ninguna
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Formato:** `@RestControllerAdvice` con un cuerpo de error que incluye un `code` estable para cada error del cambio de estado y la admisión.
  - 2. **Compatibilidad:** los mensajes se mantienen.
  - 3. **Tests.**

### EP3-68 — Catalog, outbox para su auditoría

- Issue: #178 · Servicio: **Catalog** · Repo: `ms-barriodigital-catalog` · Rama: `feature/catalog-outbox`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-26 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Outbox:** catalog aplica el mismo patrón de outbox de requests a sus eventos de auditoría, y elimina para ese servicio el límite de K2.
  - 2. **Tests** de rollback y de publicación diferida.

### EP3-69 — BFF, rutas de Nivel 2 y uso de códigos de error

- Issue: #179 · Servicio: **BFF** · Repo: `ms-barriodigital-bff` · Rama: `feature/bff-level2-routes`
- Assignee: **CEOAlmaloco** · Tamaño: M · Estimación: 5
- Depende de: EP3-63 (OPEN), EP3-64 (OPEN), EP3-65 (OPEN), EP3-66 (OPEN), EP3-67 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-63, EP3-64, EP3-65, EP3-66, EP3-67**
- Criterios / tareas:
  - 1. **Rutas:** exportación CSV, comentario del vecino, preferencias y filtro de recordatorios, con sus roles.
  - 2. **Admisión por código:** `RequestStatusOrchestrationService.recognizedRejection` usa `code` en vez de comparar textos.
  - 3. **Tests.**

### EP3-70 — Frontend, exportar CSV

- Issue: #180 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-csv-export`
- Assignee: **Kuurisuu** · Tamaño: XS · Estimación: 1
- Depende de: EP3-48 (OPEN), EP3-69 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-48, EP3-69**
- Criterios / tareas:
  - 1. **Botón:** "Exportar" en el listado, que descarga con los filtros activos.

### EP3-71 — Frontend, comentario y fotos en el detalle

- Issue: #181 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-citizen-comment`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-46 (OPEN), EP3-69 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-46, EP3-69**
- Criterios / tareas:
  - 1. **Formulario:** el vecino agrega comentario e imagen desde el detalle de un trámite abierto, y aparecen en la línea de tiempo.
  - 2. **Tests.**

### EP3-72 — Frontend, pantalla de perfil

- Issue: #182 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-profile`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-69 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-69**
- Criterios / tareas:
  - 1. **Contenido de `/perfil`:** datos de la cuenta, preferencia de avisos y ajustes de accesibilidad existentes.
  - 2. **Tests.**

### EP3-73 — Frontend, panel de mensajería para el Admin

- Issue: #183 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-messaging-panel`
- Assignee: **CEOAlmaloco** · Tamaño: L · Estimación: 8
- Depende de: EP3-44 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-44**
- Criterios / tareas:
  - 1. **Pestañas en `/admin`:**
  - - colas, DLQ y mensajes de RabbitMQ;
  - - tópicos, consumer groups con lag y DLT de Kafka, con replay.
  - 2. **Confirmación** antes de toda acción destructiva.
  - 3. **Tests.**

### EP3-74 — Requests, encuesta de satisfacción

- Issue: #184 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-satisfaction`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-31 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-31**
- Criterios / tareas:
  - 1. **Respuesta:** el titular califica de 1 a 5 un trámite `RESUELTO`, una sola vez, con comentario opcional.
  - 2. **Evento:** se genera `request.rated` en el outbox.
  - 3. **Tests.**

### EP3-75 — Requests, aviso de posible duplicado

- Issue: #185 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-duplicate-check`
- Assignee: **Kuurisuu** · Tamaño: M · Estimación: 5
- Depende de: EP3-30 (CLOSED)
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Consulta:** devuelve trámites abiertos del mismo tipo cerca de un punto (radio configurable) o en el mismo sector, sin exponer datos del solicitante.
  - 2. **Tests.**

### EP3-76 — Requests, cancelación por el vecino

- Issue: #186 · Servicio: **Requests** · Repo: `ms-barriodigital-requests` · Rama: `feature/requests-citizen-cancel`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-31 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-31**
- Criterios / tareas:
  - 1. **Regla:** el titular cancela solo en `INGRESADO`.
  - 2. **Estado:** se define si se crea un estado nuevo o se reutiliza `RECHAZADO` con un motivo fijo, y se actualiza el contrato.
  - 3. **Historial y evento:** queda en el historial y genera `request.cancelled`.
  - 4. **Tests.**

### EP3-77 — BFF, rutas de Nivel 3

- Issue: #187 · Servicio: **BFF** · Repo: `ms-barriodigital-bff` · Rama: `feature/bff-level3-routes`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-74 (OPEN), EP3-75 (OPEN), EP3-76 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-74, EP3-75, EP3-76**
- Criterios / tareas:
  - 1. **Rutas:** encuesta, consulta de duplicados y cancelación, con sus roles.
  - 2. **Tests.**

### EP3-78 — Frontend, encuesta de satisfacción

- Issue: #188 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-satisfaction`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-46 (OPEN), EP3-77 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-46, EP3-77**
- Criterios / tareas:
  - 1. **Encuesta en el detalle:** se muestra en el detalle de un trámite resuelto, una sola vez.

### EP3-79 — Frontend, aviso de duplicado al crear

- Issue: #189 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-duplicate-warning`
- Assignee: **Kuurisuu** · Tamaño: S · Estimación: 2
- Depende de: EP3-77 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-77**
- Criterios / tareas:
  - 1. **Aviso no bloqueante:** antes de enviar, el formulario de alta muestra los posibles duplicados cercanos.

### EP3-80 — Frontend, cancelar trámite

- Issue: #190 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-citizen-cancel`
- Assignee: **CEOAlmaloco** · Tamaño: XS · Estimación: 1
- Depende de: EP3-46 (OPEN), EP3-77 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-46, EP3-77**
- Criterios / tareas:
  - 1. **Acción:** el titular cancela desde el detalle de un trámite en `INGRESADO`, previa confirmación.

### EP3-81 — Frontend, aviso de privacidad al crear

- Issue: #191 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-privacy-notice`
- Assignee: **Kuurisuu** · Tamaño: XS · Estimación: 1
- Depende de: ninguna
- Estado de avance: **DESBLOQUEADA**
- Criterios / tareas:
  - 1. **Aviso en el formulario de alta:** informa qué datos se guardan y con qué fin, y advierte que no se deben subir fotos con rostros ni patentes.

### EP3-82 — Frontend, plantillas de respuesta del funcionario

- Issue: #192 · Servicio: **Frontend** · Repo: `frontend-barriodigital` · Rama: `feature/frontend-reply-templates`
- Assignee: **CEOAlmaloco** · Tamaño: S · Estimación: 2
- Depende de: EP3-46 (OPEN)
- Estado de avance: **BLOQUEADA por EP3-46**
- Criterios / tareas:
  - 1. **Plantillas:** textos frecuentes seleccionables al rechazar o registrar una gestión, y editables antes de enviar.

---

## Cerradas (referencia rápida)

EP3-01, EP3-02, EP3-03, EP3-04, EP3-05, EP3-06, EP3-07, EP3-08, EP3-09, EP3-10, EP3-11, EP3-12, EP3-14, EP3-15, EP3-16, EP3-17, EP3-18, EP3-19, EP3-20, EP3-21, EP3-22, EP3-23, EP3-24, EP3-25, EP3-26, EP3-27, EP3-28, EP3-29, EP3-30, EP3-39

Total CLOSED: 30 · OPEN: 52 · All EP3 parseadas: 82
