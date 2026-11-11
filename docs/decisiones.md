# Decisiones del proyecto

## Microsoft Entra ID: App Registration "BarrioDigital"

- Tenant ID: ce6e98c4-63f0-4b79-83e5-20925b5fada2
- Client ID (Application ID): a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Authority: https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/
- Application ID URI: `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3` (el `aud` real de los tokens es otro, ver "Contrato JWT")
- Redirect URIs (SPA):
  - http://localhost:4200 (desarrollo). Con este redirect el login sí entrega token.
  - https://main.db7dk8tawyzry.amplifyapp.com es el redirect que manda el frontend
    de este lab. Entra todavía no lo tiene en la app registration: el login
    responde AADSTS50011. Hay que agregarlo en el portal, junto al de localhost,
    para que la sesión de Amplify cierre.

## Roles y usuarios de prueba

### App Roles definidos en Microsoft Entra ID
- Admin
- Funcionario
- Vecino
- Auditor

### Usuarios de prueba
| Usuario | Rol asignado |
|---|---|
| admin.test@cloudproyecto.onmicrosoft.com | Admin |
| funcionario.test@cloudproyecto.onmicrosoft.com | Funcionario |
| vecino.test@cloudproyecto.onmicrosoft.com | Vecino |
| auditor.test@cloudproyecto.onmicrosoft.com | Auditor |

## Despliegue en AWS

- catalog, notify, requests y el BFF corren en la EC2 `barriodigital-apps`
  (`i-0e0571365e11188c4`, IP pública `54.175.48.178`, privada `172.31.45.131`).
  Los cuatro contenedores están Up y healthy: `bd-catalog`, `bd-notify`,
  `bd-requests` y `bd-bff`. Al encender el lab la IP pública cambió y el
  Gateway quedó apuntando a la anterior; se actualizó a esta. El BFF se
  recreó a las 23:29Z, con catalog ya healthy. Si se recrea la instancia
  cambia su IP pública, y hay que actualizar la integración del API Gateway
  hacia el BFF.
- catalog no publica puerto: `expose: "8082"`, sin `ports`. El BFF lo llama con
  `CATALOG_BASE_URL=http://catalog:8082`. `reserve` y `release` no validan JWT
  y solo son alcanzables dentro de la red del compose.
- El orden de despliegue es catalog primero y el BFF después. El compose espera
  a que el health de catalog esté UP antes de arrancar el BFF. Si se recrea el
  BFF mientras catalog no responde, el alta de trámites responde 503.
- API Gateway (HTTP API `barriodigital-http`), Invoke URL: https://0yo277ntr8.execute-api.us-east-1.amazonaws.com
  - Reenvía al BFF en `http://54.175.48.178:8080`. En catalog y en mq la integración
    conserva el prefijo (`/api/catalog/{proxy}`, `/api/mq/{proxy}`): en esas rutas
    `{proxy}` es solo el resto del path.
  - JWT Authorizer `entra-jwt`: issuer https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/v2.0.
    Audiences: `a0773f3e-abc6-4b53-86fc-9d33a2eddef3` y `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3`.
  - JWT en las rutas de negocio. Sin token el Gateway responde 401. No mira el rol:
    Funcionario con token válido en `/api/mq/queues` recibe 403 del BFF
    (`No tienes el rol necesario para este recurso`). Con catalog y requests
    arriba, `POST /api/requests` por este Gateway respondió 201.
  - `GET /api/ping`, `GET /api/requests`, `POST /api/requests` y `GET /api/requests/{id}`
    siguen entrando por `GET|POST|PUT|PATCH|DELETE /{proxy+}`.
  - Rutas explícitas de EP2-30, mismo authorizer `entra-jwt`:
    - `GET`, `POST` y `PUT /api/catalog/{proxy+}`.
    - `GET /api/requests/meta/transitions` (literal, para que `{id}` no capture `meta`).
    - `PUT /api/requests/{id}/status`.
    - `GET`, `POST`, `PUT` y `DELETE /api/mq/{proxy+}`.
  - No quedó `ANY /{proxy+}`. Esa ruta también capturaba `OPTIONS` y el preflight
    respondía 401. HTTP API no tiene `**`; `{proxy+}` cubre el resto del path.
  - CORS del Gateway, sin `*`. Orígenes: `http://localhost:4200`,
    `https://main.db7dk8tawyzry.amplifyapp.com` y el sitio S3 del front de este lab.
    Métodos `GET`, `POST`, `PUT`, `PATCH`, `DELETE` y `OPTIONS`. Headers
    `authorization`, `content-type`, `x-user-id` y `x-user-roles`. El preflight lo
    responde el Gateway, sin JWT.
- Frontend desplegado en AWS Amplify Hosting: https://main.db7dk8tawyzry.amplifyapp.com
  - App `barriodigital-front` (`db7dk8tawyzry`), rama `main`, job manual 3.
    El build publicado llama a este Gateway. Entra ya acepta el redirect de
    Amplify: con la cuenta vecino la sesión abre `/inicio` ("Hola, Vecino Test").
  - Deploy manual, sin repositorio Git conectado, con una regla de rewrite
    (`404-200` a `/index.html`) para las rutas de Angular.
  - Se descartó CloudFront + S3 porque cloudfront:CreateDistribution no está
    permitido en el rol del Learner Lab.
- Oracle Autonomous Database vive en OCI, no en AWS. El wallet se monta en los
  contenedores de requests y de catalog como volumen (`/wallet`) y nunca va a Git.
- ec2-mq es `i-0e487974a1f920449` (pública `54.81.56.155`, privada
  `172.31.46.156`). Corren `rabbitmq-1` y `rabbitmq-2`, los dos healthy, en el
  clúster `rabbit@rabbitmq-1` / `rabbit@rabbitmq-2`. AMQP `5672` está publicado
  solo en `172.31.46.156` y el security group lo admite desde el security group
  de ec2-apps. Management `15672` está en `0.0.0.0` del host y el security group
  lo admite solo desde `201.187.175.153/32`. Ninguno de los dos puertos se abre
  a `0.0.0.0/0`. notify y requests usan `RABBIT_ADDRESSES=172.31.46.156:5672`:
  hay dos conexiones del usuario `barriodigital` desde `172.31.45.131`, y
  consumidores en `q.cmd.email`, `q.cmd.crew` y `q.cmd.certificate`.
  La IP pública cambia al recrear la instancia; cómo rehacerla está en
  `mq/README.md`. En local los dos puertos siguen en `127.0.0.1`.

## Contrato JWT

- Claim de rol: `roles` (estándar de Microsoft Entra ID para App Roles asignados a usuarios)
- Audience: el Application ID URI configurado es `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3`,
  pero el claim `aud` real dentro de los tokens v2 que emite Entra ID viene como
  el GUID plano (`a0773f3e-abc6-4b53-86fc-9d33a2eddef3`), sin el prefijo `api://`.
  Cualquier validador de audience (API Gateway JWT Authorizer, BFF, etc.) debe
  aceptar el GUID plano; el Application ID URI puede quedar como segundo valor
  aceptado, pero no alcanza por sí solo.
  - BFF: acepta los valores de `AZURE_AUDIENCES`, separados por coma. Su valor
    por defecto en `application.yml` es solo `api://…`, así que el `.env` (de la
    EC2 y el local) debe traer ambos:
    `AZURE_AUDIENCES=api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3,a0773f3e-abc6-4b53-86fc-9d33a2eddef3`.
    Sin el GUID, el BFF responde 401 "Audience inválido".
- Scopes: openid, profile (login básico vía MSAL)
  - Scope custom `access_as_user`: en uso desde EP1. El frontend lo solicita en el login (msal-config.ts) junto con openid/profile, para que el accessToken tenga audience hacia la API y traiga el claim `roles`.
- El BFF valida issuer, audience y firma contra el token recibido; no valida un scope custom todavía, solo el claim `roles` para autorización.

## Contrato: cambio de estado del trámite (EP1.5-01)

### 1. Transiciones válidas

| Desde | Hacia |
|---|---|
| INGRESADO | ADMITIDO |
| INGRESADO | RECHAZADO |
| ADMITIDO | EN_GESTION |
| ADMITIDO | RECHAZADO |
| EN_GESTION | EN_TERRENO |
| EN_GESTION | RECHAZADO |
| EN_TERRENO | RESUELTO |
| EN_TERRENO | RECHAZADO |

RESUELTO y RECHAZADO son estados terminales, sin transiciones salientes. RECHAZADO es alcanzable desde cualquier estado no terminal, no solo desde EN_TERRENO. Política de cupo: el cupo diario reservado al pasar a ADMITIDO (ver contrato de EP1.5-03) nunca se libera automáticamente por un rechazo posterior, la orquestación de cupo de EP1.5-18 solo participa en la transición INGRESADO a ADMITIDO.

### 2. Autorización

**Actualizado el 5-nov-2026 por EP3-04.** Pueden invocar este endpoint:
- el **Funcionario responsable** del trámite (EP3-05);
- el **Admin**, como intervención, con `interventionReason` obligatorio.

Un Funcionario que no es el responsable, o un trámite sin responsable, responde 403. El Vecino y el Auditor reciben 403 por rol. Las reglas completas están en EP3-04, secciones 3 y 4.

El Vecino no puede cancelar su propio trámite en esta versión. Si entra EP3-76 (prioridad Baja), ese contrato lo define.

*Antes de EP3-04, solo el Funcionario podía invocar este endpoint y el Admin recibía 403.*

### 3. Endpoint y payload

```
PUT /api/requests/{id}/status
```

```json
{
  "status": "RECHAZADO",
  "rejectionReason": "Direccion fuera de la comuna"
}
```

- `status`: obligatorio, debe ser uno de los 6 valores de `RequestStatus` (INGRESADO, ADMITIDO, EN_GESTION, EN_TERRENO, RESUELTO, RECHAZADO).
- `rejectionReason`: obligatorio y no vacío únicamente cuando `status` es RECHAZADO, se ignora en cualquier otra transición. Máximo 500 caracteres.
- `interventionReason`: obligatorio y no vacío cuando quien llama es Admin (EP3-04, sección 3). Máximo 500 caracteres. Es un motivo **interno**: nunca le llega al Vecino. Es distinto de `rejectionReason`, que sí se le comunica. Si el Admin rechaza, los dos son obligatorios. Se ignora para los demás roles.
- Requiere identidad del caller vía header `X-User-Id`, mismo patrón ya usado en `create()` y `getById()`.

### 4. Respuesta en éxito

200, devuelve el recurso completo actualizado, misma forma que `GET /api/requests/{id}` (incluye `rejectionReason` cuando aplica, y `solicitanteNombre` una vez implementado EP1.5-24).

### 5. Errores

| Código | Causa |
|---|---|
| 400 | `status` ausente o no es un valor válido del enum |
| 400 | `rejectionReason` ausente o vacío cuando `status` es RECHAZADO |
| 400 | falta identidad del caller (header X-User-Id) |
| 400 | `interventionReason` ausente o vacío cuando quien llama es Admin |
| 403 | el rol no permite operar trámites (Vecino, Auditor, sin rol o con más de un rol) |
| 403 | quien llama es Funcionario y no es el responsable del trámite, o el trámite no tiene responsable |
| 404 | el trámite no existe |
| 409 | la transición desde el estado actual al `status` solicitado no está en la tabla del punto 1 |

El orden de evaluación está en EP3-04, sección 5.

### 6. Nota técnica: mensajes de error no llegaban al cliente

`application.yml` de `ms-barriodigital-requests` no tiene `server.error.include-message` seteado, el default de Spring Boot es `never`, por lo que el campo `message` del cuerpo de error venía vacío pese a que el código ya lanzaba el texto correcto. Esto afecta no solo al 409 nuevo, sino a los 400 y 404 que ya existían en `create()` y `getById()`. Se agrega `server.error.include-message: always` bajo `server:` (mismo nivel que `port`) como parte de EP1.5-04.

## Contrato: preferencias de aviso del usuario (EP3-65)

### 1. Regla

Cada usuario (clave `X-User-Id`) guarda si recibe avisos por correo. **Sin fila = habilitado** (opt-out). Si `emailEnabled` es `false`, requests **no publica** comandos `email.*` a RabbitMQ para los trámites de ese titular. Los comandos `certificate.*` (comprobante/certificado PDF) y `crew.ticket` **sí se publican**.

### 2. Endpoints

```
GET  /api/requests/me/notification-preferences
PUT  /api/requests/me/notification-preferences
```

```json
{ "emailEnabled": false }
```

Cualquier rol autenticado con identidad. 200 con el mismo cuerpo. `emailEnabled` es obligatorio en el PUT.

### 3. Persistencia

Tabla `user_notification_prefs` (`user_id` PK, `email_enabled`, `updated_at`). Hibernate `ddl-auto: update` la crea.

### 4. Errores

| Código | Causa |
|---|---|
| 400 | falta `X-User-Id`, o falta `emailEnabled` en el PUT |

## Contrato: catálogo de tipos de trámite (EP1.5-02)

### 1. Modelo base

| Campo | Tipo | Nota |
|---|---|---|
| value | string | identificador de negocio, inmutable una vez creado. Mismo nombre que ya usa el frontend en `TipoTramiteOption.value`, y que `ProcedureTypes.java` ya describe como "el código (value)" del contrato front-back |
| label | string | texto a mostrar, en español, editable |
| active | boolean | determina si el tipo de trámite está disponible para nuevas solicitudes |

Los campos de cupo (`dailyQuota`, `remainingQuota`, `quotaResetDate`) no forman parte de esta entidad ni de este contrato, se agregan en EP1.5-16 como migración aparte, según lo acordado en EP1.5-03.

### 2. Qué es editable

`value` es inmutable, es la clave que usan los trámites existentes para referenciar el tipo. `label` y `active` son editables vía `PUT`.

### 3. Endpoints y payload

`GET /api/catalog/procedures`, cualquier rol autenticado, sin filtro en el backend, devuelve siempre la lista completa (activos e inactivos):

```json
[
  { "value": "bache", "label": "Bache en calle", "active": true },
  { "value": "alumbrado", "label": "Alumbrado publico", "active": true }
]
```

El filtrado por active es responsabilidad del frontend, no del backend: el formulario de creación de trámite (Vecino) filtra a `active === true`, mientras que la vista Admin de catálogo y cualquier resolución de label sobre un trámite ya existente usan la lista completa, para que un tipo desactivado no rompa el label de trámites históricos.

`POST /api/catalog/procedures`, solo Admin:

```json
{ "value": "semaforo", "label": "Semáforo en mal estado", "active": true }
```

`active` es opcional, por defecto `true` si se omite. Respuesta `201` con el objeto creado.

`PUT /api/catalog/procedures/{value}`, solo Admin, reemplazo completo de los campos editables, no parcial:

```json
{ "label": "Semáforo intermitente", "active": false }
```

Respuesta `200` con el objeto actualizado completo.

**Actualización (EP3-06, 6-nov-2026):** catalog lee el body de forma estricta (`accept-float-as-int: false` y `allow-coercion-of-scalars: false`). Un número o un booleano enviado como string o como decimal responde 400: `active: "true"`, `dailyQuota: "5"` o `dailyQuota: 5.0` ya no se aceptan. El frontend ya envía los tipos correctos. Los mensajes están en EP3-06, sección 1.

### 4. Validación de value

Solo en POST, debe cumplir `^[a-z0-9_-]+$` (minúsculas, sin espacios ni tildes), mismo formato que los 6 valores ya existentes (bache, alumbrado, basura, agua, ruido, otro).

### 5. Errores

| Código | Causa |
|---|---|
| 400 | value ausente, vacío, o no cumple el patrón esperado (solo en POST) |
| 400 | label ausente o vacío (POST y PUT) |
| 403 | el rol no es Admin (POST y PUT) |
| 404 | el value indicado en PUT no existe |
| 409 | el value indicado en POST ya existe |

### 6. Por qué active y no DELETE

La necesidad real es pausar y reanudar un tipo de trámite (por ejemplo, el municipio deja de recibir cierto tipo de solicitud directamente, o un trámite estacional se pausa fuera de temporada), no eliminarlo definitivamente. Con value inmutable y active como toggle, los trámites históricos de ese tipo nunca pierden su label ni su integridad, se puede reactivar sin recrear nada. Mismo patrón que usan Stripe Product y Price con su propio campo active: archivar no afecta lo que ya existe, solo bloquea uso nuevo.

### 7. Notas pendientes para EP1.5-09

- Revisar si ms-barriodigital-catalog tiene el mismo problema detectado en EP1.5-04: `server.error.include-message` sin setear en su `application.yml`, lo que dejaría el campo `message` vacío en los errores 400/403/404/409 de este contrato.
- Las labels de `ProcedureTypes.java` (ms-barriodigital-requests) y `TIPOS_TRAMITE_PROVISIONAL` (frontend-barriodigital) no coinciden exactamente para basura y ruido, y alumbrado difiere en tilde. Elegir una sola versión como dato semilla.

## Contrato: cupos diarios (EP1.5-03)

### 1. Dónde vive la lógica de descuento

`catalog` mantiene su propio contador (`dailyQuota`, `remainingQuota`, `quotaResetDate`) con reset diario perezoso, **sin consultar nunca a `requests`**. El BFF orquesta la transición de `INGRESADO` a `ADMITIDO` llamando primero a `reserve` en catalog y después al cambio de estado en requests; si el cambio de estado falla después de reservar, el BFF llama a `release` como compensación.

Ninguna otra transición de estado participa de la orquestación de cupo: el cupo reservado al admitir **nunca se libera automáticamente** por un `RECHAZADO` posterior, según lo ya establecido en el contrato de EP1.5-01.

### 2. Campos

| Campo | Tipo | Nota |
|---|---|---|
| `dailyQuota` | integer, nullable | `null` significa sin límite, `reserve` nunca falla por cupo para ese tipo. No se puede setear en POST (EP1.5-02), solo después vía PUT. |
| `remainingQuota` | integer, nullable | refleja el cupo disponible hoy. `null` cuando `dailyQuota` es `null`. |
| `quotaResetDate` | date | columna interna de persistencia, **no se serializa** en ninguna respuesta de la API. |

Desde EP3-06, `dailyQuota` tiene que llegar como entero de JSON: como string o decimal responde 400 (EP1.5-02, sección 3, actualización del 6-nov-2026).

**Reset perezoso:** en la primera llamada a `reserve` del día, si `quotaResetDate` es distinto a la fecha actual, se repone `remainingQuota` a `dailyQuota` y se actualiza `quotaResetDate`, antes de aplicar el descuento.

### 3. Exposición en GET

Una vez implementado este contrato, `GET /api/catalog/procedures` incluye `dailyQuota` y `remainingQuota` en cada ítem, `quotaResetDate` nunca se expone:

```json
{ "value": "bache", "label": "Bache en calle", "active": true, "dailyQuota": 20, "remainingQuota": 13 }
```

Para un tipo sin límite, ambos vienen en `null`.

### 4. Endpoints

```
POST /api/catalog/procedures/{value}/reserve
POST /api/catalog/procedures/{value}/release
```

Sin body en ninguno de los dos, la cantidad siempre es 1.

- **`reserve`**: aplica el reset perezoso del punto 2 si corresponde, descuenta 1 de `remainingQuota` si hay cupo. Si `dailyQuota` es `null`, responde 200 sin modificar nada (no-op).
- **`release`**: repone 1 a `remainingQuota`, con tope `remainingQuota = min(remainingQuota + 1, dailyQuota)`, para no superar el límite ante una compensación duplicada. Si `dailyQuota` es `null`, responde 200 sin modificar nada (no-op). **Nunca devuelve 409**, es una compensación que siempre debe poder ejecutarse.

Respuesta en éxito (200) en ambos: el recurso completo actualizado, misma forma que un ítem de `GET /api/catalog/procedures`.

### 5. Errores

| Código | Causa |
|---|---|
| 404 | el `value` indicado no existe |
| 409 | solo en `reserve`: `remainingQuota` es 0 después de aplicar el reset diario |

### 6. Autenticación

`reserve` y `release` **no validan rol ni JWT** dentro de catalog, confían en que solo el BFF los invoca. Por eso catalog no se publica al host, ver el punto 7.

### 7. Catalog en el compose, sin puerto público

catalog usa `expose: "8082"` y no tiene `ports`, en `apps/compose.yml` y en `apps/compose.ec2.yml`. Solo lo alcanza el BFF, con `CATALOG_BASE_URL=http://catalog:8082`. requests sigue publicado en el 8081 para el health local; el security group de la EC2 no abre ese puerto ni el 8082.

El BFF declara `depends_on` de catalog con `condition: service_healthy`. Catalog tiene que estar UP antes de que el BFF arranque. Si se redespliega el BFF primero, el alta de trámites responde 503 porque catalog no valida el tipo a tiempo.

## Cupo diario nulo y día en Chile (EP1.5-03)

`dailyQuota` y `remainingQuota` en null significan sin límite. El seed y el POST no ponen 10: un tipo nuevo no queda limitado hasta que el Admin lo pida. El día del reset es `America/Santiago`, no UTC, para que no cambie a las 20:00 o 21:00.

El PUT reemplaza el cupo completo. Si el cuerpo no trae `dailyQuota`, el tipo pasa a sin límite. El frontend tiene que mandar siempre el campo cuando quiere conservar el número; si lo omite, lo saca. En Oracle, `ddl-auto: update` no relaja un NOT NULL ya creado: hace falta un `ALTER` manual de `daily_quota` y `remaining_quota`.

## Contrato: mensajería al cambiar el trámite (EP2-01)

`ms-barriodigital-requests` publica un evento después de confirmar el alta o el cambio de estado. `ms-barriodigital-notify` lo consume. El HTTP no espera al broker: si RabbitMQ no responde, la respuesta del trámite no cambia.

### 1. Qué eventos existen

| type | Quién publica | Cuándo | Quién consume | Para qué |
|---|---|---|---|---|
| `certificate.receipt` | requests | alta del trámite, queda `INGRESADO` | notify | comprobante en PDF |
| `email.admitted` | requests | `INGRESADO` → `ADMITIDO` | notify | email de admisión |
| `crew.ticket` | requests | `EN_GESTION` → `EN_TERRENO` | notify | ticket para la cuadrilla |
| `email.visit` | requests | `EN_GESTION` → `EN_TERRENO` | notify | email de visita |
| `email.resolved` | requests | `EN_TERRENO` → `RESUELTO` | notify | email de cierre |
| `certificate.resolved` | requests | `EN_TERRENO` → `RESUELTO` | notify | certificado en PDF |

`EN_TERRENO` publica dos eventos en el mismo cambio: `crew.ticket` y `email.visit`. `RESUELTO` publica `email.resolved` y `certificate.resolved`. Comparten el `correlationId` del trámite.

No publican mensaje:

- Reservar o liberar cupo. El cupo de EP1.5-03 es una llamada HTTP del BFF a catalog, no un evento.
- `ADMITIDO` → `EN_GESTION`.
- Cualquier transición a `RECHAZADO`. En esta etapa un rechazo no avisa al vecino.
- Una transición rechazada (409) o un alta que no se confirma. Si el commit no ocurre, no hay evento.

### 2. Sobre

Todos los mensajes usan el mismo sobre. `type` dice qué evento es. `eventId` identifica el mensaje. `correlationId` es el id del trámite.

| Campo | Tipo | Nota |
|---|---|---|
| `type` | string | uno de los seis de la tabla anterior |
| `eventId` | uuid | único por mensaje. Sirve para no procesar dos veces el mismo envío |
| `timestamp` | instant UTC | momento de la publicación, ISO-8601 con `Z` |
| `traceId` | uuid | seguimiento del cambio que originó el mensaje |
| `correlationId` | string | id del trámite |
| `payload` | objeto | datos del caso. No repite el `type` |

`payload` lleva `requestId`, `procedureType`, `procedureLabel`, `address` y `solicitanteEmail`. `solicitanteEmail` puede venir `null` en trámites antiguos. `crew.ticket` necesita `address`. Los emails necesitan `solicitanteEmail`.

**Actualización (EP3-05, 5-nov-2026):** `payload` agrega `folio` (`BD-AAAA-NNNNNN`). Puede venir `null` en mensajes publicados antes de EP3-28. Es un cambio compatible: los consumidores de notify ignoran los campos que no usan.

### 3. Ejemplos

`certificate.receipt`, al crear el trámite:

```json
{
  "type": "certificate.receipt",
  "eventId": "8f1c2a40-6b2e-4d1a-9c33-1a0e5f7b2d10",
  "timestamp": "2026-10-20T15:04:05Z",
  "traceId": "c3a91e22-0d44-4f6b-8a17-55e2b0c4d901",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

`email.admitted`, al pasar a `ADMITIDO`:

```json
{
  "type": "email.admitted",
  "eventId": "11aa22bb-33cc-44dd-55ee-66ff77889900",
  "timestamp": "2026-10-20T16:10:00Z",
  "traceId": "aa11bb22-cc33-4dd5-8ee6-ff0011223344",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

`crew.ticket` y `email.visit` salen juntos al pasar a `EN_TERRENO`. El `correlationId` es el mismo. El `eventId` no.

```json
{
  "type": "crew.ticket",
  "eventId": "90ab12cd-34ef-4567-89ab-cdef01234567",
  "timestamp": "2026-10-21T13:00:00Z",
  "traceId": "bb22cc33-dd44-4ee5-9ff6-001122334455",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

```json
{
  "type": "email.visit",
  "eventId": "12cd34ef-56ab-4789-90ab-cdef67890123",
  "timestamp": "2026-10-21T13:00:00Z",
  "traceId": "bb22cc33-dd44-4ee5-9ff6-001122334455",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

`email.resolved` y `certificate.resolved` salen juntos al pasar a `RESUELTO`:

```json
{
  "type": "email.resolved",
  "eventId": "aabbccdd-eeff-4011-2233-445566778899",
  "timestamp": "2026-10-22T18:30:00Z",
  "traceId": "cc33dd44-ee55-4ff6-8011-223344556677",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

```json
{
  "type": "certificate.resolved",
  "eventId": "ddeeff00-1122-4333-8444-556677889900",
  "timestamp": "2026-10-22T18:30:00Z",
  "traceId": "cc33dd44-ee55-4ff6-8011-223344556677",
  "correlationId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
  "payload": {
    "requestId": "7b6e1d44-2a18-4c90-9f01-88aa11bb22cc",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "address": "Los Aromos 120",
    "solicitanteEmail": "vecino@example.com"
  }
}
```

### 4. Cuándo se publica

La publicación ocurre después del commit, nunca dentro de la transacción y nunca en el hilo que responde el HTTP. Si el alta o el cambio de estado se revierte, no sale ningún mensaje.

El cliente de RabbitMQ usa un timeout de conexión de 2 segundos. Publicar es asíncrono. Si el broker no responde, requests registra el error en el log y no lo lanza hacia el servicio que cambió el estado. El alta sigue respondiendo 201 y el cambio de estado sigue respondiendo 200.

### 5. Límites conocidos

- No hay outbox. Si el broker está caído en el momento de publicar, el evento se pierde. Solo queda el log. Es el costo de no hacer esperar al HTTP.
- La idempotencia vive en la memoria de notify. Si ese proceso se reinicia, olvida los `eventId` ya vistos y puede repetir un correo o un PDF.
- Un `RECHAZADO` no avisa al vecino.

## Contrato: topología RabbitMQ (EP2-02)

Nombres que `requests`, `notify` y `mq-admin` copian a su `application.yml`. No se escriben en clases de negocio. Los `type` del contrato de mensajería (EP2-01) son las routing keys con las que publica la aplicación.

### 1. Exchanges, colas y bindings

| Exchange | Tipo | Routing key | Destino | Argumentos de la cola |
|---|---|---|---|---|
| `cmd.direct` | direct | `email.send` | `q.cmd.email` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=email.dead` |
| `cmd.topic` | topic | `email.*` | `q.cmd.email` | los mismos |
| `cmd.direct` | direct | `crew.ticket` | `q.cmd.crew` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=crew.dead` |
| `cmd.topic` | topic | `crew.#` | `q.cmd.crew` | los mismos |
| `cmd.direct` | direct | `certificate.gen` | `q.cmd.certificate` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=certificate.dead` |
| `cmd.topic` | topic | `certificate.*` | `q.cmd.certificate` | los mismos |
| `cmd.dead.dlx` | direct | `email.dead` | `q.cmd.email.dlq` | ninguno |
| `cmd.dead.dlx` | direct | `crew.dead` | `q.cmd.crew.dlq` | ninguno |
| `cmd.dead.dlx` | direct | `certificate.dead` | `q.cmd.certificate.dlq` | ninguno |

Exchanges, colas y DLQ son durables. Los mensajes se publican persistentes. Las DLQ no tienen consumidor ni dead-letter propio: un mensaje muerto se queda ahí para verlo en el Management UI.

La aplicación publica así. El otro binding de cada cola queda para probar desde el Management UI o desde mq-admin.

| type | Exchange | Routing key |
|---|---|---|
| `email.admitted`, `email.visit`, `email.resolved` | `cmd.topic` | el propio `type` |
| `crew.ticket` | `cmd.direct` | `crew.ticket` |
| `certificate.receipt`, `certificate.resolved` | `cmd.topic` | el propio `type` |

`email.admitted` calza con `email.*`. `certificate.receipt` calza con `certificate.*`. `crew.ticket` calza con el binding direct. Direct y topic quedan los dos en uso.

### 2. Nombres en YAML

Las tres aplicaciones usan las mismas claves. `requests` declara los exchanges. `notify` declara colas, DLQ y bindings. `mq-admin` lee los nombres para no permitir borrar ni vaciar `cmd.*` ni `q.cmd.*`.

```yaml
barriodigital:
  rabbit:
    exchange:
      topic: cmd.topic
      direct: cmd.direct
      dead: cmd.dead.dlx
    queue:
      email: q.cmd.email
      email-dlq: q.cmd.email.dlq
      crew: q.cmd.crew
      crew-dlq: q.cmd.crew.dlq
      certificate: q.cmd.certificate
      certificate-dlq: q.cmd.certificate.dlq
    routing:
      email-send: email.send
      email-topic: email.*
      crew-ticket: crew.ticket
      crew-topic: crew.#
      certificate-gen: certificate.gen
      certificate-topic: certificate.*
      email-dead: email.dead
      crew-dead: crew.dead
      certificate-dead: certificate.dead
```

### 3. Tipo de cola y los dos nodos

Colas clásicas durables. No quorum y no mirroring.

El clúster de la demo tiene dos nodos. Una cola quorum necesita mayoría para aceptar escrituras: con dos réplicas, si un nodo se cae no hay mayoría y la cola deja de aceptar mensajes. El mirroring de colas clásicas (`ha-mode`) está deprecado en RabbitMQ 3.12 y no se usa.

Cada cola vive en el nodo que la posee. Al reiniciar ese nodo, la cola durable y los mensajes persistentes siguen ahí. El segundo nodo cumple el clúster (los dos aparecen en `cluster_status` y en el Management UI). No replica las colas. Si el nodo dueño no vuelve, esas colas no se atienden hasta que regrese.

### 4. Bindings: los seis

Se declaran los seis bindings de las colas principales, más los tres de las DLQ. Es la tabla de la sección 9 del caso: cada cola tiene un binding direct y uno topic.

La alternativa era declarar solo el binding por el que publica la aplicación (topic para email y certificado, direct para cuadrilla). También deja direct y topic en uso, pero borra de la topología los bindings que el caso ya nombra. Se descarta.

### 5. Orden de arranque

`requests` declara `cmd.topic`, `cmd.direct` y `cmd.dead.dlx`. `notify` también declara esos exchanges,
además de las colas, DLQ y bindings, para poder iniciar sin depender de Requests. Así se evita una dependencia
circular. Las declaraciones repetidas deben tener atributos compatibles: mismo tipo, durabilidad,
auto-delete y argumentos; de lo contrario RabbitMQ rechaza la declaración.

Se inicia MQ y después Notify antes de Requests. El health de Notify acredita conexión al broker, no toda
la topología. El procedimiento de arranque, los comandos y los criterios de comprobación manual se documentan
en `apps/README.md`. Esa comprobación no se repite automáticamente durante los reinicios de Docker ni garantiza
el orden de recuperación entre servicios.

Si un exchange existente no puede enrutar un mensaje a ninguna cola, `mandatory=true` hace que RabbitMQ lo
devuelva al publicador. El callback registra exchange, routing key y `eventId` para diagnosticar el problema.
El retorno no significa procesamiento exitoso ni recupera o reenvía automáticamente el evento.

## Contrato: ACK, reintentos y DLQ (EP2-03)

Los tres consumidores de notify (email, cuadrilla y certificado) confirman igual. `AcknowledgeMode.MANUAL` en todos los listeners. El listener decide `basicAck`, `basicNack` o `basicReject`. No se usa el requeue automático de Spring.

Las DLQ no tienen consumidor. El mensaje se queda en la cola para verlo en el Management UI.

### 1. Situación y acción

| Situación | Ejemplo | Acción |
|---|---|---|
| Procesó bien | `email.admitted` y el correo quedó en el log | `basicAck` |
| `eventId` ya visto | el mismo `email.visit` llega otra vez | `basicAck`, no se reprocesa, log INFO |
| Error recuperable, aún quedan intentos | SMTP caído al enviar `email.resolved` | espera 1 s y vuelve a intentar, sin devolver el mensaje al broker |
| Error recuperable, tercer fallo | el PDF de `certificate.receipt` no se puede escribir tres veces | `basicNack(requeue=false)`. RabbitMQ lo manda a `q.cmd.certificate.dlq` |
| Error no recuperable | JSON inválido, `type` desconocido, o `email.admitted` sin `solicitanteEmail` | `basicReject(requeue=false)`, sin reintentos. Va a la DLQ de la cola que lo recibió |

El reintento es dentro del listener. No se hace `requeue=true` entre intentos: si el mensaje volviera a la cola, otro hilo podría tomarlo y el conteo se perdería.

### 2. Qué es recuperable

Recuperable, subclase de `RecoverableException`:

- El servidor de correo no acepta la conexión o corta a mitad del envío.
- Falló la escritura del PDF (disco lleno o el directorio no está disponible en ese momento).

No recuperable, subclase de `NonRecoverableException`:

- El cuerpo no es JSON o no trae el sobre (`type`, `eventId`, `payload`).
- `type` no es uno de los seis del contrato de mensajería.
- Falta un dato que el caso no puede inventar: `solicitanteEmail` en un email, `address` en `crew.ticket`.

Un dato ausente no se reintenta. Reintentar no lo hace aparecer.

### 3. Intentos y espera

Son 3 intentos en total, no 3 reintentos además del primero. Entre uno y el siguiente se espera 1 segundo, fijo. A los 3 fallos recuperables se hace `basicNack(requeue=false)`.

El prefetch es 10. Así un listener dormido en la espera no acumula toda la cola.

### 4. Log

Duplicado, en INFO:

```text
INFO duplicado cola=q.cmd.email eventId=11aa22bb-33cc-44dd-55ee-66ff77889900
```

Mensaje que va a la DLQ, en ERROR, siempre con cola, `eventId`, motivo e intentos:

```text
ERROR mensaje-muerto cola=q.cmd.email eventId=aabbccdd-eeff-4011-2233-445566778899 motivo="SMTP no responde" intentos=3
```

Si el cuerpo no se puede leer, `eventId` queda en `desconocido` e `intentos` en 0:

```text
ERROR mensaje-muerto cola=q.cmd.crew eventId=desconocido motivo="JSON invalido" intentos=0
```

`intentos` es cuántas veces se ejecutó el procesamiento. En un rechazo directo vale 0.

### 5. Idempotencia

notify guarda en memoria los `eventId` ya confirmados. Si el mismo identificador vuelve a entrar, responde `basicAck`, escribe el INFO de arriba y no manda otro correo ni otro PDF.

El conjunto vive en el proceso. Si notify se reinicia, lo olvida y puede repetir el efecto. No se comparte entre instancias.

### 6. Cómo se ve un mensaje muerto

No hay métrica automática de tasa de DLQ en esta etapa. Se mira en dos sitios:

- El log ERROR `mensaje-muerto` de notify, con la cola, el `eventId`, el motivo y los intentos.
- El Management UI, en `q.cmd.email.dlq`, `q.cmd.crew.dlq` o `q.cmd.certificate.dlq`. Esas colas no tienen consumidor, así que el mensaje permanece y se puede abrir.

## Certificados PDF y Compose (EP2-18)

Notify acepta exclusivamente `certificate.receipt` y `certificate.resolved`, con comprobante de ingreso y certificado de resolución respectivamente. `certificate.gen` sigue siendo una routing key alternativa, no un tipo de documento. Reutiliza sin cambios el sobre, ACK manual, tres intentos, DLQ y deduplicación de EP2-15.

`requestId` y `procedureType` son obligatorios, textuales y con contenido tras recortar espacios. `procedureLabel` es opcional y usa `procedureType` como respaldo. `address` es opcional y solo se muestra si tiene texto. Ausencia, null y blancos se admiten en esos opcionales; un valor no nulo y no textual se rechaza. No se usa ni valida `solicitanteEmail`, no se consulta el catálogo y `correlationId` no reemplaza `requestId`. No se exige UUID adicionalmente al parser compartido ni se modifica el payload.

El comprobante dice «Tu trámite fue registrado en BarrioDigital con estado INGRESADO.» y el certificado «Tu trámite fue marcado como RESUELTO en BarrioDigital.». Muestran el identificador completo, tipo, dirección si existe y estado correspondiente al evento. No acreditan una consulta del estado actual ni la ejecución satisfactoria de trabajos. No incluyen datos municipales inventados, firmas, sellos, folios legales, QR ni afirmaciones de validez oficial.

Al final del contenido aparecen el identificador completo del evento, su publicación cuando hay `timestamp` y la generación obtenida de un `Clock` inyectado. Ambas fechas usan `dd/MM/uuuu HH:mm:ss UTC`. El timestamp es publicación, no fecha de ingreso o resolución.

PDFBox 3.0.8 genera A4 vertical, con márgenes de 20 mm, Inter estática regular/seminegrita incrustada y la marca textual vigente del frontend. Morado `#814B8B`, texto `#252329`, secundario `#68636B` y separadores `#DDD9DF`, sobre blanco. Las fuentes Inter 4.1 oficiales, licencia OFL 1.1 y procedencia están en Notify. Ajusta líneas según métricas, divide identificadores sin truncar y pagina con cabecera compacta y pie reservado. Un carácter no representable se rechaza indicando campo y código Unicode, sin datos personales; no se elimina silenciosamente. Recursos de fuente ausentes o corruptos impiden el inicio y no son errores de payload.

`barriodigital.certificate.output-dir` se enlaza con `CERTIFICATE_OUTPUT_DIR`, con `./data/certificates` fuera de contenedores. En ambos Compose independientes de Apps se fija `/app/data/certificates` y se monta el volumen nombrado `certificates`. Recrear Notify o un `down` normal conserva los archivos; `down -v` de Apps elimina el volumen. Los archivos no se exponen por HTTP ni se adjuntan a correos.

Los nombres son `certificate-receipt-<sha256-eventId>.pdf` y `certificate-resolved-<sha256-eventId>.pdf`. SHA-256 usa el identificador completo UTF-8 del parser, sin normalizarlo. No se usan datos de negocio como rutas. El directorio se crea al guardar, se rechazan enlaces/redirecciones y el destino queda controlado dentro de él. El directorio debe permanecer bajo administración del servicio; no se garantiza protección frente a modificaciones hostiles concurrentes de sus ancestros.

La escritura usa un temporal exclusivo en el mismo directorio y publica el PDF cerrado mediante movimiento atómico. Reprocesar regenera y reemplaza la misma ruta, sin borrar primero el archivo anterior. Si falla la creación, escritura o publicación se conserva la causa en `RecoverableException`, se mantiene el archivo anterior y se intenta limpiar el temporal sin ocultar el fallo original. Si el proveedor no admite la operación atómica requerida, falla sin degradarse a copia o escritura directa. La capacidad de reemplazo se valida sobre el montaje real: las opciones de Java no garantizan idéntico comportamiento en todos los proveedores.

Tras guardar se registra un INFO `certificate-pdf` con JSON compacto que contiene tipo, eventId y nombre. Solo entonces termina el handler y EP2-15 marca y confirma. Regenerar puede cambiar la fecha. Esto no añade deduplicación persistente, exclusión entre instancias ni garantía de exactamente una ejecución. Atomicidad de publicación no equivale a durabilidad absoluta ante pérdida de energía; una caída abrupta puede dejar temporales y no se añade limpieza indiscriminada.

Local conecta Notify a Apps y a la red externa MQ, con nombres de ambos nodos. MQ debe iniciar primero, sin `depends_on` entre proyectos. EC2 usa la red Apps y exige un endpoint privado del nodo 1 mediante `RABBIT_ADDRESSES`. `RABBIT_AMQP_BIND_ADDRESS` permite publicar AMQP de MQ en su IP privada, conservando loopback por defecto. En local Management sigue en loopback. En la EC2, EP2-29 lo publica con `RABBIT_MGMT_BIND_ADDRESS=0.0.0.0` y lo cierra el security group. Logging sigue siendo el correo predeterminado; SMTP se activa por entorno.

Queda adelantado de EP2-28 el servicio Notify en los dos Compose existentes, sus variables, red local, healthcheck y volumen. No se crea un Compose de demostración ni se modifica Requests. Validación reproducible en `apps/README.md` y en el README de Notify; los resultados efectivos se registran separadamente de procedimientos pendientes.

## Contrato: API de mq-admin (EP2-04)

Endpoints de administración de RabbitMQ, definidos antes de programarlos. Los implementa `mq-admin`. El BFF es el único cliente y ya filtra por rol, pero mq-admin vuelve a comprobar `X-User-Roles` y no se publica fuera de la red interna.

En la EC2 de apps el contenedor es `bd-mq-admin` (imagen `barriodigital-apps-mq-admin:ep231`), puerto 8084 solo en la red del compose. El BFF tiene `MQ_ADMIN_BASE_URL=http://mq-admin:8084`. El Gateway llega al BFF en `/api/mq/{proxy+}`, no a mq-admin. mq-admin habla con el Management de RabbitMQ en `http://172.31.46.156:15672`; el security group de la EC2 de MQ acepta ese puerto desde el security group de apps, además del `/32` de la casa para la UI.

No hay actualizar. En RabbitMQ una cola no se edita: hay que borrarla y crearla de nuevo. Las tres operaciones son crear, eliminar y vaciar.

### 1. Endpoints

| Método | Ruta | Éxito |
|---|---|---|
| GET | `/api/mq/queues` | 200, lista |
| GET | `/api/mq/queues/{name}` | 200, una cola |
| POST | `/api/mq/queues` | 201, la cola creada |
| DELETE | `/api/mq/queues/{name}` | 204, sin cuerpo |
| DELETE | `/api/mq/queues/{name}/messages` | 204, sin cuerpo |
| POST | `/api/mq/exchanges` | 201, el exchange creado |
| DELETE | `/api/mq/exchanges/{name}` | 204, sin cuerpo |
| POST | `/api/mq/bindings` | 201, el binding creado |
| DELETE | `/api/mq/bindings` | 204, sin cuerpo. Query: `exchange`, `queue`, `routingKey` |

### 2. Cola

`GET /api/mq/queues` devuelve todas, también las de la topología. `messages` es el total (listos más sin confirmar). `consumers` es cuántos hay conectados.

```json
[
  {
    "name": "q.cmd.email",
    "messages": 2,
    "consumers": 1,
    "durable": true,
    "ttl": null,
    "deadLetterExchange": "cmd.dead.dlx",
    "deadLetterRoutingKey": "email.dead"
  }
]
```

`GET /api/mq/queues/{name}` devuelve el mismo objeto. 404 si no existe.

`POST /api/mq/queues`:

```json
{
  "name": "q.demo.avisos",
  "durable": true,
  "ttl": 60000,
  "deadLetterExchange": "cmd.dead.dlx",
  "deadLetterRoutingKey": "avisos.dead"
}
```

`durable` es opcional y vale `true` si se omite. `ttl` es opcional: si no viene, la cola no tiene `x-message-ttl`. `deadLetterExchange` y `deadLetterRoutingKey` son opcionales y se escriben como `x-dead-letter-exchange` y `x-dead-letter-routing-key`. La routing key de dead-letter solo se acepta si viene el exchange. Respuesta 201 con la misma forma del GET y `messages` y `consumers` en 0. Si el nombre ya existe, 409, aunque los argumentos coincidan.

`DELETE /api/mq/queues/{name}` borra la cola. `DELETE /api/mq/queues/{name}/messages` la vacía y no la borra. Vaciar una cola que ya está en cero también responde 204.

### 3. Exchange y binding

`POST /api/mq/exchanges`:

```json
{ "name": "demo.topic", "type": "topic", "durable": true }
```

`type` es `direct`, `topic` o `fanout`. `durable` es opcional y vale `true` si se omite. Respuesta 201 con esos tres campos. 409 si el nombre ya existe.

`POST /api/mq/bindings`:

```json
{
  "exchange": "demo.topic",
  "queue": "q.demo.avisos",
  "routingKey": "aviso.nuevo"
}
```

Respuesta 201 con el mismo cuerpo. 404 si el exchange o la cola no existen. 409 si ese binding ya existe.

`DELETE /api/mq/bindings?exchange=demo.topic&queue=q.demo.avisos&routingKey=aviso.nuevo`. Los tres parámetros van en la query. `routingKey` puede ir vacío solo si el exchange es fanout. En direct y topic, vacía es 400.

### 4. Validación

El nombre de cola, exchange y cola de un binding cumple `^[A-Za-z0-9._-]{1,100}$`. No puede empezar por `amq.`. Si no cumple, 400.

La routing key cumple `^[A-Za-z0-9._#*-]{0,100}$`. El `*` y el `#` hacen falta porque la topología usa `email.*` y `crew.#`. En direct y topic tiene que traer al menos un carácter.

`ttl` es un entero de 1 a 86400000 milisegundos (24 horas). Por encima de eso, o cero, o negativo, es 400. El tope cabe en el entero que RabbitMQ acepta para `x-message-ttl` y evita una cola de prueba con un vencimiento de años.

`deadLetterExchange`, si viene, usa la misma regla de nombre y no puede empezar por `amq.`. Puede ser `cmd.dead.dlx`: una cola nueva sí puede morir hacia el exchange del sistema. `deadLetterRoutingKey` sin exchange es 400.

El orden de las comprobaciones es: 403 si el rol no es Admin, después 400, después 404, después 409.

### 5. Recursos reservados

`cmd.*` y `q.cmd.*` son la topología de EP2-02 (`cmd.topic`, `cmd.direct`, `cmd.dead.dlx`, `q.cmd.email`, `q.cmd.crew`, `q.cmd.certificate` y las tres DLQ). No se eliminan ni se vacían. La respuesta es 409 aunque el nombre no exista: no se usa el 404 para estos prefijos.

Tampoco se crean con POST. Un nombre reservado que después no se puede borrar dejaría basura en el broker. Crear, borrar o vaciar uno de esos nombres responde 409 con el mensaje `El nombre está reservado para la topología`.

Un binding cuyo exchange empieza por `cmd.` o cuya cola empieza por `q.cmd.` tampoco se crea ni se borra: quitar `email.*` de `q.cmd.email` dejaría de enrutar los eventos. 409 con el mismo mensaje.

El prefijo `amq.` no es 409. Es nombre inválido y responde 400.

### 6. Autorización

Todos los endpoints exigen Admin. mq-admin lee `X-User-Roles` con la misma regla que catalog: el header se parte por comas, se recorta cada valor y hace falta uno igual a `Admin` o `ROLE_Admin`, sin distinguir mayúsculas. Sin header, en blanco, Vecino, Funcionario o Auditor responden 403.

```json
{
  "status": 403,
  "error": "Forbidden",
  "message": "Solo Admin puede administrar las colas"
}
```

El servicio no ve el JWT. No se publica en el API Gateway: solo lo llama el BFF, dentro de la red del compose.

### 7. Códigos por endpoint

| Endpoint | 400 | 403 | 404 | 409 |
|---|---|---|---|---|
| GET `/api/mq/queues` | | rol | | |
| GET `/api/mq/queues/{name}` | nombre inválido | rol | no existe | |
| POST `/api/mq/queues` | nombre, TTL o DLX | rol | | ya existe, o nombre reservado |
| DELETE `/api/mq/queues/{name}` | nombre inválido | rol | no existe | nombre reservado |
| DELETE `.../messages` | nombre inválido | rol | no existe | nombre reservado |
| POST `/api/mq/exchanges` | nombre o type | rol | | ya existe, o nombre reservado |
| DELETE `/api/mq/exchanges/{name}` | nombre inválido | rol | no existe | nombre reservado |
| POST `/api/mq/bindings` | nombre o routing key | rol | exchange o cola inexistente | ya existe, o recurso reservado |
| DELETE `/api/mq/bindings` | falta un parámetro, o routing key vacía en direct o topic | rol | no existe | recurso reservado |

El 200 y el 201 devuelven el recurso. El 204 no lleva cuerpo. El error lleva `status`, `error` y `message`, igual que catalog. En `application.yml` va `server.error.include-message: always` para que `message` no llegue vacío.

Mensajes:

| Caso | message |
|---|---|
| rol | `Solo Admin puede administrar las colas` |
| nombre | `El nombre no cumple el formato` |
| prefijo amq. | `El nombre no puede empezar por amq.` |
| type | `El tipo de exchange debe ser direct, topic o fanout` |
| TTL | `El TTL debe ser un entero entre 1 y 86400000` |
| DLX | `La routing key de dead-letter exige un exchange` |
| routing key | `La routing key no cumple el formato` |
| cola ausente | `La cola no existe` |
| exchange ausente | `El exchange no existe` |
| binding ausente | `El binding no existe` |
| ya existe | `La cola ya existe`, `El exchange ya existe` o `El binding ya existe` |
| reservado | `El nombre está reservado para la topología` |

### 8. OpenAPI

mq-admin publica la misma API con springdoc en `/v3/api-docs` y la UI en `/swagger-ui.html`. Cada operación lleva los ejemplos de esta sección y los códigos de la tabla. No se agrega otro endpoint fuera de esta lista.

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

**`sequence`.** Se obtiene de la columna `event_sequence` de `outbox_events`, que es identity con `ORDER` (la columna no se llama `sequence` porque es palabra clave de Oracle; EP3-02). El relay la incorpora al sobre en el momento de publicar, porque el número se conoce recién al insertar la fila en el outbox. Garantiza el orden real de los eventos de un mismo trámite (EP3-02). Los consumidores que mantienen el estado actual de un trámite ignoran un evento con `sequence` menor al último aplicado para ese trámite, sin dejar de contarlo en las métricas históricas.

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
| `request.status-changed` | Cualquier cambio de estado válido, incluidos `EN_GESTION` y `RECHAZADO` |
| `request.contact-logged` | Registro de una gestión de contacto |
| `request.assigned` | Toma, asignación o reasignación del responsable del trámite |

Una transición rechazada (409) o una operación revertida no genera evento. El evento se escribe en el outbox dentro de la misma transacción del cambio (EP3-02).

**Campos del payload:**

| Campo | Tipo | `created` | `status-changed` | `contact-logged` | `assigned` |
|---|---|---|---|---|---|
| `requestId` | uuid | No nulo | No nulo | No nulo | No nulo |
| `folio` | string | No nulo | No nulo | No nulo | No nulo |
| `procedureType` | string | No nulo | No nulo | | |
| `procedureLabel` | string | No nulo | | | |
| `sector` | string | Nulo si no se indicó | Nulo si no se indicó | | |
| `latitude`, `longitude` | número | Ambos nulos o ambos con valor | | | |
| `status` | enum | Siempre `INGRESADO` | | | |
| `slaBusinessDays` | entero | Nulo si el tipo no tiene plazo | | | |
| `fromStatus`, `toStatus` | enum | | No nulos | | |
| `reason` | string | | Con valor solo si `toStatus` es `RECHAZADO` | | Ver regla de asignación |
| `interventionReason` | string | | Nulo si el actor no es Admin | Nulo si el actor no es Admin | |
| `channel` | enum `ContactChannel` | | | No nulo | |
| `result` | enum `ContactResult` | | | No nulo | |
| `nextAttemptAt` | instant | | | Nulo si no se programó | |
| `assigneeId`, `assigneeName` | string | | | | No nulos |
| `previousAssigneeId` | string | | | | Ver regla de asignación |

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
| Gestión de contacto | `RequestActivityService.registerGestion` | `request.contact-logged` |
| Toma o reasignación | Asignación (EP3-29) | `request.assigned` |

#### 2.3 Bloqueo previo por trámite

Toda operación que genera un evento sobre un trámite **existente** toma antes el bloqueo `PESSIMISTIC_WRITE` de su fila (`findByIdForUpdate`). Así, dos operaciones sobre el mismo trámite se ejecutan una después de la otra, y la segunda recibe un `sequence` mayor.

Hoy ya lo hacen `changeStatus` y `registerGestion`. La asignación debe hacerlo también. El alta no lo necesita porque la fila es nueva.

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
| `processed_events` | report | Registros con más de 30 días |
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
| report | `processed_events` | `pk_processed_events`, clave primaria (`consumer`, `event_id`) | `consumer` VARCHAR2(40), `event_id` VARCHAR2(36), `processed_at` TIMESTAMP |
| audit | Tabla de auditoría | `uk_audit_entries_event_id`, única sobre `event_id` | La propia fila de auditoría |

En report, la fila de `processed_events` y la actualización de los KPI van en **la misma transacción**: o se cuenta el evento y se marca como procesado, o ninguna de las dos cosas. En audit, la fila de auditoría es a la vez el registro y la marca de idempotencia.

Las restricciones llevan esos nombres explícitos en el `db/schema.sql` de cada servicio.

#### 9.2 Cómo se reconoce un duplicado

Solo una violación de `pk_processed_events` o de `uk_audit_entries_event_id` se trata como duplicado. Cualquier otra violación de restricción o error de base de datos se propaga y entra al flujo de reintentos de la sección 8.

La detección ocurre **fuera** del método `@Transactional`: una excepción dentro de la transacción la marca para rollback, así que el listener la captura después de que la transacción terminó.

#### 9.3 Eventos atrasados

Un evento reprocesado desde la DLT puede llegar después de eventos más nuevos del mismo trámite.

- **report:** guarda en su proyección el último `sequence` aplicado por trámite. Un evento con `sequence` menor **no modifica** el estado actual del trámite, pero **sí cuenta** en las métricas históricas (trámites por hora, tipos más demandados).
- **audit:** guarda todos los eventos y ordena el timeline por `occurredAt`, así que el atraso no le afecta.

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
| Preferencias de aviso por correo | Sí (las propias) | Sí (las propias) | Sí (las propias) | Sí (las propias) |
| Cambiar estado y rechazar con motivo | No | Solo como responsable | Sí, con motivo | No |
| Tomar un trámite sin responsable | No | Sí | No | No |
| Asignar o reasignar | No | Solo los suyos (EP3-05) | Cualquiera | No |
| Ver la lista de funcionarios para reasignar | No | Sí | Sí | No |
| Ver el responsable | Solo si tiene, sin nombre | Sí | Sí | Sí |
| Ver el estado del plazo (listado, detalle e `/inicio`) | No | Sí | Sí | Sí |
| Administrar catálogo, cupos y plazos | No | No | Sí | No |
| Administrar la mensajería (RabbitMQ y Kafka) | No | No | Sí | No |
| Ver reportes (`/reports`) | No | No | Sí | Sí, solo lectura |
| Ver auditoría (`/audit`) | No | No | Sí | Sí |

Reglas que acompañan la matriz:

1. **El Admin no toma trámites, los asigna.** Así "Mis asignados" y los KPIs por funcionario reflejan atención y no supervisión, y la lista de reasignación de EP3-05 queda sin ambigüedad. El destinatario de una asignación tiene que ser un Funcionario de esa lista, y EP3-05 define el error. El Admin igual puede operar cualquier trámite como intervención (sección 3).
2. **El Auditor no tiene acciones.** Quien fiscaliza no opera.
3. **`/reports` es para el Admin y el Auditor.** Control interno revisa los indicadores de gestión. El Funcionario no entra a `/reports`: su vista es la bandeja, y recibe los plazos de report en el listado, el detalle e `/inicio`. Si entra EP3-62 (mapa, prioridad Media), ese contrato redefine su acceso.
4. **Adjuntar después del alta:** nadie, en la prioridad Alta. Si entra EP3-64 (prioridad Media), el Vecino agrega fotos a un trámite abierto y ese contrato agrega su fila.
5. **Funciones de prioridad Media y Baja** (comentario del vecino, cancelación, encuesta, exportación) agregan su fila en su propio contrato, si se cumple la fecha de corte del 17-nov.
6. **Solo el Vecino crea.** requests también lo comprueba (principio 2): el staff que crea un trámite recibe 403 `Solo un Vecino puede crear un tramite`.

**Rutas del frontend:**

| Ruta | Roles |
|---|---|
| `/inicio` | Los cuatro roles |
| `/tramites` y `/tramites/:id` | Los cuatro roles |
| `/admin` | Admin |
| `/reports` | Admin, Auditor |
| `/audit` | Admin, Auditor |
| Pantalla "sin acceso" | Sin rol o con más de un rol, con el motivo |

**Roles por endpoint de report y audit** (EP3-07):

| Endpoint | Roles |
|---|---|
| KPIs y tipos más demandados | Admin, Auditor |
| Plazos (vencidos y por vencer), con filtro `assignee=me` | Funcionario, Admin, Auditor |
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

| Paso | Código | Caso |
|---|---|---|
| 1 | 401 | Sin token |
| 2 | 403 | Sin rol, con más de un rol, o un rol que no opera (Vecino, Auditor) |
| 3 | 400 | Body inválido (`status`, `rejectionReason`, tamaños, `nextAttemptAt` no futura según EP3-10) e `interventionReason` ausente cuando quien llama es Admin |
| 4 | 404 | El trámite no existe, o es ajeno para el Vecino |
| 5 | 403 | Funcionario que no es el responsable, o trámite sin responsable |
| 6 | 409 | Transición no permitida, cupo agotado, o gestión en un trámite cerrado (EP3-10) |

Mantiene el orden del resto del proyecto (403, 400, 404, 409; EP2-04 y EP3-03), que es además el que impone Spring con `@Valid`. El paso 5 necesita el trámite, y en requests se evalúa dentro del bloqueo.

Un Vecino que intenta operar un trámite ajeno recibe 403 en el paso 2, antes de cualquier 404: operar ya está prohibido por rol.

**Admisión y cupo.** Para pasar a `ADMITIDO`, el BFF reserva el cupo antes de llamar a requests (EP1.5-03). Para no consumir cupo en una operación que va a fallar:

1. **El 400 del Admin sin `interventionReason`** lo responde el BFF antes del `GET`, porque depende solo del rol y del body.
2. **El 403 de no responsable** lo responde el BFF con el `GET /api/requests/{id}` que ya hace, antes de tocar catalog.
3. **`recognizedRejection` suma dos mensajes**, como red de seguridad: `Solo el responsable del tramite puede operarlo` (el caso real es una reasignación entre el `GET` y el `PUT`) e `interventionReason es obligatorio para el Admin`. Con ellos el BFF libera el cupo. Se compara por texto hasta que EP3-67 introduzca códigos estables.

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

El CSV de EP3-63 (prioridad Media) y cualquier vista futura usan las reglas de esta sección.

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

El Admin ve `/audit`, que registra sus propias acciones, y eso no debilita la segregación de funciones, porque no puede modificar lo registrado. El límite a nivel de base de datos está en la sección 10.

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
| **frontend**, `shared/models/role.ts` | `REQUESTS_ROLES` incluye los cuatro roles | EP3-49 |
| **frontend**, `app.routes.ts` y header | `/reports` y `/audit` para Admin y Auditor. Navegación del rol del usuario. Pantalla "sin acceso" con el motivo, sin rol o con más de uno | EP3-49 |
| **frontend**, detalle | Acciones por rol y por responsable, "Tomar" como acción principal, campo de motivo para el Admin, "En atención" y "Municipalidad" para el Vecino | EP3-46 |
| **frontend**, `/inicio` | Bloques de la sección 7 | EP3-52 |
| **Contratos** | EP3-05 define tomar, reasignar, la lista de funcionarios y su orden de errores. EP3-07 define los roles por endpoint de report y audit, `assignee=me` y `actorRole` | EP3-05, EP3-07 |
| **requests**, payload de RabbitMQ | `email.rejected` y los demás `email.*` no llevan `interventionReason` | EP3-33 |

### 10. Límites conocidos

1. **Ingreso asistido:** un funcionario de ventanilla u OIRS no puede ingresar un trámite a nombre de un vecino que llega en persona, aunque la Ley 19.880 lo contempla. Exige separar al solicitante del actor y capturar sus datos de contacto. Es un cambio de modelo en requests.
2. **Sin segmentación por unidad:** Entra ID entrega el rol, no la oficina ni el sector del funcionario. Todos los funcionarios ven todos los trámites de la comuna. Mejora futura: un grupo de Entra ID o un atributo por unidad.
3. **Plazo para el Vecino** (actualizado por EP3-06): ve el plazo en días hábiles (`slaBusinessDays`), no la fecha límite ni el estado del plazo, que calcula report. Mejora futura: mostrarle `dueDate` (EP3-06, límite 6).
4. **Evidencia de resolución:** el Funcionario no adjunta una foto del trabajo terminado.
5. **Colaboración entre funcionarios:** otro Funcionario no puede registrar una gestión en un trámite ajeno. El responsable reasigna, o el Admin interviene.
6. **Abstención (artículo 12 de la Ley 19.880):** la plataforma no detecta conflictos de interés. Con un rol por usuario, un Funcionario o un Admin no puede ser solicitante al crear, y el único caso posible es que el rol de un usuario cambie en Entra ID después de ingresar un trámite. Las causales de abstención dependen de la declaración del funcionario.
7. **Solo agregar a nivel de aplicación:** el usuario de Oracle que usa audit podría borrar filas técnicamente. Cerrarlo exige permisos de solo `INSERT` y `SELECT`, que no están disponibles con un solo esquema en Oracle Autonomous.
8. **Notas de las gestiones:** son texto libre y no se filtran. Pueden contener datos de contacto si el funcionario los escribe.
9. **Exposición hasta EP3-29:** mientras no se integre la proyección, `/actividad` le entrega al Vecino el nombre y el `oid` del funcionario que actuó, y el detalle y el listado entregan `solicitanteEmail` a todos los roles que ven el trámite.
10. **Un rol por usuario:** es consecuencia de que el proyecto usa un solo tenant de Entra ID para vecinos y funcionarios, como exige el caso base. En una municipalidad real, el vecino usaría una identidad ciudadana como ClaveÚnica y el funcionario su cuenta corporativa. La regla seguiría valiendo, porque serían identidades distintas. Integrar ClaveÚnica queda fuera del alcance del proyecto.

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
| 7 | 409 | Trámite en `RESUELTO` o `RECHAZADO` | `No se puede asignar un tramite cerrado` |
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

## Contrato: plazos en días hábiles (EP3-06)

Define el plazo de atención por tipo de trámite, cómo se cuenta en días hábiles, de dónde salen los feriados, los estados del plazo y cómo los calcula report. Es la base de EP3-24 (catalog), EP3-25 (BFF), EP3-31 (requests), EP3-36 y EP3-38 (report), EP3-46 y EP3-53 (frontend).

**Base legal, como fundamento de diseño:** la Ley 19.880 fija que los plazos de días son de días hábiles, y que los sábados, domingos y festivos son inhábiles (art. 25). El mismo artículo dice que los plazos se cuentan desde el día siguiente, y que una presentación electrónica en día inhábil se entiende hecha en la primera hora del primer día hábil siguiente. El art. 27 limita la duración de un procedimiento a seis meses. Este contrato aplica esas reglas por analogía al plazo de atención. No es una interpretación legal.

**Nombres:** los campos, columnas y propiedades van en inglés (convención 13 del backlog). Los valores de los enums de dominio van en español, como `RequestStatus` y `ActivityKind`.

### 1. Plazo por tipo y snapshot

#### 1.1 `slaBusinessDays` en catalog

| Regla | Valor |
|---|---|
| Rango | Entero de 1 a 120 días hábiles. El tope se ancla en el art. 27: seis meses son unos 120 a 125 días hábiles, y ningún plazo de atención debería superar la duración máxima de un procedimiento. Además evita errores de tipeo |
| `null` | Sin plazo, igual que `dailyQuota` en EP1.5-03. Un tipo nuevo, y los tipos existentes, quedan sin plazo hasta que el Admin lo defina |
| `POST` | Opcional, `null` si se omite |
| `PUT` | Reemplaza el valor completo, como el cupo: si el body no trae `slaBusinessDays`, el tipo pasa a sin plazo. El frontend envía siempre el campo. Una sola regla para todo el body es más fácil de seguir que dos |
| Quién lo edita | Solo el Admin. El orden de validación es el de catalog: 403, 400, 404. También vale para un body ilegible (sección 1.2) |
| Fuera de rango | 400 `El plazo debe ser un entero entre 1 y 120 dias habiles` |
| Auditoría | Cada cambio queda en `procedure-type.updated`, con `slaBusinessDays` en `before` y `after` (EP3-01, sección 7) |

#### 1.2 Lectura estricta del body en catalog

Jackson acepta por defecto `5.7` como 5 y `"5"` como 5. Para que un decimal o un string respondan 400, catalog configura:

```yaml
spring:
  jackson:
    deserialization:
      accept-float-as-int: false
    mapper:
      allow-coercion-of-scalars: false
```

1. **Aplica a todo catalog.** También endurece `dailyQuota` y `active`, que dejan de aceptar `"5"` y `"true"`. Cambia lo que aceptan EP1.5-02 y EP1.5-03, que llevan una nota fechada. El frontend ya envía números y booleanos (`<input type="number">` con un control `number | null`), el BFF reenvía el body como `Map<String, Object>` sin cambiar los tipos, y ningún test de catalog envía esos campos como string.
2. **Cubre números y booleanos, no texto.** `allow-coercion-of-scalars` no afecta a los campos de texto: un `label` enviado como número se sigue aceptando como texto.
3. **El 400 se arma según el campo.** `CatalogExceptionHandler` agrega un `@ExceptionHandler(HttpMessageNotReadableException.class)`, lee la ruta del campo desde la causa (`MismatchedInputException.getPath()`) y responde con el cuerpo de error de catalog (`status`, `error`, `message`):

| Campo | `message` |
|---|---|
| `slaBusinessDays` | `El plazo debe ser un entero entre 1 y 120 dias habiles` |
| `dailyQuota` | `El cupo diario debe ser un entero` |
| Cualquier otro campo, o un JSON roto | `El cuerpo de la solicitud no es valido` |

4. **El rol se revisa antes que el body.** Spring lee el body antes de que `CatalogService` compruebe el rol, así que un error de lectura llegaría antes que el 403. Para mantener el orden 403, 400, 404, el manejador revisa `X-User-Roles` con `AdminCaller.isAdmin` antes de armar el 400: si quien llama no es Admin, responde el mismo 403 que el servicio (`Solo Admin puede crear tipos de tramite` en `POST` y `Solo Admin puede editar tipos de tramite` en `PUT`).

#### 1.3 Snapshot en el alta

1. El BFF toma `slaBusinessDays` del tipo que ya valida `ProcedureTypeValidator` y lo reenvía en `X-Procedure-Sla-Days`, igual que `X-Procedure-Label`. Si el tipo no tiene plazo, el header no se envía (EP3-25).
2. requests lo guarda en el trámite, lo incluye en `request.created` y lo expone en `RequestView` para los cuatro roles (EP3-31). EP3-29 no lo expone porque la columna todavía no existe.
   - **Header inválido.** Un valor que no es un entero de 1 a 120 se guarda como `null`, con un `WARN` en el log, y el alta sigue. El BFF ya validó el rango contra catalog, así que un valor inválido sería un error del BFF, y no debe impedir que el vecino ingrese su trámite. Es la misma regla que `X-Procedure-Label` mal codificado.
3. **Editar el plazo del tipo no afecta a los trámites ya ingresados.** report calcula con el snapshot del alta. El plazo del tipo es una política de la municipalidad, y no se le cambia al vecino un compromiso ya informado.

### 2. Cómo se cuenta el plazo

#### 2.1 Desde cuándo corre

El plazo corre **desde el alta**, no desde la admisión:
- es el compromiso con el vecino, que espera desde que ingresó su solicitud;
- evita un incentivo perverso: con la admisión como inicio, demorarla detendría el reloj, y la espera por cupo agotado no contaría.

El **inicio** depende de un solo evento, `request.created`. Para detener el plazo, report usa además `request.status-changed`, ordenado por `sequence` (EP3-02, sección 9.3).

#### 2.2 Reglas de conteo

1. **El día del alta se calcula en `America/Santiago`**, desde el `occurredAt` de `request.created`. Un alta del viernes a las 22:00 en Chile ya es sábado en UTC: sin la conversión caería en un día inhábil por error. Es la misma regla del año del folio (EP3-05, sección 1.1), y `occurredAt` es el mismo instante que `created_at`.
2. **Un alta en día inhábil se entiende hecha el primer día hábil siguiente** (art. 25).
3. **El conteo parte el día hábil siguiente** al día del alta, o al día en que se entiende hecha.
4. **`dueDate` es el día hábil número N** del conteo, con N = `slaBusinessDays`. Es una fecha (`LocalDate`) en `America/Santiago`, no un instante. Como solo se cuentan días hábiles, `dueDate` siempre es hábil, y la prórroga del art. 25 cuando el último día es inhábil ocurre sola.
5. **Las reglas 2 y 3 usan el mismo calendario** de la sección 3. Nadie implementa "inhábil = sábado o domingo" en una parte y con feriados en la otra.
6. **Sin pausas.** El plazo corre en todos los estados abiertos y se detiene en `RESUELTO` o `RECHAZADO`.
7. **Se mide con la hora del hecho**, el `occurredAt`, no con la llegada a Kafka (EP3-01, sección 4). Un evento atrasado por el outbox no mueve el plazo.

Ejemplos, con un plazo de 5 días y sin feriados en esa semana:

| Alta | Día 1 | `dueDate` |
|---|---|---|
| Viernes 6-nov-2026, 10:00 | Lunes 9-nov | Viernes 13-nov |
| Sábado 7-nov-2026 (se entiende hecha el lunes 9) | Martes 10-nov | Lunes 16-nov |

#### 2.3 Cierre

Un trámite cerrado se evalúa por fecha, con la misma regla:
- **`CUMPLIDO`:** la fecha del `occurredAt` del cambio a `RESUELTO` o `RECHAZADO`, en `America/Santiago`, es igual o anterior a `dueDate`;
- **`FUERA_DE_PLAZO`:** es posterior.

Un trámite sin plazo no es ni cumplido ni fuera de plazo.

### 3. Calendario de feriados

#### 3.1 Fuente

Solo report calcula plazos, así que el calendario vive solo en report. requests y el frontend no lo necesitan: el frontend muestra lo que calcula report.

**Archivo versionado `holidays-cl.yml` en report**, cargado con `@ConfigurationProperties`. Es determinista, se prueba sin red, y la EC2 no depende de un tercero. Se descartaron una API externa (el cálculo fallaría si no responde) y una tabla editable por el Admin (suma endpoint, pantalla y auditoría, fuera de la prioridad Alta).

1. **Contenido:** los feriados nacionales de 2026 y 2027, por fecha y con su nombre.
2. **Fuente oficial:** las fechas se toman del texto legal (BCN o Diario Oficial), no de memoria ni de sitios agregadores, porque varios feriados se trasladan según el año. El archivo cita la fuente y la fecha en que se verificó.
3. **El 31 de diciembre no se incluye.** Es feriado bancario, no feriado legal, y no hace inhábil el día para la administración.
4. **Feriados regionales:** solo los que aplican a la comuna del proyecto, Alto Biobío (Región del Biobío), que es la que valida `LocationRules`. Los feriados regionales vigentes (7 de junio en Arica y Parinacota, y 20 de agosto en Chillán y Chillán Viejo) no le aplican, así que el archivo no tiene feriados regionales. Se confirma con la fuente oficial al cargar el archivo. El Día Nacional de los Pueblos Indígenas es nacional y va incluido.

#### 3.2 Años sin calendario

El cálculo depende de **todos los años que cruza el conteo**, no solo del año del alta. Con un tope de 120 días hábiles, un conteo puede pasar al año siguiente.

Si el calendario no cubre algún año del conteo:
1. ese tramo se calcula solo con sábados y domingos. Es conservador: la fecha sale igual o más temprana que la correcta, así que el aviso nunca llega tarde;
2. report registra `WARN calendario-feriados-incompleto year=2028`;
3. el health de report lo muestra en un componente informativo, como el componente `outbox` de requests, sin cambiar su estado `UP`. Report no falla al arrancar por un archivo desactualizado, porque la reportería no es el core.

#### 3.3 Recálculo al arrancar

El archivo solo cambia con un redeploy de report. Al arrancar, report **recalcula `dueDate` y `dueSoonDate` de los trámites abiertos** con el calendario cargado:
- aplica un feriado nuevo, que por el art. 25 es inhábil aunque se haya declarado después del alta;
- corrige los tramos calculados solo con fines de semana mientras faltaba un año.

**Por qué no se congela la fecha:** el plazo por tipo es una política (sección 1.3), pero un feriado es un hecho legal. Una fecha congelada que no lo descuenta queda mal según la misma norma que usa el contrato.

Los trámites **cerrados** no se recalculan: su `CUMPLIDO` o `FUERA_DE_PLAZO` ya se evaluó. El recálculo tampoco toca los trámites sin plazo: trabaja sobre el snapshot de `slaBusinessDays`, nunca sobre el plazo actual del tipo en catalog. Tampoco toca las proyecciones parciales, que no tienen fecha de alta desde donde contar (sección 5.2).

### 4. Estados del plazo

#### 4.1 `slaStatus`

Un solo campo para todo el ciclo de vida:

| Situación | `slaStatus` | Texto en pantalla | Condición, con D = fecha actual en `America/Santiago` |
|---|---|---|---|
| Abierto | `DENTRO_DE_PLAZO` | "Dentro de plazo" | D es anterior a `dueSoonDate` |
| Abierto | `POR_VENCER` | "Por vencer" | D es igual o posterior a `dueSoonDate`, e igual o anterior a `dueDate` |
| Abierto | `VENCIDO` | "Vencido" | D es posterior a `dueDate` |
| Cerrado | `CUMPLIDO` | "Cumplido" | Sección 2.3 |
| Cerrado | `FUERA_DE_PLAZO` | "Fuera de plazo" | Sección 2.3 |
| Sin plazo | `SIN_PLAZO` | "Sin plazo" | `slaBusinessDays` nulo, abierto o cerrado |

Una proyección parcial (sección 6.1) tiene `sla_status` en `null`, que significa "sin dato", distinto de `SIN_PLAZO`. EP3-07 define cómo se muestra en la API.

#### 4.2 Umbral de "por vencer"

El umbral es fijo: **2 días hábiles o menos**, contando D si es hábil y `dueDate`. Queda en configuración, `barriodigital.sla.due-soon-business-days: 2`, y el contrato fija el 2.

- **Por qué fijo:** es fácil de explicar en pantalla y da un día hábil completo de aviso antes del último. Un umbral proporcional, por ejemplo el 20 %, avisaría con 24 días de anticipación en un plazo de 120, y dejaría de ser una alerta.
- **Plazos cortos:** con `slaBusinessDays = 1`, el trámite nace `POR_VENCER`. Si entra el lunes, vence el martes, y ese mismo lunes quedan 2 días hábiles. Es correcto: ese plazo es urgente por definición.

#### 4.3 `dueSoonDate`

Para que el cálculo diario solo compare fechas, report guarda también `dueSoonDate`, la fecha en que el trámite pasa a `POR_VENCER`:

> `dueSoonDate` es el día siguiente al día hábil número (N + 1) contado hacia atrás desde `dueDate`, donde `dueDate` es el día 1 y N es `due-soon-business-days`.

Con N = 2: si `dueDate` es viernes, los días 1, 2 y 3 son viernes, jueves y miércoles, y `dueSoonDate` es el jueves. Si `dueDate` es martes, son martes, lunes y viernes, y `dueSoonDate` es el sábado; el funcionario ve el aviso el lunes.

`dueDate` y `dueSoonDate` se calculan juntos, y es el único lugar donde se usa el calendario.

#### 4.4 Nombres en report

| Campo | Columna | Contenido |
|---|---|---|
| `createdAt` | `created_at` | `occurredAt` de `request.created`. Nulo en una proyección parcial |
| `slaBusinessDays` | `sla_business_days` | Snapshot del plazo, tomado de `request.created`. Es la base del recálculo |
| `dueDate` | `due_date` | Sección 2.2 |
| `dueSoonDate` | `due_soon_date` | Sección 4.3 |
| `closedAt` | `closed_at` | `occurredAt` del cambio a `RESUELTO` o `RECHAZADO` |
| `slaStatus` | `sla_status` | Sección 4.1 |

### 5. Cálculo y concurrencia

#### 5.1 Cuándo se calcula

| Momento | Qué hace |
|---|---|
| Al proyectar `request.created` | Con plazo: calcula `dueDate`, `dueSoonDate` y `slaStatus`. Sin plazo: `SIN_PLAZO` |
| Al proyectar un cierre | Escribe `closedAt`. Si el trámite tiene `dueDate`, escribe `CUMPLIDO` o `FUERA_DE_PLAZO`. Un trámite `SIN_PLAZO` sigue en `SIN_PLAZO`, y una proyección parcial sigue con `sla_status` nulo |
| Al arrancar | Recálculo de la sección 3.3, después el `UPDATE` de estado, y recién entonces se inicia el listener |
| Todos los días a las 00:05 en `America/Santiago` | El `UPDATE` de estado |

Cumple K8: los vencimientos se calculan con un `@Scheduled`, sin evento adicional, y la API de report lee proyecciones ya materializadas.

**El `UPDATE` de estado** es una sola sentencia sobre el conjunto, sin calendario, que cubre los tres estados abiertos y es excluyente por construcción:

```sql
UPDATE report_request_projection
SET sla_status = CASE
    WHEN due_date < :hoy       THEN 'VENCIDO'
    WHEN due_soon_date <= :hoy THEN 'POR_VENCER'
    ELSE 'DENTRO_DE_PLAZO'
  END
WHERE closed_at IS NULL AND due_date IS NOT NULL
```

- `:hoy` es la fecha actual en `America/Santiago`. El nombre de la tabla es ilustrativo: lo fija EP3-36.
- **Mueve los estados en las dos direcciones.** Si el recálculo posterga `dueDate` a una fecha más tardía, por un feriado nuevo o por un año que faltaba, un trámite `VENCIDO` puede volver a `POR_VENCER` o a `DENTRO_DE_PLAZO`, y uno `POR_VENCER` puede volver a `DENTRO_DE_PLAZO`. Con una sentencia por estado, ninguna condición lo devolvería.
- `due_date IS NOT NULL` deja fuera, de forma explícita, a los trámites sin plazo y a las proyecciones parciales.

**Horario de verano:** en septiembre, Chile adelanta el reloj de las 24:00 del sábado a la 01:00 del domingo, y ese domingo no existen las 00:05. No afecta, porque ningún estado cambia en domingo: un estado solo cambia en un día cuyo día anterior fue hábil, y `VENCIDO` empieza el día siguiente a una `dueDate`, que siempre es hábil. No hace falta una segunda ejecución.

#### 5.2 Escrituras sin pérdidas

Tres procesos escriben la misma proyección: el listener, el recálculo al arrancar y el job diario. La regla es: **el listener bloquea la fila, y los procesos derivados escriben solo sus columnas.**

1. **El listener lee la proyección con `PESSIMISTIC_WRITE`** (`findByIdForUpdate`), dentro de su transacción. Al proyectar un cierre lee `dueDate` para evaluar el resultado, y solo el bloqueo protege esa lectura: si el recálculo llegó primero, el listener espera y lee la fila corregida; si el listener llegó primero, el recálculo espera. `@DynamicUpdate` no alcanza, porque no protege la lectura.
2. **El recálculo al arrancar** recorre los trámites abiertos con `created_at` y `sla_business_days` no nulos. Así deja fuera a los trámites sin plazo y a las proyecciones parciales, que no tienen desde dónde contar. Escribe con un `UPDATE` acotado por trámite (`@Modifying`), que solo toca `due_date` y `due_soon_date`, con `WHERE id = :id AND closed_at IS NULL`. **Cada trámite va en su propia transacción**, y se recorren por `id` ascendente. Va un `UPDATE` por trámite porque contar días hábiles necesita el calendario en Java.
3. **El job diario** escribe con el `UPDATE` de estado sobre el conjunto de la sección 5.1.
4. **Ningún proceso derivado lee la fila, la modifica en Java y la guarda completa.** En Oracle, un `UPDATE` que encuentra la fila cambiada por otra transacción vuelve a evaluar el `WHERE`: un trámite cerrado entremedio ya no cumple `closed_at IS NULL` y no se toca.
5. **El listener parte con `autoStartup=false`** y se inicia al terminar el recálculo y el `UPDATE` de estado. Ordena el arranque. Lo que garantiza la corrección son las reglas 1 a 4.
6. **Dos instancias** (la prueba de balanceo de EP3-36) corren las dos el recálculo y el job. No hace falta un bloqueo distribuido: el recálculo y el `UPDATE` de estado dan el mismo resultado si corren dos veces, y el bloqueo del listener cubre el recálculo de una instancia contra el listener de la otra.

#### 5.3 Deadlocks

report no tiene contadores compartidos: los KPIs son consultas agregadas sobre la proyección (EP3-07). Un ciclo de bloqueos necesita al menos dos transacciones que tengan cada una una fila y esperen la de la otra:

1. **El listener** bloquea solo la proyección de su trámite y no espera ninguna otra fila. Dos hilos nunca comparten una proyección, porque un trámite siempre cae en la misma partición.
2. **El recálculo** va un trámite por transacción (sección 5.2), así que cada transacción tiene una sola fila y no puede formar un ciclo.
3. **El `UPDATE` de estado** es el único que bloquea muchas filas en una sentencia. Con dos instancias (la prueba de balanceo de EP3-36), los dos jobs de las 00:05, o los dos arranques, pueden correr la misma sentencia a la vez y recorrer las filas en distinto orden. Si Oracle cancela una con `ORA-00060`, la sentencia completa se revierte, sin dejar nada a medias, y **se reintenta una vez**. Es seguro porque es idempotente. Si vuelve a fallar, se registra en el log y lo corrige la siguiente ejecución o el siguiente arranque.
4. **En el listener, un deadlock es recuperable** por si ocurriera. Spring traduce `ORA-00060` a una subclase de `PessimisticLockingFailureException`, y `DefaultErrorHandler` reintenta todo lo que no se registró como no recuperable, así que esa excepción **no** se registra como no recuperable.

### 6. Trámites sin plazo y trámites anteriores al outbox

#### 6.1 Trámites anteriores al outbox

report solo conoce un trámite por sus eventos, y `request.created` se registra en el outbox recién desde EP3-31. **report parte desde el despliegue:** los KPIs y los plazos cubren los trámites creados desde EP3-31, y la demo usa trámites nuevos. Se descartó un backfill de eventos sintéticos: es una issue en sí misma, toca la cadena crítica, y audit guardaría como reales eventos con un actor y una IP que no existieron.

Los trámites antiguos siguen vivos, y sus cambios posteriores sí publican eventos. Para eso, y para el `request.created` que se reprocesa desde la DLT, vale la regla de la **proyección parcial**:

1. Un evento de un trámite sin proyección **crea una proyección parcial** con lo que trae (estado actual, responsable, `sequence` y `folio`), sin datos de creación (`createdAt` nulo) y con `sla_status` nulo. No va a la DLT.
2. **Una proyección parcial no cuenta** en ningún KPI ni en los plazos.
3. **Si después llega el `request.created`** y el trámite sigue abierto, completa los datos de creación (`createdAt` y `slaBusinessDays`) y calcula `dueDate`, `dueSoonDate` y `slaStatus`, o `SIN_PLAZO` si no tiene plazo. No cambia el estado del trámite, porque su `sequence` es menor (EP3-02, sección 9.3). Desde ahí el trámite cuenta.
4. **Si la proyección parcial ya estaba cerrada** cuando llega el `created`, completa los mismos datos y evalúa de inmediato `CUMPLIDO` o `FUERA_DE_PLAZO` con la fecha de cierre ya guardada, o `SIN_PLAZO` si no tiene plazo.
5. **Un trámite antiguo nunca recibe su `created`,** así que queda parcial y fuera de los KPIs.

#### 6.2 Trámites sin plazo

Son los de tipos sin plazo y los creados antes de que el BFF reenvíe `X-Procedure-Sla-Days` (EP3-25):

1. **Se proyectan** con `dueDate` y `dueSoonDate` en `null` y `slaStatus` en `SIN_PLAZO`.
2. **No aparecen** en los listados de vencidos ni de por vencer, y el job no los toca.
3. **No cuentan en el cumplimiento:** el porcentaje se calcula con `CUMPLIDO` sobre `CUMPLIDO + FUERA_DE_PLAZO`.
4. **Definir un plazo después no les afecta**, por el snapshot. El recálculo al arrancar tampoco les calcula fechas.
5. **En pantalla**, el staff ve "Sin plazo" como texto neutro, no un estado vacío, para que no se confunda con un error de carga.

### 7. Qué ve cada rol

| Rol | Qué ve | Dónde |
|---|---|---|
| Vecino | El plazo en días, si el trámite tiene. No ve `dueDate` ni `slaStatus` | Detalle (EP3-46), con `slaBusinessDays` de `RequestView` |
| Funcionario, Admin y Auditor | `slaStatus`, `dueDate` y el plazo en días | Listado, detalle e `/inicio` (EP3-53, EP3-52) |

**Texto para el Vecino**, como plantilla:

> Plazo de atención: {slaBusinessDays} días hábiles, contados desde el día hábil siguiente al ingreso. Si ingresaste en sábado, domingo o festivo, el ingreso se considera hecho el día hábil siguiente.

- Con `slaBusinessDays = 1` va en singular: "1 día hábil".
- La segunda frase puede ir como texto secundario o en un tooltip.
- Si `slaBusinessDays` es `null`, el detalle no muestra el bloque.

La fila "Ver el estado del plazo" de la matriz de EP3-04 sigue en No para el Vecino: ve el compromiso en días, no el estado. Por eso se actualiza EP3-04, sección 6.1 (`slaBusinessDays` para los cuatro roles) y el límite 3.

### 8. Cambios en otros contratos

| Contrato | Cambio |
|---|---|
| EP1.5-02, sección 3 | Nota fechada: lectura estricta del body de catalog |
| EP1.5-03, sección 2 | Línea que remite a esa nota para `dailyQuota` |
| EP3-01, sección 6 | Los ejemplos de `request.created` y `request.status-changed` usan `sector: "ralco"` y un punto dentro de la caja de `LocationRules`. Antes usaban `Centro` y coordenadas de Viña del Mar, que el propio sistema rechaza con 400 |
| EP3-04, sección 6.1 | `folio` y `slaBusinessDays` visibles para los cuatro roles, y la nota de los campos que suma `RequestView` |
| EP3-04, límite 3 | Reescrito: el Vecino ve el plazo en días |

### 9. Cambios por capa

| Capa | Cambio | Issue |
|---|---|---|
| **catalog** | Columna `sla_business_days` nullable, `slaBusinessDays` en `ProcedureView`, POST y PUT con la sección 1.1. Lectura estricta y manejador de `HttpMessageNotReadableException` de la sección 1.2 | EP3-24 |
| **BFF** | `X-Procedure-Sla-Days` en el alta, sin header si no hay plazo | EP3-25 |
| **requests** | Columna del snapshot, `slaBusinessDays` en `request.created` y en `RequestView` | EP3-31 |
| **report**, consumidor | Proyección con `createdAt`, `slaBusinessDays` y `closedAt`, bloqueo de la proyección y proyección parcial | EP3-36 |
| **report**, plazos | Cálculo de `dueDate`, `dueSoonDate` y `slaStatus` al proyectar el alta y el cierre, `holidays-cl.yml`, recálculo al arrancar, `UPDATE` de estado al arrancar y a las 00:05 con su reintento ante deadlock, health del calendario y endpoints de plazos | EP3-38 |
| **frontend** | `slaStatus` con su texto en listado, detalle e `/inicio`. Plazo en días para el Vecino. Edición de `slaBusinessDays` por el Admin | EP3-46, EP3-52, EP3-53 |

**Tests que pide este contrato**, además de los de cada ficha:
- recálculo al arrancar: un trámite abierto calculado sin un feriado queda corregido;
- un trámite `VENCIDO` vuelve a `DENTRO_DE_PLAZO` cuando el recálculo posterga su `dueDate`;
- el job y el recálculo no tocan trámites sin plazo ni proyecciones parciales;
- proyección parcial completada por un `created` posterior, abierta y cerrada;
- lectura estricta en catalog: `"5"` y `5.7` responden 400 con su mensaje, y 403 si quien llama no es Admin.

### 10. Límites conocidos

1. **Trámites anteriores a EP3-31** (por plazo): no aparecen en los KPIs ni en los plazos, tampoco en "estados activos", aunque sigan abiertos. El timeline de audit de esos trámites empieza en el despliegue. Mejora futura: un backfill con eventos marcados como reconstruidos.
2. **Un feriado nuevo se aplica después del redeploy de report** (por diseño).
3. **Un trámite cerrado mientras faltaba un año en el calendario** conserva su evaluación, aunque se haya hecho solo con fines de semana (por diseño, para no reescribir resultados ya informados).
4. **Sin pausas** (por diseño): si el trámite espera una respuesta del vecino, por ejemplo una gestión con resultado `NO_CONTESTA`, el plazo sigue corriendo. Mejora futura: suspensión con motivo.
5. **Entre las 00:00 y las 00:05**, un trámite que acaba de vencer se ve con el estado del día anterior.
6. **El Vecino ve el plazo en días, no la fecha** (por plazo). Mejora futura: que el BFF obtenga el trámite de requests, que controla la propiedad, y después la `dueDate` de report por `requestId`.

## Contrato: APIs de report y audit (EP3-07)

Define los endpoints de solo lectura de report (`/api/report/*`) y audit (`/api/audit/*`): KPIs, plazos, timeline y búsqueda de auditoría. Es la base de EP3-35 a EP3-38 (report), EP3-39 a EP3-42 (audit), EP3-44 (BFF) y EP3-50 a EP3-53 (frontend). Parte de los endpoints del caso base (`GET /api/report/kpis?range=last24h` y `GET /api/report/top-procedures?range=last7d`), de los roles de EP3-04 y de la proyección de EP3-06.

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

`status` en `/api/report/sla`, `requestIds` en `/api/report/sla/batch` y `eventType` en `/api/audit/events` aceptan varios valores **separados por coma**, sin espacios. Un valor desconocido o mal formado responde 400, y un valor repetido también.

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
| `slaCompliance` | `{ rate, onTime, late }`. `onTime` y `late` cuentan los trámites con `closedAt` en la ventana y `slaStatus` `CUMPLIDO` o `FUERA_DE_PLAZO`. `rate` es `onTime / (onTime + late)`, con 4 decimales, o `null` si el denominador es 0. Los trámites `SIN_PLAZO` no cuentan (EP3-06, sección 6.2) |
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

1. **Se agrupa por `procedureType`.** El label es un snapshot de cada alta (EP3-01), y si el Admin renombró el tipo, los trámites tienen labels distintos. Se devuelve el `procedureLabel` del **alta más reciente dentro de la ventana**.
2. **La consulta es portable entre Oracle y H2.** La forma natural en Oracle, `MAX(...) KEEP (DENSE_RANK LAST ORDER BY created_at)`, no existe en H2, y los tests tienen que probar la misma lógica que corre en Oracle (el principio de EP3-05, sección 1.3). Se usa una subconsulta sobre el `created_at` máximo por tipo, o dos consultas.
3. **Orden:** por `count` descendente, y después por `procedureType`.

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
| `assignee` | Opcional. `me` usa el `X-User-Id` que reenvía el BFF: para el Admin y el Auditor devuelve una lista vacía, porque nunca son responsables (EP3-05, sección 8). `none` devuelve los trámites sin responsable. Otro valor, 400 |
| `page`, `size` | Sección 2.1 |

Solo considera trámites abiertos con `slaStatus` en los valores pedidos, que por construcción tienen `dueDate` (EP3-06, sección 5.1).

**Ítem:** `requestId`, `folio`, `procedureType`, `procedureLabel`, `assigneeId`, `assigneeName`, `dueDate` y `slaStatus`. El nombre del responsable viene de `request.assigned` (EP3-01). El folio basta para enlazar al detalle.

**Orden:** por `dueDate` ascendente y después por `folio`. Con los dos estados, los vencidos quedan primero, porque su `dueDate` ya pasó.

Cubre los bloques de `/inicio` de EP3-04, sección 7: el Funcionario usa `assignee=me` con los dos estados, y el Admin usa `status=VENCIDO` sin `assignee`, para toda la comuna.

#### 3.7 `GET /api/report/sla/batch`: plazos por lote

`GET /api/report/sla/batch?requestIds=<uuid>,<uuid>,...`

1. **Entrada:** de 1 a 50 UUID, sin repetir. 50 es el `size` máximo del listado de requests (EP3-30), así una página completa entra en una sola consulta. Con 50 UUID, la URL tiene menos de 2 KB.
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
| **audit**, base | Puerto 8087 | EP3-39 |
| **audit**, consumidores | Normalización de la sección 5.1, `sequence` y `summary` | EP3-40, EP3-41 |
| **audit**, API | Timeline y búsqueda (secciones 5.3 y 5.4), con la comprobación del rol y el cuerpo de error | EP3-42 |
| **BFF** | Proxy de `/api/report/**` y `/api/audit/**` con los roles de la sección 1, `REPORT_BASE_URL` y `AUDIT_BASE_URL`, y 503 si el servicio no responde | EP3-44 |
| **frontend** | Columna de plazo en el listado y el detalle, con la consulta por lote y sus tres situaciones (sección 4) | EP3-53 |
| **frontend** | Reportería con `kpis` y `top-procedures`, y "datos al" con `lastEventAt` | EP3-50 |
| **frontend** | Auditoría con la búsqueda y el timeline por folio | EP3-51 |
| **frontend** | Bloques de `/inicio` con el listado de plazos y la búsqueda de intervenciones | EP3-52 |

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

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.


