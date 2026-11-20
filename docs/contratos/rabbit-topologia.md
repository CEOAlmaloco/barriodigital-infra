<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: topología RabbitMQ (EP2-02)

Nombres que `requests`, `notify` y `mq-admin` copian a su `application.yml`. No se escriben en clases de negocio. Los `type` del contrato de mensajería (EP2-01) son las routing keys con las que publica la aplicación.

### 1. Exchanges, colas y bindings

| Exchange | Tipo | Routing key | Destino | Argumentos de la cola |
|---|---|---|---|---|
| `cmd.direct` | direct | `email.send` | `q.cmd.email` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=email.dead` |
| `cmd.topic` | topic | `email.*` | `q.cmd.email` | los mismos |
| `cmd.direct` | direct | `crew.ticket` | `q.cmd.crew` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=crew.dead` |
| `cmd.topic` | topic | `crew.#` | `q.cmd.crew` | los mismos |
| `cmd.direct` | direct | `certificate.gen` | `q.cmd.certificate` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=certificate.dead` |
| `cmd.topic` | topic | `certificate.*` | `q.cmd.certificate` | los mismos |
| `cmd.dead.dlx` | direct | `email.dead` | `q.cmd.email.dlq` | ninguno |
| `cmd.dead.dlx` | direct | `crew.dead` | `q.cmd.crew.dlq` | ninguno |
| `cmd.dead.dlx` | direct | `certificate.dead` | `q.cmd.certificate.dlq` | ninguno |

Exchanges, colas y DLQ son durables. Los mensajes se publican persistentes. Las DLQ no tienen consumidor ni dead-letter propio: un mensaje muerto se queda ahí para verlo en el Management UI.

La aplicación publica así. El otro binding de cada cola queda para probar desde el Management UI o desde mq-admin.

| type | Exchange | Routing key |
|---|---|---|
| `email.admitted`, `email.visit`, `email.resolved`, `email.rejected` | `cmd.topic` | el propio `type` |
| `crew.ticket` | `cmd.direct` | `crew.ticket` |
| `certificate.receipt`, `certificate.resolved` | `cmd.topic` | el propio `type` |

`email.admitted` calza con `email.*`. `certificate.receipt` calza con `certificate.*`. `crew.ticket` calza con el binding direct. Direct y topic quedan los dos en uso.

### 2. Nombres en YAML

Las tres aplicaciones usan las mismas claves. `requests` declara los exchanges. `notify` declara colas, DLQ y bindings. `mq-admin` lee los nombres para no permitir borrar ni vaciar `cmd.*` ni `q.cmd.*`.

```yaml
barriodigital:
  rabbit:
    exchange:
      topic: cmd.topic
      direct: cmd.direct
      dead: cmd.dead.dlx
    queue:
      email: q.cmd.email
      email-dlq: q.cmd.email.dlq
      crew: q.cmd.crew
      crew-dlq: q.cmd.crew.dlq
      certificate: q.cmd.certificate
      certificate-dlq: q.cmd.certificate.dlq
    routing:
      email-send: email.send
      email-topic: email.*
      crew-ticket: crew.ticket
      crew-topic: crew.#
      certificate-gen: certificate.gen
      certificate-topic: certificate.*
      email-dead: email.dead
      crew-dead: crew.dead
      certificate-dead: certificate.dead
```

### 3. Tipo de cola y los dos nodos

Colas clásicas durables. No quorum y no mirroring.

El clúster de la demo tiene dos nodos. Una cola quorum necesita mayoría para aceptar escrituras: con dos réplicas, si un nodo se cae no hay mayoría y la cola deja de aceptar mensajes. El mirroring de colas clásicas (`ha-mode`) está deprecado en RabbitMQ 3.12 y no se usa.

Cada cola vive en el nodo que la posee. Al reiniciar ese nodo, la cola durable y los mensajes persistentes siguen ahí. El segundo nodo cumple el clúster (los dos aparecen en `cluster_status` y en el Management UI). No replica las colas. Si el nodo dueño no vuelve, esas colas no se atienden hasta que regrese.

### 4. Bindings: los seis

Se declaran los seis bindings de las colas principales, más los tres de las DLQ. Es la tabla de la sección 9 del caso: cada cola tiene un binding direct y uno topic.

La alternativa era declarar solo el binding por el que publica la aplicación (topic para email y certificado, direct para cuadrilla). También deja direct y topic en uso, pero borra de la topología los bindings que el caso ya nombra. Se descarta.

### 5. Orden de arranque

`requests` declara `cmd.topic`, `cmd.direct` y `cmd.dead.dlx`. `notify` también declara esos exchanges,
además de las colas, DLQ y bindings, para poder iniciar sin depender de Requests. Así se evita una dependencia
circular. Las declaraciones repetidas deben tener atributos compatibles: mismo tipo, durabilidad,
auto-delete y argumentos; de lo contrario RabbitMQ rechaza la declaración.

Se inicia MQ y después Notify antes de Requests. El health de Notify acredita conexión al broker, no toda
la topología. El procedimiento de arranque, los comandos y los criterios de comprobación manual se documentan
en `apps/README.md`. Esa comprobación no se repite automáticamente durante los reinicios de Docker ni garantiza
el orden de recuperación entre servicios.

Si un exchange existente no puede enrutar un mensaje a ninguna cola, `mandatory=true` hace que RabbitMQ lo
devuelva al publicador. El callback registra exchange, routing key y `eventId` para diagnosticar el problema.
El retorno no significa procesamiento exitoso ni recupera o reenvía automáticamente el evento.
