<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: encuesta de satisfacción (EP3-74)

### 1. Regla

Solo el **Vecino titular** califica un trámite en `RESUELTO`, **una sola vez**, con `score` entero de 1 a 5 y `comment` opcional (máximo 500). Queda en `municipal_requests.satisfaction_score` / `satisfaction_comment`, marca `CALIFICACION` en el historial y evento `request.rated` en el outbox.

### 2. Endpoint

```
POST /api/requests/{id}/rating
```

```json
{ "score": 5, "comment": "Rapido" }
```

200 con el `RequestView` actualizado (`satisfactionScore`, `satisfactionComment`). Sin comandos RabbitMQ.

### 3. Errores

| Código | Causa |
|---|---|
| 400 | falta `X-User-Id`, `score` ausente o fuera de 1..5, o `comment` > 500 |
| 403 | el rol no es Vecino, o no es el titular |
| 404 | el trámite no existe |
| 409 | el trámite no está en `RESUELTO`, o ya fue calificado |

### 4. Oracle

`ddl-auto: update` agrega las columnas. El CHECK de `request_activity.kind` debe incluir `CALIFICACION`: script `db/satisfaction-rating.sql` en requests, una vez en bases ya desplegadas.
