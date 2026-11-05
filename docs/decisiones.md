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

Solo el rol Funcionario puede invocar este endpoint. 403 para cualquier otro rol, Admin incluido, Admin no tiene responsabilidad sobre el ciclo de vida del trámite según el caso base. El Vecino no puede cancelar su propio trámite en esta versión, queda fuera de alcance de EP1.5, se trataría como issue nueva si se requiere más adelante.

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
- Requiere identidad del caller vía header `X-User-Id`, mismo patrón ya usado en `create()` y `getById()`.

### 4. Respuesta en éxito

200, devuelve el recurso completo actualizado, misma forma que `GET /api/requests/{id}` (incluye `rejectionReason` cuando aplica, y `solicitanteNombre` una vez implementado EP1.5-24).

### 5. Errores

| Código | Causa |
|---|---|
| 400 | `status` ausente o no es un valor válido del enum |
| 400 | `rejectionReason` ausente o vacío cuando `status` es RECHAZADO |
| 400 | falta identidad del caller (header X-User-Id) |
| 403 | el rol del caller no es Funcionario |
| 404 | el trámite no existe |
| 409 | la transición desde el estado actual al `status` solicitado no está en la tabla del punto 1 |

### 6. Nota técnica: mensajes de error no llegaban al cliente

`application.yml` de `ms-barriodigital-requests` no tiene `server.error.include-message` seteado, el default de Spring Boot es `never`, por lo que el campo `message` del cuerpo de error venía vacío pese a que el código ya lanzaba el texto correcto. Esto afecta no solo al 409 nuevo, sino a los 400 y 404 que ya existían en `create()` y `getById()`. Se agrega `server.error.include-message: always` bajo `server:` (mismo nivel que `port`) como parte de EP1.5-04.

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
| `actor.role` | string | No | El rol que autorizó la acción |
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
| `channel` | enum `ContactChannel` | | | No nulo | |
| `result` | enum `ContactResult` | | | No nulo | |
| `nextAttemptAt` | instant | | | Nulo si no se programó | |
| `assigneeId`, `assigneeName` | string | | | | No nulos |
| `previousAssigneeId` | string | | | | Ver regla de asignación |

Notas por campo:
- **`folio`:** su formato y generación se definen en EP3-05.
- **`procedureLabel`:** es el snapshot del alta, con el respaldo de `ProcedureTypes.labelOf`.
- **`slaBusinessDays`:** es el snapshot del plazo del tipo al momento del alta. Su regla de negocio está en EP3-06.

**Regla de asignación.** Depende de si el trámite tenía responsable antes de la operación:
- **Sin responsable previo** (primera asignación): `previousAssigneeId` y `reason` van en `null`.
- **Con responsable previo** (reasignación): `previousAssigneeId` y `reason` son obligatorios.

Los permisos y el motivo se definen en EP3-05.

**Ejemplos.** El valor de `folio` sigue el formato que fije EP3-05.

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
    "sector": "Centro",
    "latitude": -33.0245,
    "longitude": -71.5518,
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
    "sector": "Centro",
    "fromStatus": "ADMITIDO",
    "toStatus": "RECHAZADO",
    "reason": "Direccion fuera de la comuna"
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
    "nextAttemptAt": "2026-11-11T13:00:00Z"
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
| `created_at` | TIMESTAMP | No | Momento de la escritura en el outbox |
| `published_at` | TIMESTAMP | Sí | `null` mientras el evento está pendiente |
| `attempts` | NUMBER | No | Envíos fallidos. Parte en 0 |
| `last_error` | VARCHAR2(500) | Sí | Último error de envío, recortado a 500 caracteres |

Índice `idx_outbox_pending` sobre (`published_at`, `event_sequence`) para leer los pendientes en orden.

La columna se llama `event_sequence` y no `sequence` porque `SEQUENCE` es palabra clave de Oracle. No es reservada, pero puede dar problemas con Hibernate al generar SQL. El campo del JSON sigue llamándose `sequence` (EP3-01).

En la entidad JPA, la clave primaria es `event_id`. `event_sequence` se mapea con `@Column(insertable = false, updatable = false)` y `@Generated`, para que Oracle lo asigne y Hibernate lo lea después del insert.

**Orden de aplicación del script.** El identity con `ORDER`, el índice y los nombres de las restricciones van en `db/schema.sql` de requests, porque `ddl-auto: update` no los crea. El script se aplica en Oracle **antes del primer arranque** de requests con esta versión. Si Hibernate crea primero la tabla, la crea sin `ORDER` y después no la modifica. En ese caso, como la tabla todavía no tiene eventos útiles, se elimina y se recrea con el script antes de publicar nada.

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

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.


