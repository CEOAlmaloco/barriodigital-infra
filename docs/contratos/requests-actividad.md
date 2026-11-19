<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: historial, gestiones, ubicación e imágenes (EP3-08 / EP1)

Contrato de corte para el expediente del trámite. Detalles de visibilidad por rol
también en EP3-04; el comentario del vecino con foto, en EP3-64.

### 1. Tabla `request_activity`

| Columna | Uso |
|---|---|
| `id`, `request_id` | Identidad del evento; hay UNIQUE `(id, request_id)` para adjuntos de comentario |
| `kind` | `CREADO`, `ESTADO`, `GESTION`, `ASIGNACION`, `COMENTARIO`, `CALIFICACION`, … |
| `visibility` | `PUBLICO` o `INTERNO` |
| `summary`, `occurred_at` | Texto y marca de tiempo informativa |
| `from_status` / `to_status` | Solo en cambios de estado |
| `actor_id`, `actor_name`, `actor_role` | Quién actuó; el hito público de asignación puede ir sin actor |
| `intervention_reason` | Motivo interno de intervención (staff); el Vecino no lo ve en `/actividad` |
| `has_attachment` | 0/1; foto ligada al evento (comentario) |
| `activity_sequence` | Orden del expediente (EP3-66); no sale en la API |

### 2. `GET /api/requests/{id}/actividad`

Devuelve el historial filtrado por rol, más `tiempos` calculables. El Vecino no
ve filas `INTERNO` ni `interventionReason`. El Gateway no tiene RouteKey literal:
entra por `GET /{proxy+}` con authorizer `entra-jwt` (evidencia EP3-13).

### 3. `POST /api/requests/{id}/gestiones`

Registra una gestión declarada (`GESTION`). Body con nota (tope 500) e
`interventionReason` cuando aplica. Roles: Funcionario responsable o Admin con
intervención (EP3-04 / EP3-05). Entra por `POST /{proxy+}` + JWT.

### 4. Ubicación (`LocationRules`)

- Dirección (`address`) obligatoria en el alta.
- `sector`: clave de Alto Biobío (`ralco`, `villa-ralco`, `pitril`, …, `otro`) o ausente.
- `latitude`/`longitude` van juntas; si vienen, deben caer en la caja de la comuna
  (lat −38.25…−37.60, lon −71.80…−71.00) y traer `locationPrecision`
  `EXACTA` o `APROXIMADA`. Fuera de la comuna → 400.

### 5. Adjuntos (imagen)

- Alta: `multipart/form-data` con parte `request` (JSON) y `attachment` opcional.
- Formatos: JPEG/PNG (WebP lo convierte el FE a PNG). No SVG.
- Límites: 5 MB; máx. 6000 px por lado / 12 MP; se reencodea y se quitan metadatos.
- `GET /api/requests/{id}/attachment`: titular o personal; otro Vecino → 404.
- Comentario con foto: EP3-64 (`/comments` y `/comments/{commentId}/attachment`).
- Gateway: `/attachment` también por `GET /{proxy+}` + JWT.

### 6. Gateway (verificación EP3-13)

Capturas en `docs/evidencias/ep3-13-gateway-*.txt`: sin token, `/actividad`,
`/gestiones` y `/attachment` responden **401** del authorizer. Con token válido
llegan al BFF vía la integración `/{proxy}`.
