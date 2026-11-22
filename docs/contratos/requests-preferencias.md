<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: preferencias de aviso del usuario (EP3-65)

### 1. Regla

Cada usuario (clave `X-User-Id`) guarda si recibe avisos por correo. **Sin fila = habilitado** (opt-out). Si `emailEnabled` es `false`, requests **no publica** comandos `email.*` a RabbitMQ para los trámites de ese titular. Los comandos `certificate.*` (comprobante/certificado PDF) y `crew.ticket` **sí se publican**. En EP3.5, la preferencia solo apaga las comunicaciones `INFORMATIVA`: las `FORMAL` siempre se envían ([`comunicaciones.md`](comunicaciones.md), sección 4.3).

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
