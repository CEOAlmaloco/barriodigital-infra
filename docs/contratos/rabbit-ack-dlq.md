<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

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
- `type` no es uno de los siete del contrato de mensajería.
- Falta un dato que el caso no puede inventar: `solicitanteEmail` en un email, `rejectionReason` en `email.rejected` (EP3-34), `address` en `crew.ticket`.

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
