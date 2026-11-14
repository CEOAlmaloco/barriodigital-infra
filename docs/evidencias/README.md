# Evidencias de la demo

Respaldo del 18 de octubre de 2026, por si algo no abre en vivo.

| Archivo | Qué muestra |
|---|---|
| `gateway-authorizer.png` | Authorizer `entra-jwt` del API `barriodigital-http` (`0yo277ntr8`) |
| `gateway-rutas.png` | Rutas del Gateway, incluida `/api/mq/{proxy+}` |
| `gateway-401.png` | `GET /api/mq/queues` sin token. El Gateway responde `{"message":"Unauthorized"}` |
| `gateway-200.png` | El mismo GET con token de Admin: HTTP 200 y las seis colas. `q.cmd.email.dlq` tiene 2 mensajes |
| `entra-cuentas.png` | Admin, Funcionario y Vecino en el selector de Microsoft. Auditor no aparece: esa cuenta no había iniciado sesión en este navegador. El directorio de Entra pidió Authenticator y no se pudo abrir la lista de roles |
| `amplify-inicio.png` | Amplify en `/inicio`, sesión de Vecino Test |
| `ec2-contenedores.png` | Salida de `sudo docker ps` en `54.175.48.178`. Los cinco contenedores healthy. mq-admin publica solo `8084/tcp` |
| `rabbit-overview.png` | Dos nodos, dos conexiones, seis canales, seis colas, tres consumidores. Ready 2 |
| `rabbit-connections.png` | Las conexiones salen de `172.31.45.131`, la EC2 de apps |
| `rabbit-queues.png` | `q.cmd.email`, `q.cmd.crew` y `q.cmd.certificate`, cada una con su DLQ |
| `rabbit-exchanges.png` | `cmd.topic`, `cmd.direct` y `cmd.dead.dlx` |

Los puertos que se ven dentro del contenedor de RabbitMQ no están abiertos a internet. El security group deja el 15672 desde la IP de la casa y desde la EC2 de apps, y el 5672 solo desde apps.

## EP3-15 — ec2-kafka

| Archivo | Qué muestra |
|---|---|
| `EP3-15-ec2-kafka.md` | Resumen: instancia, SG, swap, health, memoria, checklist |
| `ec2-kafka-compose-ps.txt` | `docker compose ps` con 7 healthy |
| `ec2-kafka-memory.txt` | `free -m`, swap, `docker stats` |
| `ec2-kafka-oom.txt` | `OOMKilled=false` en los 7 |
| `ec2-kafka-instance.json` / `ec2-kafka-console-describe.txt` | Datos EC2 (consola/CLI) |
| `ec2-kafka-sg.json` / `ec2-kafka-sg-table.txt` | SG: 9092–94 desde apps; UI/SSH `/32`; sin 2181 |
| `ec2-kafka-ui.png` | Kafka UI con cluster ONLINE |

## EP3-55 — API Gateway rutas + X-Source-Ip

| Archivo | Qué muestra |
|---|---|
| `ep3-55-gateway-rutas.txt` | Rutas del HTTP API, incluidas kafka/report/audit/assignees/take/assignee |
| `ep3-55-gateway-integrations.json` | Integraciones al BFF `3.92.161.52:8080` con `overwrite:header.X-Source-Ip` |
| `ep3-55-gateway-401.txt` | Sin token: kafka/report/audit/assignees → 401 Unauthorized del Gateway |
| `ep3-55-gateway-403.txt` | Funcionario con JWT en `/api/mq/queues` → 403 del BFF |

## EP3-56 — Despliegue nube + flujo completo

| Archivo | Qué muestra |
|---|---|
| `ep3-56-topics.json` | Tópicos sistema 3p/RF3 + 3 DLT (kafka-admin) |
| `ep3-56-stack-healthy.txt` | 8 contenedores apps healthy |
| `ep3-56-flujo-tramite.txt` | create→take→admit→gestión→terreno→resuelto + KPIs |
| `ep3-56-audit-config-ip.txt` | cupo + cola en `audit.timeline` con `sourceIp` |
| `ep3-56-caos-kafka.txt` | ISR=2, outbox con brokers down, lag report, DLT, Rabbit |

Recorrido anotado: `docs/kafka.md`.

## EP3-57 — Documentación Kafka / arquitectura

| Archivo | Qué muestra |
|---|---|
| `ep3-57-prueba-uso.txt` | Recorrido de las demos de `docs/kafka.md` ejecutado en lab (corte EP3-56) |

