# barriodigital-infra

Infraestructura y docs del caso **BarrioDigital**.  
Tres mundos Docker (uno por EC2) + documentación compartida.

## Estructura

```text
barriodigital-infra/
├── apps/
│   ├── compose.yml           # stack local (repos hermanos)
│   ├── compose.ec2.yml       # layout plano EC2 (~/barriodigital) con build
│   ├── compose.ec2.jars.yml  # mismo layout con JARs precompilados (EP3-56)
│   └── .env.example
├── mq/                       # ec2-mq → RabbitMQ 2 nodos
├── kafka/                    # ec2-kafka → 3 ZK + 3 brokers + UI
└── docs/                     # decisiones, arquitectura, kafka, matriz, evidencias
```

| Carpeta | EC2 | Cuándo se llena |
|---------|-----|-----------------|
| `apps/` | ec2-apps | BFF, requests, catalog, notify, mq-admin, kafka-admin, report, audit |
| `mq/` | ec2-mq | clúster RabbitMQ (`mq/README.md`) |
| `kafka/` | ec2-kafka | clúster Kafka 3+3 + UI (`kafka/README.md`) |
| `docs/` | — | contratos, arquitectura, demos Kafka, evidencias |

`apps/README.md` describe el compose. En lab JAR usar `compose.ec2.jars.yml`.

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

Índice: [`docs/README.md`](docs/README.md) (EP3.5-01).

- `docs/decisiones.md` — Entra ID, roles de prueba y limitaciones
- `docs/contratos/` — contratos por tema (antes en `decisiones.md`)
- `docs/operacion/` — despliegue AWS y guías de operación
- `docs/arquitectura.md` — Amplify → Gateway → BFF → MS; Rabbit, Kafka, report, audit
- `docs/matriz-funcionalidades.md` — estado real vs `develop`
- `docs/evidencias/` — capturas y textos de demos

## Repos relacionados

| Repo | Puerto / rol |
|---|---|
| `frontend-barriodigital` | SPA Angular + MSAL (Amplify) |
| `ms-barriodigital-bff` | `:8080` — JWT, proxies, `X-User-*` / `X-Source-Ip` |
| `ms-barriodigital-requests` | `:8081` — trámites, outbox → Kafka, comandos Rabbit |
| `ms-barriodigital-catalog` | `:8082` — tipos y cupos; eventos a `audit.timeline` |
| `ms-barriodigital-notify` | `:8083` — email / ticket / PDF (Rabbit) |
| `ms-barriodigital-mq-admin` | `:8084` — admin Rabbit; eventos a `audit.timeline` |
| `ms-barriodigital-kafka-admin` | `:8085` — tópicos, grupos, DLT; crea tópicos sistema |
| `ms-barriodigital-report` | `:8086` — KPIs / SLA desde `requests.events` |
| `ms-barriodigital-audit` | `:8087` — auditoría / timeline (Kafka) |
| `barriodigital-infra` | este repo — compose apps/mq/kafka + docs |
