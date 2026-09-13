# apps/ — ec2-apps (BFF + requests)

Compose del mundo **apps** (una EC2). Cada microservicio trae su propio `Dockerfile` en su repo.

## Local (repos hermanos)

Desde esta carpeta, con `ms-barriodigital-bff` y `ms-barriodigital-requests` al mismo nivel que `barriodigital-infra`:

```bash
cp .env.example .env   # o crea .env a mano
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

Si la password de Oracle tiene `$`, en el `.env` de Compose escríbela como `$$`.

Variables mínimas en `.env` (no subir a git):

- `AZURE_ISSUER_URI`, `AZURE_AUDIENCES`
- `ORACLE_URL`, `ORACLE_USER`, `ORACLE_PASSWORD`
- `CORS_ALLOWED_ORIGINS` (URL del front cuando exista)

Lab actual (ejemplo): BFF público `http://<IP-EC2>:8080` — la IP cambia si recreas la instancia.
