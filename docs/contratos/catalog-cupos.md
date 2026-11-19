<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

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
