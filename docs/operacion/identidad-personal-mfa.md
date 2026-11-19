# Identidad del personal: MFA y aprobación de roles (EP3.5-08 / SEG-06)

Documentación de laboratorio. **No cambia reglas de API.**

## MFA para cuentas del personal

En el tenant del curso (Entra ID Free) los **valores predeterminados de seguridad** exigen MFA. Eso cubre Admin, Funcionario y Auditor sin Acceso condicional (P1/P2 fuera de alcance).

Comprobación:

1. Portal Entra → Properties / Security defaults → **Enabled**.
2. Inicio de sesión con `funcionario.test@…`, `admin.test@…` y `auditor.test@…`: debe pedir segundo factor (app Authenticator o método registrado).
3. Una cuenta del personal **no** debe completar el login solo con contraseña.

El Vecino de prueba puede seguir el mismo tenant; el criterio de producto aplica a **personal**.

## Registro de aprobación de asignación de roles

Cada vez que se asigna o cambia un App Role en Entra ID se deja constancia en esta tabla (datos ficticios del lab):

| Fecha (Chile) | Cuenta | Rol asignado | Aprobado por | Evidencia / ticket |
|---|---|---|---|---|
| 2026-11-18 | admin.test@cloudproyecto.onmicrosoft.com | Admin | CEOAlmaloco | Alta inicial lab EP3 |
| 2026-11-18 | funcionario.test@cloudproyecto.onmicrosoft.com | Funcionario | CEOAlmaloco | Alta inicial lab EP3 |
| 2026-11-18 | auditor.test@cloudproyecto.onmicrosoft.com | Auditor | CEOAlmaloco | Alta inicial lab EP3 |
| 2026-11-18 | vecino.test@cloudproyecto.onmicrosoft.com | Vecino | CEOAlmaloco | Alta inicial lab EP3 |

Al agregar un rol nuevo: fila nueva con fecha, aprobador y enlace a captura o issue.

## Primera revisión de accesos

| Campo | Valor |
|---|---|
| Fecha | 2026-11-18 |
| Revisó | CEOAlmaloco (con Kuurisuu) |
| Alcance | Cuentas de prueba del tenant del curso |
| Resultado | Cuatro cuentas, un App Role cada una; MFA activo vía Security defaults; sin cuentas huérfanas con rol de personal |
| Próxima revisión | Al incorporar personal real o al cerrar EP3.5-13 (capacidades) |

## Relación con el frontend

- Sesión MSAL en `sessionStorage` (no sobrevive al cerrar el navegador).
- Idle del personal configurable en `environment.session`.
- Logout limpia tokens y `bd.profile.*` del almacenamiento.
