# Arquitectura — BarrioDigital

EP1 (login → Gateway → BFF → requests → Oracle) más el recorte EP2/EP3 de mensajería: RabbitMQ, Kafka, report, audit y kafka-admin.  
URLs y contratos: `decisiones.md`. Kafka operativo: `docs/kafka.md`.

## Vista en 30 segundos

```mermaid
flowchart LR
  subgraph Usuarios
    V[Vecino / Funcionario / Admin / Auditor]
  end

  subgraph Azure["Microsoft Entra ID"]
    AD[App Registration BarrioDigital<br/>OIDC + App Roles]
  end

  subgraph Front["frontend-barriodigital"]
    ANG[Angular + MSAL<br/>Amplify Hosting]
  end

  subgraph AWS["AWS"]
    GW[API Gateway HTTP API<br/>barriodigital-http<br/>JWT Authorizer]
    subgraph Back["EC2 — mundo apps, Docker Compose"]
      BFF[ms-barriodigital-bff<br/>:8080]
      REQ[ms-barriodigital-requests<br/>:8081]
    end
  end

  subgraph Datos["Oracle Cloud"]
    ORA[(Autonomous DB<br/>+ wallet)]
  end

  V -->|1. Login| AD
  AD -->|2. Access token JWT| ANG
  ANG -->|3. HTTPS + Bearer JWT| GW
  GW -->|4. HTTP + Bearer JWT| BFF
  BFF -->|5. HTTP + X-User-Id / X-User-Roles| REQ
  REQ -->|6. JDBC| ORA
```

En desarrollo local el front corre con `ng serve` en `http://localhost:4200` y le pega directo al BFF (`http://localhost:8080`), sin Gateway.

## Flujo de una petición autenticada

```mermaid
sequenceDiagram
  actor U as Usuario
  participant M as Entra ID
  participant F as Angular + MSAL
  participant G as API Gateway
  participant B as BFF :8080
  participant R as requests :8081
  participant O as Oracle

  U->>F: Abrir app
  F->>M: Login (Authorization Code + PKCE)
  M-->>F: Access token (iss v2, aud = GUID, roles)
  U->>F: Crear / listar trámite
  F->>G: HTTPS + Authorization Bearer
  Note over G: JWT Authorizer: firma,<br/>issuer, audience, exp
  alt Token inválido o ausente
    G-->>F: 401 (no llega al BFF)
  else Token válido
    G->>B: HTTP + Authorization Bearer
    Note over B: Valida de nuevo issuer, firma JWKS,<br/>exp, audience, roles
    B->>R: Proxy /api/requests<br/>headers X-User-Id, X-User-Roles
    R->>O: Persistencia JPA
    O-->>R: OK
    R-->>B: JSON
    B-->>G: 200 / 201
    G-->>F: 200 / 201
  end
```

## Qué valida cada capa (EP1)

| Capa | Responsabilidad |
|------|-----------------|
| **Entra ID** | Identidad, App Roles (`Admin`, `Funcionario`, `Vecino`, `Auditor`), emite JWT |
| **Angular + MSAL** | Login/logout, guarda token, manda `Authorization: Bearer` al API Gateway (en local, al BFF) |
| **API Gateway** | JWT Authorizer: firma, issuer, audience (GUID) y `exp`; 401 sin llamar al BFF. Solo enruta las rutas publicadas (`decisiones.md`) |
| **BFF** | Resource Server: vuelve a validar issuer, audience, firma y `exp`; roles → 403 en `/api/admin/**`; CORS; proxy a requests |
| **requests** | CRUD trámites; filtra por dueño si es Vecino; **no** valida JWT (confía en headers del BFF) |
| **Oracle** | Tabla de trámites; wallet fuera del repo |

Contrato resumido (detalle en `decisiones.md`):

- Issuer: `https://login.microsoftonline.com/<tenant>/v2.0`
- Audience: GUID del client id (lo que traen los tokens v2); el BFF acepta además `api://<clientId>`
- Roles en claim `roles`
- Scope API: `api://…/access_as_user`

## EP2/EP3 — mensajería y proyección

```mermaid
flowchart TB
  subgraph Front["Front"]
    ANG[Angular + Amplify]
  end

  subgraph Edge["Borde"]
    GW[API Gateway<br/>entra-jwt + X-Source-Ip]
    BFF[BFF :8080<br/>JWT + proxies]
  end

  subgraph Apps["EC2 apps — Compose"]
    REQ[requests :8081]
    CAT[catalog :8082]
    NTY[notify :8083]
    MQA[mq-admin :8084]
    KAD[kafka-admin :8085]
    REP[report :8086]
    AUD[audit :8087]
  end

  subgraph MQ["EC2 mq"]
    RMQ[(RabbitMQ 2 nodos)]
  end

  subgraph KFK["EC2 kafka — 3 ZK + 3 brokers + UI"]
    KB[brokers :9092-9094]
    KUI[Kafka UI :8090]
  end

  subgraph Data["Oracle Autonomous"]
    ORA[(trámites · outbox · proyecciones · audit)]
  end

  ANG -->|Bearer JWT| GW --> BFF
  BFF -->|X-User-*| REQ & CAT & MQA & KAD & REP & AUD
  REQ --> ORA
  REQ -->|comandos email/ticket/PDF| RMQ --> NTY
  REQ -->|outbox → requests.events| KB
  CAT & MQA & KAD -->|audit.timeline| KB
  KB --> REP & AUD
  REP & AUD --> ORA
  KAD -.->|AdminClient / DLT| KB
  KUI -.-> KB
```

| Pieza | Rol |
|---|---|
| **ec2-kafka** | Clúster 3+3 + UI. Compose en `kafka/`. Sin auto-create de tópicos. |
| **kafka-admin** | Crea tópicos sistema, API Admin de tópicos/grupos/DLT, publica en `audit.timeline`. |
| **requests** | Dueño del dominio del trámite; outbox → `requests.events`; comandos a Rabbit. |
| **report** | Consume `requests.events` (`report-group`); KPIs/SLA en proyección Oracle. |
| **audit** | Consume `audit.timeline` (`audit-group`); timeline de `requests.events` según EP3-40/42. |
| **catalog / mq-admin** | Ops admin → `audit.timeline` (con `sourceIp`). |
| **notify** | Consume Rabbit (no Kafka). |

Flujo autenticado EP1 (arriba) no cambia: JWT solo en Gateway + BFF; hacia abajo `X-User-*` y, a catalog/mq/kafka-admin, `X-Source-Ip`.

## Despliegue de referencia (lab)

| Pieza | Dónde |
|-------|--------|
| Front | AWS Amplify Hosting; local `ng serve` → `http://localhost:4200` |
| API Gateway | HTTP API `barriodigital-http`, JWT Authorizer, delante del BFF |
| BFF + MS | EC2 apps: `apps/compose.ec2.yml` o layout JAR `apps/compose.ec2.jars.yml`; local `apps/compose.yml` |
| RabbitMQ | EC2 mq (`mq/compose.yml`) |
| Kafka | EC2 kafka (`kafka/compose.yml` / compose.ec2); UI `:8090` |
| Oracle | Autonomous en OCI; wallet en volumen `/wallet`, no en Git |
