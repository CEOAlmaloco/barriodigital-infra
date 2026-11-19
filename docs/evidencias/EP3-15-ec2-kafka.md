# Evidencias EP3-15 — ec2-kafka en la nube

Fecha: 2026-11-10 (Learner Lab us-east-1, cuenta 515972402689)

## Instancia

| Campo | Valor |
|---|---|
| Name | `ec2-kafka` |
| InstanceId | `i-0cca16eed64db7f8e` |
| Tipo | **t3.large** (el Lab lo permitió; más holgado que t3.medium) |
| AZ | us-east-1a |
| IP privada | `172.31.0.172` |
| IP pública (sesión) | `3.239.192.62` |
| AMI | Amazon Linux 2023 `ami-09bf9dfeeb1e9adbc` |
| Key | `barriodigital-kafka-ep315` |
| SG | `barriodigital-ec2-kafka` (`sg-00799d130cf5687f4`) |

Archivos: `ec2-kafka-instance.json`, `ec2-kafka-console-describe.txt`.

## Security Group

| Puerto | Origen |
|---|---|
| 9092–9094 | solo SG apps `sg-019ac21b57f54ed7f` (`barriodigital-apps-sg`) |
| 8090 | `/32` del equipo (sesión: `201.187.174.82/32`) |
| 22 | mismo `/32` |
| 2181 | **sin regla** (Zookeeper no publicado al host) |

Archivos: `ec2-kafka-sg.json`, `ec2-kafka-sg-table.txt`.

## Swap

`/swapfile` 2G, activo y en `/etc/fstab` (persistente). Ver `ec2-kafka-memory.txt`.

## Compose — 7 contenedores healthy

Ver `ec2-kafka-compose-ps.txt`: zk-1/2/3, kafka-1/2/3, kafka-ui → **healthy**.
Zookeeper solo escucha dentro de la red Docker (no hay `0.0.0.0:2181` en el host).

## Memoria (flujo produce/consume 500 msgs)

Host t3.large ~7819 MiB. Tras carga:

- used ≈ 1842 MiB → **~23.5 %** (< 85 %)
- Swap used = 0
- OOMKilled = false en los 7 (ver `ec2-kafka-oom.txt`)
- Contenedores bajo sus `mem_limit` (brokers ~40 %, UI ~39 %, ZK ~18–20 %)

**Plan A/B:** se usó **t3.large** (permitido por el Lab). No hizo falta bajar heaps. Si en otra sesión solo hubiera t3.medium, aplicar Plan B del `kafka/README.md`.

## Kafka UI

`http://<IP_PUBLICA>:8090` — login OK, cluster `barriodigital-local` ONLINE.
Captura: `ec2-kafka-ui.png`.

## Variables de esta sesión

```
KAFKA_HOST_IP=172.31.0.172
KAFKA_BIND_ADDRESS=0.0.0.0
KAFKA_UI_BIND_ADDRESS=0.0.0.0
KAFKA_BOOTSTRAP_SERVERS=172.31.0.172:9092,172.31.0.172:9093,172.31.0.172:9094
```

## Checklist reapertura lab

1. Nueva IP privada/pública de `ec2-kafka`.
2. Actualizar `KAFKA_HOST_IP` en `~/barriodigital/kafka/.env` y `docker compose -f compose.ec2.yml --env-file .env up -d`.
3. Actualizar `KAFKA_BOOTSTRAP_SERVERS` en apps/kafka-admin.
4. SG: renovar `/32` del equipo (SSH + UI); confirmar 9092–94 solo desde SG apps; sin 2181.
5. `swapon --show`, `docker compose ps` (7 healthy), `docker stats`/`free -m` < 85 %, sin OOM.
