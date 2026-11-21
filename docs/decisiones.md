# Decisiones del proyecto

Los **contratos** viven en [`contratos/`](contratos/README.md). La **operación** del lab está en [`operacion/`](operacion/) y en los guías de la raíz de `docs/`.

Este archivo conserva solo decisiones de identidad, roles y limitaciones. **No cambia reglas de negocio** respecto al contenido anterior.

## Microsoft Entra ID: App Registration "BarrioDigital"

- Tenant ID: ce6e98c4-63f0-4b79-83e5-20925b5fada2
- Client ID (Application ID): a0773f3e-abc6-4b53-86fc-9d33a2eddef3
- Authority: https://login.microsoftonline.com/ce6e98c4-63f0-4b79-83e5-20925b5fada2/
- Application ID URI: `api://a0773f3e-abc6-4b53-86fc-9d33a2eddef3` (el `aud` real de los tokens es otro, ver "Contrato JWT")
- Redirect URIs (SPA):
  - http://localhost:4200 (desarrollo). Con este redirect el login sí entrega token.
  - https://main.db7dk8tawyzry.amplifyapp.com (Amplify del lab). Está registrado en
    la app registration: el login de Amplify cierra sin AADSTS50011. Si Entra
    volviera a responder AADSTS50011, falta ese redirect en el portal.

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

## Límites de servicios en EP3.5

EP3.5 agrega un solo servicio, `ms-barriodigital-field` (puerto 8088), porque la EC2 de apps del laboratorio no admite más (ARQ-05, E2 del backlog). Personas, partes y adjuntos quedan en requests; configuración, territorio, unidades, directorio y puntos de atención en catalog; documentos generados y notificaciones en notify, que suma base de datos. Los eventos y comandos llevan identificadores de personas, no sus datos. Contrato: [`contratos/dominio-contextos.md`](contratos/dominio-contextos.md). Identidad: [`contratos/identidad.md`](contratos/identidad.md).

## Limitaciones conocidas (no bloqueantes)

Notas de robustez detectadas durante el desarrollo, fuera de alcance de la EP1 por no representar fallas de los criterios de aceptación actuales.

### Sesión (MSAL): detectado en EP1-09

1. Múltiples cuentas en cache local. El logout de MSAL borra solo la cuenta indicada. Si alguna vez hubiera dos cuentas guardadas en `localStorage` a la vez, el guard podría tomar la cuenta restante como sesión válida tras el logout. Hoy es casi imposible llegar a este estado porque `redirectAuthenticatedGuard` impide loguearse de nuevo mientras exista sesión activa.
2. UI inconsistente si `logoutRedirect` falla por error de red. Si falla la resolución de la authority durante el logout, el usuario queda viendo el dashboard con el error solo en consola. La cache ya se limpió correctamente en ese punto, así que la siguiente navegación a una ruta protegida sí exige login (el criterio de seguridad se cumple), pero la experiencia visual queda inconsistente por un momento.
3. Sincronización entre pestañas. Al cerrar sesión en una pestaña, otras pestañas abiertas del mismo navegador siguen mostrando su estado en memoria (dashboard, etc.) hasta que el usuario navega en ellas, momento en el que el guard sí las redirige al login.
