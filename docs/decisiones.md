# Decisiones del proyecto

## Microsoft Entra ID: App Registration "BarrioDigital"

- Tenant ID: ce6e98c4-63f0-4b79-83e5-20925b5fada2
- Client ID (Application ID): a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Authority: https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/
- Application ID URI: `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3` (el `aud` real de los tokens es otro, ver "Contrato JWT")
- Redirect URIs (SPA):
  - http://localhost:4200 (desarrollo)
  - https://main.d2akoucfdwgozq.amplifyapp.com (producción, Amplify)

## Roles y usuarios de prueba

### App Roles definidos en Microsoft Entra ID
- Admin
- Funcionario
- Vecino
- Auditor

### Usuarios de prueba
| Usuario | Rol asignado |
|---|---|
| admin.test@cloudproyecto.onmicrosoft.com | Admin |
| funcionario.test@cloudproyecto.onmicrosoft.com | Funcionario |
| vecino.test@cloudproyecto.onmicrosoft.com | Vecino |
| auditor.test@cloudproyecto.onmicrosoft.com | Auditor |

## Despliegue en AWS

- BFF y ms-barriodigital-requests corren vía Docker Compose en una EC2 de AWS
  Academy Learner Lab (`apps/compose.ec2.yml`). Si se recrea la instancia cambia
  su IP pública, y hay que actualizar la integración del API Gateway hacia el BFF.
- API Gateway (HTTP API `barriodigital-api`), Invoke URL: https://dfcq1q4noj.execute-api.us-east-1.amazonaws.com
  - Reenvía al BFF en el puerto 8080 de la EC2.
  - JWT Authorizer: issuer https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/v2.0,
    audience a0773f3e-abc6-4b53-86fc-9d33a2eddef3 (sin prefijo api://, ver nota
    en "Contrato JWT" más abajo).
  - Rutas protegidas: GET /api/ping, GET/POST /api/requests, GET /api/requests/{id}.
- Frontend desplegado en AWS Amplify Hosting: https://main.d2akoucfdwgozq.amplifyapp.com
  - Deploy manual, sin repositorio Git conectado, con una regla de rewrite
    (`404-200` a `/index.html`) para las rutas de Angular.
  - Se descartó CloudFront + S3 porque cloudfront:CreateDistribution no está
    permitido en el rol del Learner Lab.
- Oracle Autonomous Database vive en OCI, no en AWS. El wallet se monta en el
  contenedor de requests como volumen (`/wallet`) y nunca va a Git.

## Contrato JWT

- Claim de rol: `roles` (estándar de Microsoft Entra ID para App Roles asignados a usuarios)
- Audience: el Application ID URI configurado es `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3`,
  pero el claim `aud` real dentro de los tokens v2 que emite Entra ID viene como
  el GUID plano (`a0773f3e-abc6-4b53-86fc-9d33a2eddef3`), sin el prefijo `api://`.
  Cualquier validador de audience (API Gateway JWT Authorizer, BFF, etc.) debe
  aceptar el GUID plano; el Application ID URI puede quedar como segundo valor
  aceptado, pero no alcanza por sí solo.
  - BFF: acepta los valores de `AZURE_AUDIENCES`, separados por coma. Su valor
    por defecto en `application.yml` es solo `api://…`, así que el `.env` (de la
    EC2 y el local) debe traer ambos:
    `AZURE_AUDIENCES=api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3,a0773f3e-abc6-4b53-86fc-9d33a2eddef3`.
    Sin el GUID, el BFF responde 401 "Audience inválido".
- Scopes: openid, profile (login básico vía MSAL)
  - Scope custom `access_as_user`: en uso desde EP1. El frontend lo solicita en el login (msal-config.ts) junto con openid/profile, para que el accessToken tenga audience hacia la API y traiga el claim `roles`.
- El BFF valida issuer, audience y firma contra el token recibido; no valida un scope custom todavía, solo el claim `roles` para autorización.

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.
