# Decisiones del proyecto

## Microsoft Entra ID: App Registration "BarrioDigital"

- Tenant ID: ce6e98c4-63f0-4b79-83e5-20925b5fada2
- Client ID (Application ID): a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Authority: https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/
- Application ID URI: `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3` (el `aud` real de los tokens es otro, ver "Contrato JWT")
- Redirect URIs (SPA):
  - http://localhost:4200 (desarrollo)
  - https://main.d2akoucfdwgozq.amplifyapp.com (producción, Amplify)

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

- BFF, ms-barriodigital-requests y ms-barriodigital-catalog corren vía Docker
  Compose en una EC2 de AWS Academy Learner Lab (`apps/compose.ec2.yml`). Si se
  recrea la instancia cambia su IP pública, y hay que actualizar la integración
  del API Gateway hacia el BFF.
- catalog no publica puerto: `expose: "8082"`, sin `ports`. El BFF lo llama con
  `CATALOG_BASE_URL=http://catalog:8082`. `reserve` y `release` no validan JWT
  y solo son alcanzables dentro de la red del compose.
- El orden de despliegue es catalog primero y el BFF después. El compose espera
  a que el health de catalog esté UP antes de arrancar el BFF. Si se recrea el
  BFF mientras catalog no responde, el alta de trámites responde 503.
- API Gateway (HTTP API `barriodigital-api`), Invoke URL: https://dfcq1q4noj.execute-api.us-east-1.amazonaws.com
  - Reenvía al BFF en el puerto 8080 de la EC2.
  - JWT Authorizer: issuer https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/v2.0,
    audience a0773f3e-abc6-4b53-86fc-9d33a2eddef3 (sin prefijo api://, ver nota
    en "Contrato JWT" más abajo).
  - Rutas protegidas: GET /api/ping, GET/POST /api/requests, GET /api/requests/{id}.
- Frontend desplegado en AWS Amplify Hosting: https://main.d2akoucfdwgozq.amplifyapp.com
  - Deploy manual, sin repositorio Git conectado, con una regla de rewrite
    (`404-200` a `/index.html`) para las rutas de Angular.
  - Se descartó CloudFront + S3 porque cloudfront:CreateDistribution no está
    permitido en el rol del Learner Lab.
- Oracle Autonomous Database vive en OCI, no en AWS. El wallet se monta en los
  contenedores de requests y de catalog como volumen (`/wallet`) y nunca va a Git.

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

`requests` es quien publica y declara `cmd.topic`, `cmd.direct` y `cmd.dead.dlx`. `notify` declara colas, DLQ y bindings. Un binding no se puede crear si el exchange no existe, y `requests` no puede esperar a `notify` si `notify` a su vez espera esos exchanges: el healthcheck no llegaría nunca.

`notify` también declara los tres exchanges, de forma idempotente, y después las colas y los bindings. Así puede quedar healthy sin que `requests` haya arrancado. `requests` los vuelve a declarar al partir. Declarar dos veces el mismo exchange durable no cambia nada.

En el compose de aplicaciones, `requests` depende de `notify` con `condition: service_healthy`. El healthcheck de `notify` exige conexión al broker y la topología ya declarada.

Eso no alcanza solo. Si un mensaje sale cuando el exchange todavía no tiene bindings, RabbitMQ lo descarta sin error. La publicación usa `mandatory=true`. El callback de retorno registra en el log el mensaje devuelto: exchange, routing key y `eventId`. No se traga en silencio.

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

## Contrato: API de mq-admin (EP2-04)

Endpoints de administración de RabbitMQ, definidos antes de programarlos. Los implementa `mq-admin`. El BFF es el único cliente y ya filtra por rol, pero mq-admin vuelve a comprobar `X-User-Roles` y no se publica fuera de la red interna.

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

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.


