<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: API de mq-admin (EP2-04)

Endpoints de administración de RabbitMQ, definidos antes de programarlos. Los implementa `mq-admin`. El BFF es el único cliente y ya filtra por rol, pero mq-admin vuelve a comprobar `X-User-Roles` y no se publica fuera de la red interna.

En la EC2 de apps el contenedor es `bd-mq-admin` (imagen `barriodigital-apps-mq-admin:ep231`), puerto 8084 solo en la red del compose. El BFF tiene `MQ_ADMIN_BASE_URL=http://mq-admin:8084`. El Gateway llega al BFF en `/api/mq/{proxy+}`, no a mq-admin. mq-admin habla con el Management de RabbitMQ en `http://172.31.46.156:15672`; el security group de la EC2 de MQ acepta ese puerto desde el security group de apps, además del `/32` de la casa para la UI.

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
