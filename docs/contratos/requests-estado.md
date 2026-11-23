<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

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

Esta tabla es la vigente. La máquina de estados de EP3.5, con la subsanación, la espera de cupo, el desistimiento, el cierre sin contacto, los duplicados, la derivación, la reapertura y los recursos, está en [`procedimiento-estados.md`](procedimiento-estados.md), y reemplaza a esta tabla a medida que la implementan EP3.5-23, 24, 30, 31, 32 y 35.

RESUELTO, RECHAZADO y CANCELADO son estados terminales, sin transiciones salientes. RECHAZADO es alcanzable desde cualquier estado no terminal vía PUT `/status`, no solo desde EN_TERRENO. CANCELADO solo se alcanza con `POST /api/requests/{id}/cancel` (EP3-76) desde INGRESADO; no entra en la tabla de este PUT. Política de cupo: el cupo diario reservado al pasar a ADMITIDO (ver contrato de EP1.5-03) nunca se libera automáticamente por un rechazo o una cancelación posterior, la orquestación de cupo de EP1.5-18 solo participa en la transición INGRESADO a ADMITIDO.

### 2. Autorización

**Actualizado el 5-nov-2026 por EP3-04.** Pueden invocar este endpoint:
- el **Funcionario responsable** del trámite (EP3-05);
- el **Admin**, como intervención, con `interventionReason` obligatorio.

Un Funcionario que no es el responsable, o un trámite sin responsable, responde 403. El Vecino y el Auditor reciben 403 por rol. Las reglas completas están en EP3-04, secciones 3 y 4.

**Actualizado por EP3-76.** El Vecino titular cancela su propio trámite solo con `POST /api/requests/{id}/cancel`, y solo en `INGRESADO`. No usa este PUT. El detalle está en el contrato de EP3-76.

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

- `status`: obligatorio, debe ser uno de los valores operables por staff (`INGRESADO`, `ADMITIDO`, `EN_GESTION`, `EN_TERRENO`, `RESUELTO`, `RECHAZADO`). `CANCELADO` no se acepta aquí: responde 400 y remite al POST de cancelación.
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
