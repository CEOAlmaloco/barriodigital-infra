# mq/ — ec2-mq (RabbitMQ, 2 nodos)

Clúster local de dos nodos `rabbitmq:3.12-management-alpine`. Comparten la cookie de Erlang, cada uno tiene su volumen y el nodo 2 entra al clúster del nodo 1 por `classic_config` (`rabbitmq.conf`).

AMQP (`5672`) se publica en `RABBIT_AMQP_BIND_ADDRESS`, con `127.0.0.1` por defecto. Management (`15672`) permanece en loopback. Solo el nodo 1 publica puertos; el nodo 2 no abre puertos en el host.

Para EC2-MQ configurar la IP privada de su interfaz en `RABBIT_AMQP_BIND_ADDRESS` y permitir conectividad privada desde EC2-Apps al 5672 mediante la configuración de red correspondiente. Este cambio no configura AWS ni abre Management. Notify remoto usa ese endpoint del nodo 1; no se promete un segundo endpoint.

En local Apps conecta Notify y Requests a la red `barriodigital-mq_default`, creada por este proyecto. MQ debe iniciar primero. No hace falta exponer AMQP fuera de loopback para comunicar contenedores de la misma red. Detener ambos antes de bajar MQ para liberar la red compartida.

El arranque de Apps y la comprobación manual de topología se documentan en `../apps/README.md`.

## Levantar

Desde la raíz de `barriodigital-infra`:

```powershell
copy mq\.env.example mq\.env
# editar mq\.env: usuario, password y cookie. La cookie tiene que ser la misma para los dos nodos (el compose ya la reutiliza).
docker compose -f mq/compose.yml --env-file mq/.env up -d
docker compose -f mq/compose.yml --env-file mq/.env ps
```

El `.env` no se sube a git. Sin él, Compose se detiene y pide las tres variables.

## Ver el estado

```powershell
docker exec rabbitmq-1 rabbitmqctl cluster_status
docker exec rabbitmq-2 rabbitmqctl cluster_status
```

En los dos tiene que aparecer `rabbit@rabbitmq-1` y `rabbit@rabbitmq-2` dentro de `running_nodes`.

Management: [http://127.0.0.1:15672](http://127.0.0.1:15672) con el usuario y la password de `mq/.env`. En Overview, Nodes, se ven los 2 nodos.

## Bajar

```powershell
docker compose -f mq/compose.yml --env-file mq/.env down
```

`down` para los contenedores y deja los volúmenes. Las colas durables siguen ahí al volver a levantar. `down -v` borra los volúmenes y el clúster parte de cero.

## Colas durables

Una cola durable vive en el volumen del nodo que la aloja. Reiniciar un nodo no la borra.

```powershell
# declarar (usuario y password: los de mq/.env)
curl.exe -u USUARIO:PASSWORD -H "content-type: application/json" -X PUT "http://127.0.0.1:15672/api/queues/%2F/bd.durable" -d "{\"durable\":true}"

docker restart rabbitmq-2
docker exec rabbitmq-1 rabbitmqctl list_queues name durable
```

`bd.durable` sigue en la lista, con `true` en durable. Lo mismo si el que se reinicia es `rabbitmq-1`: al volver, la cola está porque el volumen no se tocó.
