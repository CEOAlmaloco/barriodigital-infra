# barriodigital-infra

Infraestructura y docs del caso **BarrioDigital**.  
Tres mundos Docker (uno por EC2) + documentación compartida.

## Estructura

```text
barriodigital-infra/
├── apps/compose.yml    # ec2-apps  → microservicios (BFF, requests, catalog, …)
├── mq/compose.yml      # ec2-mq    → RabbitMQ (Unidad 2)
├── kafka/compose.yml   # ec2-kafka → Kafka + ZK (Unidad 3)
└── docs/               # decisiones, contratos JWT, evidencias
```

| Carpeta | EC2 | Cuándo se llena |
|---------|-----|-----------------|
| `apps/` | ec2-apps | EP1 (imágenes) → servicios del semestre |
| `mq/` | ec2-mq | Unidad 2 |
| `kafka/` | ec2-kafka | Unidad 3 |
| `docs/` | — | desde EP1 (Entra ID, JWT, arquitectura) |

Los tres `compose.yml` existen desde EP1 como **placeholders** (`services: {}`).  
Así el repo ya tiene el esqueleto del caso; no hace falta inventar nombres en EP2/EP3.

## Cómo validar (EP1)

```powershell
docker compose -f apps/compose.yml config
docker compose -f mq/compose.yml config
docker compose -f kafka/compose.yml config
```

No se espera `docker compose up` funcional de Rabbit/Kafka en EP1.

## Docs

- `docs/decisiones.md` — App Registration Entra ID (EP1-01)
- Más adelante: contrato JWT (EP1-03), notas de despliegue, etc.

## Repos relacionados

- `frontend-barriodigital`
- `ms-barriodigital-bff`
- `ms-barriodigital-requests`
- `ms-barriodigital-catalog`
- `ms-barriodigital-notify` / `report` / `audit` (U2/U3)
