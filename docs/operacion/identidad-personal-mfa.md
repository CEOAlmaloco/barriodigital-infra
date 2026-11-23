# Identidad del personal: MFA y aprobación de roles

Aplica a las cuentas con App Role `Admin`, `Funcionario` o `Auditor` en el tenant del curso (Entra ID Free).

## MFA del personal

Los valores predeterminados de seguridad (Security defaults) no bastan. Exigen MFA en cada inicio de sesión solo a los roles de directorio, como Global Administrator; al resto de las cuentas se lo piden cuando Microsoft lo estima necesario. Los App Roles de BarrioDigital no son roles de directorio ([Microsoft Learn](https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults)).

Sin licencia P1 o P2 no hay acceso condicional, así que se usa **MFA por usuario**, que pide el segundo factor en cada inicio de sesión ([Microsoft Learn](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userstates)):

1. En el centro de administración de Microsoft Entra, desactivar los valores predeterminados de seguridad. Microsoft no recomienda combinarlos con MFA por usuario.
2. En **Usuarios → MFA por usuario**, dejar en estado **Exigido** cada cuenta del personal y cada cuenta con un rol de directorio del tenant, para que no pierdan la protección que daban los valores predeterminados.
3. Al asignar un App Role de personal a una cuenta nueva, exigir MFA por usuario en la misma operación y registrarlo en la tabla de aprobaciones.

**Verificación.** En una ventana privada, iniciar sesión con cada cuenta del personal: debe pedir el segundo factor, también en el segundo intento. Se registra antes de cerrar la tarea:

| Fecha (Chile) | Cuenta | Verificó | Resultado |
|---|---|---|---|

## Aprobación de asignaciones de rol

Cada asignación o cambio de App Role queda en esta tabla, con su aprobador y la evidencia (captura o issue). Las cuentas son las de prueba del laboratorio.

| Fecha (Chile) | Cuenta | Rol asignado | Aprobado por | Evidencia |
|---|---|---|---|---|
| 2026-11-18 | admin.test@cloudproyecto.onmicrosoft.com | Admin | CEOAlmaloco | Alta inicial del laboratorio |
| 2026-11-18 | funcionario.test@cloudproyecto.onmicrosoft.com | Funcionario | CEOAlmaloco | Alta inicial del laboratorio |
| 2026-11-18 | auditor.test@cloudproyecto.onmicrosoft.com | Auditor | CEOAlmaloco | Alta inicial del laboratorio |
| 2026-11-18 | vecino.test@cloudproyecto.onmicrosoft.com | Vecino | CEOAlmaloco | Alta inicial del laboratorio |

## Revisión de accesos

| Campo | Valor |
|---|---|
| Fecha | 2026-11-18 |
| Revisó | CEOAlmaloco |
| Alcance | Cuentas de prueba del tenant del curso |
| Resultado | Cuatro cuentas, un App Role cada una, sin cuentas sin uso con rol de personal |
| Próxima revisión | Al incorporar personal o al cerrar EP3.5-13 (capacidades por rol) |

## Sesión en el frontend

- La sesión de MSAL vive en `sessionStorage` y no sobrevive al cierre del navegador.
- El inicio de sesión pide elegir la cuenta, así el siguiente usuario de un equipo compartido no entra con la cuenta anterior.
- La inactividad del personal cierra la sesión según `environment.session`, con aviso previo. La actividad cuenta en todas las pestañas, y cerrar sesión en una cierra las demás.
- Al cerrar sesión se borran los tokens, la foto y las preferencias de trabajo del usuario. Se conservan las preferencias de accesibilidad.
