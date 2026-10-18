# mq/ — ec2-mq (RabbitMQ, 2 nodos)

Clúster local de dos nodos `rabbitmq:3.12-management-alpine`. Comparten la cookie de Erlang, cada uno tiene su volumen y el nodo 2 entra al clúster del nodo 1 por `classic_config` (`rabbitmq.conf`).

AMQP (`5672`) se publica en `RABBIT_AMQP_BIND_ADDRESS` y Management (`15672`) en `RABBIT_MGMT_BIND_ADDRESS`. Los dos valen `127.0.0.1` si no se definen. Solo el nodo 1 publica puertos; el nodo 2 no abre puertos en el host.

En la EC2 esos valores cambian y el security group es el que cierra el acceso. Los pasos para recrearla están más abajo: la IP pública del Learner Lab no se conserva. Notify remoto usa solo el AMQP del nodo 1; no hay un segundo endpoint.

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

## EC2 en el Learner Lab

Una sola instancia `ec2-mq` corre los dos contenedores. No son dos máquinas. Hace falta al menos 2 GiB: `t3.small`. Un `t2.micro` o `t3.micro` se queda sin memoria con los dos nodos y el healthcheck no llega a healthy.

Región `us-east-1`, la misma del API Gateway. AMI Amazon Linux 2023. Disco 20 GiB gp3 alcanza. Misma VPC que `ec2-apps` (en el lab, la VPC por defecto). IP pública automática: hace falta para SSH y para el Management UI. No hace falta Elastic IP; al recrear la instancia esa IP cambia y se actualiza a mano.

### Security group `barriodigital-ec2-mq`

Entrada, y nada más:

| Puerto | Origen | Para qué |
|---|---|---|
| 22 | IP pública del equipo `/32` | SSH |
| 5672 | security group de `ec2-apps` | AMQP. No una IP suelta y no `0.0.0.0/0` |
| 15672 | IP pública del equipo `/32` | Management UI |

La IP del equipo sale de `https://checkip.amazonaws.com`. Si cambia la red, se edita la regla de 22 y la de 15672. El origen de 5672 es el security group de apps, no su IP: sobrevive a que apps cambie de IP pública. Si se recrea apps con otro security group, hay que apuntar de nuevo esa regla.

Salida: la que trae el lab, para poder hacer `docker pull`.

### Instalar Docker

En la instancia, como `ec2-user`:

```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
sudo mkdir -p /usr/libexec/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose
```

Cerrar la sesión SSH y volver a entrar, para que el grupo `docker` aplique. Comprobar `docker compose version`. Amazon Linux 2023 no trae el plugin de Compose en `dnf`.

### Archivos y variables

Hace falta `mq/compose.yml`, `mq/rabbitmq.conf` y un `mq/.env` creado en la instancia. El `.env` no se copia desde git ni desde el chat.

```bash
sudo dnf install -y git
git clone --branch develop --depth 1 https://github.com/CEOAlmaloco/barriodigital-infra.git
cd barriodigital-infra
cp mq/.env.example mq/.env
```

Hasta que esta rama esté en `develop`, clonar `feature/rabbit-cluster-cloud` en lugar de `develop`. Si no, el compose sigue fijando Management en loopback y el navegador no llega.

En `mq/.env`, reemplazar password y cookie. La password es la misma que usarán requests y notify. La cookie es otra cadena, distinta de la password. Luego:

```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4
```

Esa es la IP privada. En `mq/.env`:

```text
RABBIT_AMQP_BIND_ADDRESS=<esa IP privada>
RABBIT_MGMT_BIND_ADDRESS=0.0.0.0
```

`0.0.0.0` en Management solo hace que el proceso escuche en el host. Quien puede conectarse lo decide el security group. AMQP no va en `0.0.0.0`: publicado en todas las interfaces, la IP pública también aceptaría 5672 y el security group quedaría como única barrera. Atado a la IP privada, la IP pública no tiene ese puerto.

### Levantar y comprobar

```bash
docker compose -f mq/compose.yml --env-file mq/.env up -d
docker compose -f mq/compose.yml ps
docker exec rabbitmq-1 rabbitmqctl cluster_status
```

`ps` tiene que mostrar los dos servicios healthy. En `cluster_status`, `running_nodes` lista `rabbit@rabbitmq-1` y `rabbit@rabbitmq-2`. Lo mismo en el nodo 2. El Management UI es `http://<IP pública>:15672`, con el usuario de `mq/.env`. En Overview, Nodes, se ven los dos.

No usar `down -v`. Un `up -d` después de cambiar la IP privada recrea el nodo 1 por el mapeo de puertos y el clúster vuelve a formarse con los volúmenes existentes.

### Cuando cambia la IP

Parar el lab no borra la instancia: al encenderlo de nuevo cambia la IP pública y, casi siempre, se conserva la privada.

1. Anotar la IP pública nueva en la consola EC2.
2. Si `checkip.amazonaws.com` cambió, editar en el security group el `/32` de los puertos 22 y 15672.
3. Abrir Management en `http://<IP pública nueva>:15672`.
4. En ec2-apps, `RABBITMQ_MANAGEMENT_URL` usa la IP privada, no la pública. Si la privada no cambió, no se toca.

Terminar la instancia sí cambia las dos IP. En ese caso se repite esta sección desde el security group, y además:

1. Poner la IP privada nueva en `RABBIT_AMQP_BIND_ADDRESS` y volver a hacer `docker compose up -d`.
2. En el `.env` de ec2-apps, actualizar `RABBIT_ADDRESSES` (`<IP privada>:5672`), `RABBITMQ_HOST` y `RABBITMQ_MANAGEMENT_URL` (`http://<IP privada>:15672`).
3. Si ec2-apps se recreó con otro security group, actualizar el origen de 5672.

### Evidencia

Tres capturas, sin passwords ni cookie en pantalla:

1. Consola EC2, inbound rules de `barriodigital-ec2-mq`: 5672 desde el security group de apps, 15672 desde un `/32`, ninguno desde `0.0.0.0/0`.
2. `docker compose -f mq/compose.yml ps` en la instancia, los dos nodos healthy.
3. Management UI, página Nodes, con `rabbit@rabbitmq-1` y `rabbit@rabbitmq-2`.

El `cluster_status` del apartado anterior es la comprobación de los dos nodos en CLI. Las capturas se sacan en la consola y en la instancia, sin pegarlas en git.
