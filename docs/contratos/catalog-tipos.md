<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

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
