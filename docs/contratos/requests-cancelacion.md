<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: cancelación por el vecino (EP3-76)

### 1. Decisión de estado

Se crea el estado terminal **`CANCELADO`**. No se reutiliza `RECHAZADO`: el rechazo es una decisión municipal (Funcionario/Admin) con `rejectionReason`; la cancelación es del titular y no lleva motivo.

### 2. Regla

Solo el **Vecino titular** (`solicitanteId` = `X-User-Id`) puede cancelar, y solo si el trámite está en `INGRESADO`. Cualquier otro estado responde 409. Staff y Auditor reciben 403 por rol.

### 3. Endpoint

```
POST /api/requests/{id}/cancel
```

Sin body. Responde 200 con el `RequestView` actualizado (`status: CANCELADO`). En la misma transacción: marca `ESTADO` en el historial y evento `request.cancelled` en el outbox (EP3-01 / EP3-02). No publica comandos RabbitMQ.

### 4. Errores

| Código | Causa |
|---|---|
| 400 | falta `X-User-Id` |
| 403 | el rol no es Vecino |
| 403 | el Vecino no es el titular |
| 404 | el trámite no existe |
| 409 | el trámite no está en `INGRESADO` |
