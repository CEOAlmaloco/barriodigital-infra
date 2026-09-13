# Decisiones del proyecto

## Microsoft Entra ID: App Registration "BarrioDigital"

- Tenant ID: ce6e98c4-63f0-4b79-83e5-20925b5fada2
- Client ID (Application ID): a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Authority: https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/
- Application ID URI (audience): api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Redirect URI (SPA): http://localhost:4200

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

## Contrato JWT

- Claim de rol: `roles` (estándar de Microsoft Entra ID para App Roles asignados a usuarios)
- Audience: `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3` (ver sección App Registration arriba)
- Scopes: openid, profile (login básico vía MSAL)
  - Scope custom `access_as_user`: en uso desde EP1. El frontend lo solicita en el login (msal-config.ts) junto con openid/profile, para que el accessToken tenga audience hacia la API y traiga el claim `roles`.
- El BFF valida issuer, audience y firma contra el token recibido; no valida un scope custom todavía, solo el claim `roles` para autorización.

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.