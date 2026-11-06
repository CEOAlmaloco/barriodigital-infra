# kafka/ — clúster Kafka local (3 Zookeeper + 3 brokers + Kafka UI)

Compose del clúster de Kafka de BarrioDigital para desarrollo local. Reemplaza el placeholder de EP1/U3.

## Arranque

```powershell
copy .env.example .env   # ajustar KAFKA_HOST_IP a la IP LAN del PC
docker compose -f kafka/compose.yml --env-file kafka/.env up -d --wait
```

Desde la raíz del repo también vale `docker compose -f kafka/compose.yml --env-file kafka/.env ...`.

- **Brokers:** `kafka-1`, `kafka-2`, `kafka-3` (Confluent `cp-kafka:7.9.10`, con Zookeeper `cp-zookeeper:7.9.10`).
- **Zookeeper:** `zk-1`, `zk-2`, `zk-3`. Los brokers arrancan solo cuando los tres están healthy.
- **Kafka UI:** http://localhost:8090, login con `KAFKA_UI_USER`/`KAFKA_UI_PASSWORD` de `.env`.

## Puertos y listeners

| Puerto host | Broker | Uso |
|---|---|---|
| 9092 | kafka-1 | EXTERNAL del broker 1 |
| 9093 | kafka-2 | EXTERNAL del broker 2 |
| 9094 | kafka-3 | EXTERNAL del broker 3 |
| 8090 | kafka-ui | Interfaz web |

Cada broker tiene dos listeners: `INTERNAL` (9092 dentro de la red del compose, es el que usan los otros servicios y la UI) y `EXTERNAL` (el puerto publicado en el host, anunciado con `KAFKA_HOST_IP`). Para que un microservicio en Docker llegue al clúster, `KAFKA_BOOTSTRAP_SERVERS` debe usar `KAFKA_HOST_IP:9092,KAFKA_HOST_IP:9093,KAFKA_HOST_IP:9094` — `localhost` no resuelve entre contenedores de proyectos distintos.

## Configuración del broker

- `auto.create.topics.enable=false`: los tópicos se crean solo por kafka-admin (EP3-03).
- `default.replication.factor=3`, `min.insync.replicas=2`, `offsets.topic.replication.factor=3`.
- `unclean.leader.election.enable=false`: sin líder sucio; con 1 broker caído el clúster sigue escribiendo.
- Memoria acotada: `KAFKA_HEAP_OPTS=-Xmx512M` por broker, `-Xmx256M` por Zookeeper y `JAVA_OPTS=-Xmx512M` en la UI, más `mem_limit` por servicio.

## Variables (`.env`, no subir a git)

| Variable | Qué va |
|---|---|
| `KAFKA_HOST_IP` | IP del host anunciada en EXTERNAL. Local: IP LAN del PC. |
| `KAFKA_BIND_ADDRESS` | Bind del host para 9092-9094. Local: `127.0.0.1`. |
| `KAFKA_UI_BIND_ADDRESS` | Bind del host para la UI. Local: `127.0.0.1`. |
| `KAFKA_UI_USER`, `KAFKA_UI_PASSWORD` | Login de Kafka UI. |

## Comandos CLI

```bash
bash kafka/scripts/describe-topics.sh
bash kafka/scripts/consumer-groups.sh --list
bash kafka/scripts/consumer-groups.sh --describe --group <grupo>
```

Equivalente directo dentro del contenedor:

```bash
docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 --list
docker exec kafka-1 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group <grupo>
```

## Prueba de tolerancia

Con el clúster arriba:

```bash
docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 \
  --create --topic ep3-tolerancia --partitions 3 --replication-factor 3

# producir/consumir, luego detener un broker
docker stop kafka-3
# el tópico sigue escribiendo y leyendo con 2 brokers

docker start kafka-3
# esperar a que vuelva a healthy y verificar ISR
docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 \
  --describe --topic ep3-tolerancia

docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 \
  --delete --topic ep3-tolerancia
```

Resultado verificado (2026-11-06): con `kafka-3` detenido el líder de la
partición afectada pasó a otro broker del ISR, se siguieron produciendo 30
mensajes y leyendo sin pérdida; al volver `kafka-3` el ISR recuperó los 3
miembros y el tópico se eliminó.

## Escaneo de imágenes

```bash
docker scout cves --format sarif confluentinc/cp-zookeeper:7.9.10 \
  | gzip > ../docs/evidencias/kafka-confluentinc_cp-zookeeper_7.9.10.sarif.gz
docker scout cves --format sarif confluentinc/cp-kafka:7.9.10 \
  | gzip > ../docs/evidencias/kafka-confluentinc_cp-kafka_7.9.10.sarif.gz
docker scout cves --format sarif kafbat/kafka-ui:v1.5.0 \
  | gzip > ../docs/evidencias/kafka-kafbat_kafka-ui_v1.5.0.sarif.gz
```

Los `.sarif.gz` se descomprimen con `gunzip -c archivo.sarif.gz` (~4.4 MB
each).

Los tres tags son el último parche disponible (cp-kafka/cp-zookeeper `7.9.10`
dentro de la línea 7.x exigida; kafka-ui `v1.5.0`). Aun así quedan CVEs HIGH
con corrección disponible en dependencias transitivas de las imágenes
( Spring/Jackson/Netty y paquetes RPM de base); no hay tag 7.x más nuevo que
los resuelva, por lo que quedan registrados en los SARIF como riesgo
conocido a reevaluar al subir a Confluent 8.x.

## Troubleshooting

- Los Zookeeper de Confluent 7.x se configuran con `ZOOKEEPER_SERVERS`
  (lista `host:2888:3888` separada por `;`, sin prefijo `server.N=`) y
  `ZOOKEEPER_SERVER_ID`. Las variables `ZOO_SERVERS`/`ZOO_MY_ID` no aplican:
  sin ellas cada nodo arranca en modo standalone y el clúster queda partido.
- Si `/brokers/ids` muestra brokers distintos según el nodo Zookeeper
  consultado, el ensemble no formó quórum: revisar los logs de `zk-*` y
  recrear con `down -v` tras corregir la configuración.
- Kafka UI responde 401 sin login (es lo esperado con `AUTH_TYPE=LOGIN`); su
  healthcheck considera sano cualquier respuesta HTTP.
