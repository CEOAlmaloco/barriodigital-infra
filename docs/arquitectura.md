# Arquitectura EP1 — BarrioDigital

Recorte de la **Prueba 1**: login Microsoft + BFF con JWT + trámites en Oracle.  
Lo que viene en EP2 (Gateway, front en S3/Amplify) se marca como “después”.

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
    ANG[Angular + MSAL<br/>localhost:4200]
  end

  subgraph Back["EC2 / local — mundo apps"]
    BFF[ms-barriodigital-bff<br/>:8080]
    REQ[ms-barriodigital-requests<br/>:8081]
  end

  subgraph Datos["Oracle Cloud"]
    ORA[(Autonomous DB<br/>+ wallet)]
  end

  V -->|1. Login| AD
  AD -->|2. Access token JWT| ANG
  ANG -->|3. Bearer JWT| BFF
  BFF -->|4. HTTP + X-User-Id / X-User-Roles| REQ
  REQ -->|5. JDBC| ORA
```

## Flujo de una petición autenticada

```mermaid
sequenceDiagram
  actor U as Usuario
  participant M as Entra ID
  participant F as Angular + MSAL
  participant B as BFF :8080
  participant R as requests :8081
  participant O as Oracle

  U->>F: Abrir app
  F->>M: Login (Authorization Code + PKCE)
  M-->>F: Access token (iss v2, aud, roles)
  U->>F: Crear / listar trámite
  F->>B: HTTPS/HTTP + Authorization Bearer
  Note over B: Valida issuer, firma JWKS,<br/>exp, audience, roles
  alt Token inválido o ausente
    B-->>F: 401
  else Sin permiso de rol
    B-->>F: 403
  else OK
    B->>R: Proxy /api/requests<br/>headers X-User-Id, X-User-Roles
    R->>O: Persistencia JPA
    O-->>R: OK
    R-->>B: JSON
    B-->>F: 200 / 201
  end
```

## Qué valida cada capa (EP1)

| Capa | Responsabilidad |
|------|-----------------|
| **Entra ID** | Identidad, App Roles (`Admin`, `Funcionario`, `Vecino`, `Auditor`), emite JWT |
| **Angular + MSAL** | Login/logout, guarda token, manda `Authorization: Bearer` al BFF |
| **BFF** | Resource Server: issuer, audience, firma, `exp`; CORS; proxy a requests; 401/403 |
| **requests** | CRUD trámites; filtra por dueño si es Vecino; **no** valida JWT (confía en headers del BFF) |
| **Oracle** | Tabla de trámites; wallet fuera del repo |

Contrato resumido (detalle en `decisiones.md`):

- Issuer: `https://login.microsoftonline.com/<tenant>/v2.0`
- Audience: GUID del client id y/o `api://<clientId>`
- Roles en claim `roles`
- Scope API: `api://…/access_as_user`

## Qué NO entra en este dibujo (EP2+)

- **API Gateway** delante del BFF (JWT en la nube + evidencias 401/200)
- Front publicado (S3/Amplify) con redirect Entra de producción
- Catalog completo, cambio de estado avanzado, Rabbit/Kafka

En EP1 el front puede pegarle **directo al BFF** (`localhost:8080` o IP EC2). En EP2 apunta al Gateway.

## Despliegue de referencia (lab)

| Pieza | Dónde |
|-------|--------|
| BFF + requests | Docker Compose en EC2 (o local) |
| Oracle | Autonomous en OCI (no en AWS) |
| Wallet | Volumen `/wallet`, no en Git |
| Front EP1 | `ng serve` → `http://localhost:4200` |
