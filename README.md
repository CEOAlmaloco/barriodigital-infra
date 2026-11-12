# barriodigital-infra

Infraestructura y docs del caso **BarrioDigital**.  
Tres mundos Docker (uno por EC2) + documentación compartida.

## Estructura

```text
barriodigital-infra/
├── apps/
│   ├── compose.yml      # BFF + requests + catalog + notify, repos hermanos en local
│   ├── compose.ec2.yml  # mismo stack con el layout plano de la EC2 (~/barriodigital)
│   └── .env.example     # variables que necesitan ambos compose
├── mq/                  # ec2-mq    → RabbitMQ, clúster de 2 nodos
├── kafka/                # clúster Kafka local: 3 ZK + 3 brokers + UI (EP3-14)
└── docs/                # decisiones (Entra ID, JWT, despliegue AWS) y arquitectura
```

| Carpeta | EC2 | Cuándo se llena |
|---------|-----|-----------------|
| `apps/` | ec2-apps | EP1: BFF + requests desplegados → servicios del semestre |
| `mq/` | ec2-mq | clúster RabbitMQ de 2 nodos (ver `mq/README.md`) |
| `kafka/` | local (ec2-kafka en U3) | clúster Kafka 3+3 ya definido (ver `kafka/README.md`) |
| `docs/` | — | desde EP1 (Entra ID, JWT, arquitectura, despliegue) |

`apps/` incluye BFF, requests, catalog y notify; cómo hacerlo está en `apps/README.md`.
`mq/` levanta el clúster RabbitMQ de 2 nodos; cómo hacerlo está en `mq/README.md`.  
`kafka/` levanta el clúster local de Kafka (3 Zookeeper + 3 brokers + Kafka UI); cómo hacerlo está en `kafka/README.md`.

## Cómo validar

```powershell
docker compose -f apps/compose.yml --env-file apps/.env config --quiet
docker compose -f mq/compose.yml --env-file mq/.env config --quiet
docker compose -f kafka/compose.yml --env-file kafka/.env config --quiet
```

Apps requiere `RABBIT_PASSWORD`; EC2 también exige `RABBIT_ADDRESSES`. Usar plantillas completadas fuera de Git y `config --quiet` para no imprimir secretos.
`mq/compose.yml` exige `mq/.env` (copiado de `mq/.env.example`): sin él, `config` se detiene y nombra la variable que falta.  
Kafka sigue sin `up` funcional.

## Docs

- `docs/decisiones.md` — App Registration de Entra ID, roles y usuarios de prueba, despliegue en AWS (URLs reales), contrato JWT y limitaciones conocidas
- `docs/arquitectura.md` — diagramas del flujo Amplify → API Gateway → BFF → requests → Oracle
- `docs/matriz-funcionalidades.md` — estado real de cada funcionalidad (EP1–EP3), con componente y evidencia

## Repos relacionados

- `frontend-barriodigital`
- `ms-barriodigital-bff`
- `ms-barriodigital-requests`
- `ms-barriodigital-catalog`
- `ms-barriodigital-notify`
- `ms-barriodigital-mq-admin`
- `ms-barriodigital-report` / `audit` / `kafka-admin`
