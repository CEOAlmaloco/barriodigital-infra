# apps/ — ec2-apps (BFF + requests)

Compose del mundo **apps** (una EC2). Cada microservicio trae su propio `Dockerfile` en su repo.

## Local (repos hermanos)

Desde esta carpeta, con `ms-barriodigital-bff` y `ms-barriodigital-requests` al mismo nivel que `barriodigital-infra`:

```bash
cp .env.example .env   # y completa los valores
# wallet descomprimido en ./wallet (o WALLET_HOST_PATH)
docker compose --env-file .env up -d --build
docker compose ps
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:8081/actuator/health
```

## EC2 (layout plano `~/barriodigital`)

Usar `compose.ec2.yml` cuando BFF, requests, wallet y `.env` viven juntos:

```bash
docker compose -f compose.ec2.yml --env-file .env up -d --build
```

## Variables (`.env`, no subir a git)

Plantilla en `.env.example`; los valores de Entra ID están en `../docs/decisiones.md`.

| Variable | Qué va |
|----------|--------|
| `AZURE_ISSUER_URI` | Issuer v2 del tenant |
| `AZURE_AUDIENCES` | `api://<clientId>,<clientId>`. El GUID es obligatorio: los tokens v2 lo traen en `aud` y, sin él, el BFF responde 401 "Audience inválido" |
| `ORACLE_URL` | `jdbc:oracle:thin:@barriodig_low?TNS_ADMIN=/wallet` (dentro del contenedor el wallet se monta en `/wallet`) |
| `ORACLE_USER`, `ORACLE_PASSWORD` | Usuario de la aplicación en Oracle. Si la password tiene `$`, en este `.env` va como `$$` |
| `CORS_ALLOWED_ORIGINS` | Orígenes del front separados por coma; por defecto `http://localhost:4200` |
| `WALLET_HOST_PATH` | Solo `compose.yml`: ruta del wallet en el host; por defecto `./wallet` |

## Puertos

- **BFF, 8080.** En producción el front no lo llama directo: las peticiones entran por el API Gateway, que las reenvía a este puerto (ver `../docs/decisiones.md`).
- **requests, 8081.** Los dos compose lo publican en el host (sirve para el health check local), así que en la EC2 el security group no debe abrir el 8081, solo el 8080.
