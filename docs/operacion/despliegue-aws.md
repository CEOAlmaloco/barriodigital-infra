<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Despliegue en AWS

- catalog, notify, requests, mq-admin, kafka-admin, report, audit y el BFF corren
  en la EC2 `barriodigital-apps`. La IP pública del lab cambia al recrear la
  instancia (corte EP3-13: `98.91.194.114`); hay que actualizar las integraciones
  HTTP_PROXY del API Gateway hacia `http://<IP>:8080/...`. Evidencia:
  `docs/evidencias/ep3-13-gateway-integrations.txt`.
- catalog no publica puerto: `expose: "8082"`, sin `ports`. El BFF lo llama con
  `CATALOG_BASE_URL=http://catalog:8082`. `reserve` y `release` no validan JWT
  y solo son alcanzables dentro de la red del compose.
- El orden de despliegue es catalog primero y el BFF después. El compose espera
  a que el health de catalog esté UP antes de arrancar el BFF. Si se recrea el
  BFF mientras catalog no responde, el alta de trámites responde 503.
- API Gateway (HTTP API `barriodigital-http`), Invoke URL: https://0yo277ntr8.execute-api.us-east-1.amazonaws.com
  - Reenvía al BFF en `http://<IP-pública-apps>:8080` (EC2 `barriodigital-apps`; la IP
    cambia al reiniciar el lab; corte EP3-13: `98.91.194.114`). En catalog, mq, kafka,
    report y audit la integración conserva el prefijo (`/api/catalog/{proxy}`,
    `/api/mq/{proxy}`, `/api/kafka/{proxy}`, `/api/report/{proxy}`, `/api/audit/{proxy}`):
    en esas rutas `{proxy}` es solo el resto del path.
  - JWT Authorizer `entra-jwt`: issuer https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/v2.0.
    Audiences: `a0773f3e-abc6-4b53-86fc-9d33a2eddef3` y `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3`.
  - JWT en las rutas de negocio. Sin token el Gateway responde 401. No mira el rol:
    Funcionario con token válido en `/api/mq/queues` recibe 403 del BFF
    (`No tienes el rol necesario para este recurso`). Con catalog y requests
    arriba, `POST /api/requests` por este Gateway respondió 201.
  - Todas las integraciones HTTP_PROXY al BFF mapean
    `overwrite:header.X-Source-Ip` = `$context.identity.sourceIp` (EP3-55). No se usa
    `append` ni `X-Forwarded-For` como IP de origen.
  - `GET /api/ping`, `GET /api/requests`, `POST /api/requests` y `GET /api/requests/{id}`
    siguen entrando por `GET|POST|PUT|PATCH|DELETE /{proxy+}`.
  - Rutas explícitas de EP2-30, mismo authorizer `entra-jwt`:
    - `GET`, `POST` y `PUT /api/catalog/{proxy+}`.
    - `GET /api/requests/meta/transitions` (literal, para que `{id}` no capture `meta`).
    - `PUT /api/requests/{id}/status`.
    - `GET`, `POST`, `PUT` y `DELETE /api/mq/{proxy+}`.
  - Rutas explícitas de EP3-55, mismo authorizer `entra-jwt`:
    - `GET`, `POST`, `PUT`, `PATCH` y `DELETE /api/kafka/{proxy+}`.
    - `GET /api/report/{proxy+}`.
    - `GET /api/audit/{proxy+}`.
    - `GET /api/requests/assignees` (literal, para que `{id}` no capture `assignees`).
    - `POST /api/requests/{id}/take`.
    - `PUT /api/requests/{id}/assignee`.
  - Script reproducible: `apps/scripts/ep3-55-apigw-routes.ps1`.
  - No quedó `ANY /{proxy+}`. Esa ruta también capturaba `OPTIONS` y el preflight
    respondía 401. HTTP API no tiene `**`; `{proxy+}` cubre el resto del path.
  - CORS del Gateway, sin `*`. Orígenes: `http://localhost:4200`,
    `https://main.db7dk8tawyzry.amplifyapp.com` y el sitio S3 del front de este lab.
    Métodos `GET`, `POST`, `PUT`, `PATCH`, `DELETE` y `OPTIONS`. Headers
    `authorization`, `content-type`, `x-user-id` y `x-user-roles`. El preflight lo
    responde el Gateway, sin JWT. Revisado en EP3-55; sin cambios.
- Frontend desplegado en AWS Amplify Hosting: https://main.db7dk8tawyzry.amplifyapp.com
  - App `barriodigital-front` (`db7dk8tawyzry`), rama `main`, job manual 3.
    El build publicado llama a este Gateway. Entra ya acepta el redirect de
    Amplify: con la cuenta vecino la sesión abre `/inicio` ("Hola, Vecino Test").
  - Deploy manual, sin repositorio Git conectado, con una regla de rewrite
    (`404-200` a `/index.html`) para las rutas de Angular.
  - Se descartó CloudFront + S3 porque cloudfront:CreateDistribution no está
    permitido en el rol del Learner Lab.
- Oracle Autonomous Database vive en OCI, no en AWS. El wallet se monta en los
  contenedores de requests y de catalog como volumen (`/wallet`) y nunca va a Git.
- ec2-mq es `i-0e487974a1f920449` (pública `54.81.56.155`, privada
  `172.31.46.156`). Corren `rabbitmq-1` y `rabbitmq-2`, los dos healthy, en el
  clúster `rabbit@rabbitmq-1` / `rabbit@rabbitmq-2`. AMQP `5672` está publicado
  solo en `172.31.46.156` y el security group lo admite desde el security group
  de ec2-apps. Management `15672` está en `0.0.0.0` del host y el security group
  lo admite solo desde `201.187.175.153/32`. Ninguno de los dos puertos se abre
  a `0.0.0.0/0`. notify y requests usan `RABBIT_ADDRESSES=172.31.46.156:5672`:
  hay dos conexiones del usuario `barriodigital` desde `172.31.45.131`, y
  consumidores en `q.cmd.email`, `q.cmd.crew` y `q.cmd.certificate`.
  La IP pública cambia al recrear la instancia; cómo rehacerla está en
  `mq/README.md`. En local los dos puertos siguen en `127.0.0.1`.
