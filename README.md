# barriodigital-infra

Infraestructura y docs del caso **BarrioDigital**.  
Tres mundos Docker (uno por EC2) + documentación compartida.

## Estructura

```text
barriodigital-infra/
├── apps/
│   ├── compose.yml      # ec2-apps → BFF + requests, local con los repos como carpetas hermanas
│   ├── compose.ec2.yml  # mismo stack con el layout plano de la EC2 (~/barriodigital)
│   └── .env.example     # variables que necesitan ambos compose
├── mq/compose.yml       # ec2-mq    → RabbitMQ (Unidad 2)
├── kafka/compose.yml    # ec2-kafka → Kafka + ZK (Unidad 3)
└── docs/                # decisiones (Entra ID, JWT, despliegue AWS) y arquitectura
```

| Carpeta | EC2 | Cuándo se llena |
|---------|-----|-----------------|
| `apps/` | ec2-apps | EP1: BFF + requests desplegados → servicios del semestre |
| `mq/` | ec2-mq | Unidad 2 |
| `kafka/` | ec2-kafka | Unidad 3 |
| `docs/` | — | desde EP1 (Entra ID, JWT, arquitectura, despliegue) |

`apps/` ya levanta BFF + requests (EP1-24); cómo hacerlo está en `apps/README.md`.  
`mq/` y `kafka/` siguen como **placeholders** (`services: {}`) hasta U2/U3: así el repo ya tiene el esqueleto del caso y no hace falta inventar nombres después.

## Cómo validar

```powershell
docker compose -f apps/compose.yml config
docker compose -f mq/compose.yml config
docker compose -f kafka/compose.yml config
```

Sin un `.env` en `apps/`, Compose avisa que las variables vienen vacías; para validar la sintaxis es esperado.  
No se espera `docker compose up` funcional de Rabbit/Kafka en EP1.

## Docs

- `docs/decisiones.md` — App Registration de Entra ID, roles y usuarios de prueba, despliegue en AWS (URLs reales), contrato JWT y limitaciones conocidas
- `docs/arquitectura.md` — diagramas del flujo Amplify → API Gateway → BFF → requests → Oracle

## Repos relacionados

- `frontend-barriodigital`
- `ms-barriodigital-bff`
- `ms-barriodigital-requests`
- `ms-barriodigital-catalog` (pendiente)
- `ms-barriodigital-notify` / `report` / `audit` (U2/U3)
