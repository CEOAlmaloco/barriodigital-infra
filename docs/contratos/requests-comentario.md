<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: comentario y fotos del vecino (EP3-64)

### 1. Regla

Solo el **Vecino titular** comenta, y solo en un trámite **abierto**: no en `RESUELTO`, `RECHAZADO` ni `CANCELADO`. Cada comentario lleva:
- `text` **obligatorio**, de 1 a 500 caracteres sin contar los espacios de los extremos;
- **una imagen opcional** JPEG o PNG, que se valida y se vuelve a codificar sin metadatos como en el alta (máximo 5 MB, 6000 px por lado y 12 MP).

Un trámite admite **20 comentarios** como máximo.

El comentario queda como marca `COMENTARIO` `PUBLICO` del historial, que ven el titular y el personal. El texto va en `note` y el `summary` es fijo: "Agregó un comentario" o "Agregó un comentario con una foto". No cambia el estado, el responsable ni los tiempos del expediente.

**Por qué el texto es obligatorio:** una foto sin contexto no le dice al funcionario qué cambió.

**Por qué hay un tope:** cada foto puede ocupar 5 MB en Oracle. Veinte comentarios bastan para aportar antecedentes y acotan el abuso.

### 2. Transacción y concurrencia

Todo ocurre en una sola transacción y después del bloqueo `PESSIMISTIC_WRITE` del trámite (EP3-02, sección 2.3): se valida el estado y el tope, y se guardan la marca, la imagen y el evento `request.citizen-comment` en el outbox. Un rechazo no deja nada.

**El tope se cuenta bajo el bloqueo.** Si un trámite tiene 19 comentarios y llegan dos a la vez, se ejecutan uno después del otro, y el segundo recibe 409.

No se publican comandos RabbitMQ: un comentario no envía correo.

### 3. Endpoints

```
POST /api/requests/{id}/comments
```

Acepta dos formatos, igual que el alta:
- `application/json`, con este cuerpo:

  ```json
  { "text": "El bache creció y ahora se acumula agua" }
  ```
- `multipart/form-data`, con la parte `comment` (el mismo JSON) y la parte opcional `attachment` (la imagen).

Responde 201 con el `ActividadView` del trámite, como `POST /gestiones`. Cada evento del historial suma `hasAttachment` (boolean), que es `true` solo en un comentario con foto.

```
GET /api/requests/{id}/comments/{commentId}/attachment
```

`commentId` es el `id` del evento en el historial. Las reglas de acceso y los headers son los de `GET /{id}/attachment`: acceden el titular y el personal, y cualquier otro Vecino recibe 404.

La imagen se devuelve solo si **el comentario pertenece a ese trámite y tiene foto**. Un `commentId` de otro trámite, uno sin foto o uno inexistente responden 404, aunque quien pide tenga acceso a los dos trámites. Oracle garantiza la misma relación con una FK compuesta (sección 5).

### 4. Errores

`POST`, en el orden en que se evalúan. La imagen se valida primero, como en el alta:

| Código | Causa |
|---|---|
| 400 / 413 | la imagen no es un JPEG o PNG válido, o excede las dimensiones (400); supera 5 MB (413) |
| 400 | falta `X-User-Id` |
| 403 | el rol no es Vecino |
| 400 | `text` vacío o de más de 500 caracteres |
| 404 | el trámite no existe |
| 403 | el Vecino no es el titular |
| 409 | el trámite está cerrado |
| 409 | el trámite ya tiene 20 comentarios |

`GET`: 400 si falta `X-User-Id`, y 404 si el trámite no existe, no es visible para quien pide, el comentario no pertenece al trámite o no tiene foto.

### 5. Oracle

El script `db/citizen-comment.sql` de requests corre **antes de desplegar** esta versión. Se puede volver a correr: crea lo que falta y se detiene ante una restricción con el nombre esperado y otra definición.
1. Amplía el CHECK de `request_activity.kind` con `COMENTARIO`.
2. Agrega `request_activity.has_attachment NUMBER(1) DEFAULT 0 NOT NULL`, con un CHECK de 0 o 1.
3. Agrega `uk_request_activity_request UNIQUE (id, request_id)`, que es el destino de la FK compuesta.
4. Crea `request_activity_attachments`:

| Columna | Tipo | Nulo | Nota |
|---|---|---|---|
| `activity_id` | VARCHAR2(36) | No | PK: una imagen por comentario |
| `request_id` | VARCHAR2(36) | No | |
| `attachment_data` | BLOB | No | La imagen ya sanitizada |
| `content_type` | VARCHAR2(30) | No | CHECK: `image/jpeg` o `image/png` |
| `file_name` | VARCHAR2(40) | No | |
| `created_at` | TIMESTAMP WITH TIME ZONE | No | |

La FK `(activity_id, request_id)` → `request_activity (id, request_id)` impide guardar una imagen con un trámite distinto al de su comentario.

**Por qué antes del despliegue:** sin el CHECK ampliado, el primer comentario falla con ORA-02290. Además, `ddl-auto: update` no crea la UNIQUE ni la FK compuesta.

La imagen del alta sigue en `municipal_request_attachments`, sin cambios.

### 6. Evento

`request.citizen-comment` lleva `requestId`, `folio` y `hasAttachment` (EP3-01, sección 6). No lleva el texto ni la imagen, por minimización (EP3-01, sección 8).

### 7. Orden de despliegue

audit y report deben soportar el tipo **antes** de que requests lo emita. Si requests se adelanta, los dos lo tratan como desconocido (EP3-01, sección 10): registran un WARN y confirman el offset. Ese evento no pasa por la DLT, así que no se puede reprocesar.

Orden:
1. Script Oracle.
2. audit y report.
3. requests.

### 8. Capas

| Capa | Cambio | Issue |
|---|---|---|
| **requests** | Endpoints, marca, imagen y evento | EP3-64 |
| **audit** | Registra `request.citizen-comment` y lo acepta en el filtro `eventType` | EP3-64 |
| **report** | Lo trata como actividad: no cambia ningún indicador (EP3-02, sección 9.3) | EP3-64 |
| **BFF** | Ruta solo para el Vecino, con el multipart y la descarga | EP3-69 |
| **frontend** | Formulario en el detalle y la foto en la línea de tiempo | EP3-71 |

### 9. Límites conocidos

1. **Sin edición ni borrado:** el historial es append-only. Un error se corrige con otro comentario.
2. **Una imagen por comentario.**
3. **Sin aviso al responsable:** el funcionario ve el comentario al abrir el trámite.
4. **El tope cuenta comentarios, no bytes:** un trámite puede llegar a 20 imágenes de 5 MB.
