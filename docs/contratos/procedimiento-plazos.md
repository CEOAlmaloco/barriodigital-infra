## Contrato: plazos del procedimiento, suspensión y prórroga (EP3.5-03)

Define los plazos que agrega el procedimiento de EP3.5, cuándo empiezan a correr, la suspensión y la prórroga del plazo de atención y la fecha comprometida que ve el vecino. Amplía [`requests-plazos.md`](requests-plazos.md) (EP3-06), que sigue rigiendo el conteo en días hábiles, el calendario y los estados del plazo. Los estados están en [`procedimiento-estados.md`](procedimiento-estados.md). Lo implementan EP3.5-22 (suspensión, prórroga y fecha comprometida), EP3.5-23 (subsanación), EP3.5-32 (recursos y reapertura) y EP3.5-35 (espera de cupo).

**Base legal, como fundamento de diseño:** los plazos de días son hábiles y se cuentan desde el día siguiente (Ley 19.880, art. 25); la Administración puede ampliar un plazo hasta la mitad, antes de su vencimiento y nunca uno ya vencido (art. 26); el procedimiento no debe exceder seis meses (art. 27); la subsanación es de cinco días (art. 31); la notificación electrónica se entiende practicada al tercer día hábil siguiente a su envío (art. 46); la reposición se presenta en cinco días y se resuelve en no más de treinta (art. 59). Se aplican por analogía, como en EP3-06.

### 1. Plazos

Todos los días hábiles se cuentan con el calendario de EP3-06, sección 3, y desde EP3.5-22 con el calendario institucional de catalog. Las fechas se calculan en `America/Santiago`.

| Plazo | Duración | Empieza a contar | Fuente | Lo controla |
|---|---|---|---|---|
| Atención | `slaBusinessDays` del tipo, de 1 a 120 días hábiles | Día hábil siguiente al alta (EP3-06, sección 2.2) | EP3-06 | report |
| Subsanación | 5 días hábiles | Día hábil siguiente a la fecha de efecto del requerimiento (sección 2) | Art. 31 | requests |
| Ampliación de la subsanación | Hasta 2 días hábiles, a pedido del titular | Se suma al plazo de subsanación | Art. 26: la mitad de 5, sin fracciones | requests |
| Presentar un recurso | `REPOSICION`: 5 días hábiles. `REVISION`: de 5 a 15 días hábiles, configurable por tipo (EP3.5-09), con 5 por defecto | Día hábil siguiente a la fecha de efecto de la comunicación del cierre | Art. 59 | requests |
| Resolver un recurso | Hasta 30 días hábiles | Día hábil siguiente a la presentación | Art. 59 | requests, con alerta a quien resuelve |
| Reapertura | 30 días corridos; el último día es la fecha de cierre más 30 | Día siguiente al cierre | E9 (D-12) | requests |
| Duración máxima | Alerta a los 5 meses del alta | Alta | Art. 27 | report. Solo en tipos formales (EP3.5-33); en EP3.5 no hay ninguno (D-01) |
| Aceptación de una orden | 4 horas corridas | Asignación | `field.md`, sección 4 | field |

El mínimo de 5 días de la `REVISION` evita que un reclamo OIRS tenga menos plazo que una reposición; el máximo de 15 acota cuánto tiempo puede quedar un cierre sin firmeza.

### 2. Fecha de efecto de una comunicación formal

Los plazos de subsanación y de recurso corren desde que la comunicación formal produce efecto, no desde que se decide. notify informa la fecha de efecto en `notify.events` (`comunicaciones.md`, sección 8) y requests la usa para calcular `remedyDueDate` y `appealDueDate`.

| Medio | Fecha de efecto |
|---|---|
| Electrónico: CasillaÚnica, simulada en el laboratorio (EP3.5-37) | Tercer día hábil siguiente al envío (art. 46) |
| Correo al medio que designó la persona, mientras no exista CasillaÚnica | Igual, por analogía |
| Carta certificada (EP3.5-37) | Tercer día hábil siguiente a su recepción en la oficina de correos (art. 46) |
| Presencial, con constancia en la oficina (EP3.5-37) | El día de la constancia |

Reglas:
1. **"Envío" es el estado `ENVIADO` en notify:** el proveedor aceptó el mensaje.
2. **A quién.** Si el trámite tiene un `REPRESENTANTE` vinculado, la comunicación formal que produce efecto es la del representante, y el titular recibe una copia informativa. Si no, la del titular (art. 22).
3. **Rebote antes del efecto.** Si llega un `REBOTADO` o `FALLIDO` antes de la fecha de efecto, la fecha se anula y el plazo no empieza: requests deja la notificación pendiente por otro medio (`comunicaciones.md`, sección 4). Un rebote posterior a la fecha de efecto no la cambia; su valor es validación jurídica (sección 9).
4. **Sin fecha de efecto, sin plazo.** Mientras no hay fecha de efecto, `remedyDueDate` y `appealDueDate` son `null` y el detalle muestra "Notificación pendiente". El trámite no puede pasar a desistimiento por confirmar ni el recurso quedar fuera de plazo.

### 3. Suspensión del plazo de atención

#### 3.1 Causas

Solo tres causas (E9, D-12), como enum `SlaSuspensionCause`:

| `cause` | Empieza | Termina | Quién |
|---|---|---|---|
| `SUBSANACION` | Al pasar a `EN_SUBSANACION` (T05) | Al volver al estado de origen (T06) o al cerrar | requests, con la acción |
| `ESPERA_CUPO` | Al pasar a `EN_ESPERA_CUPO` (T03) | Al admitir (T04) o al cerrar | requests, con la acción |
| `ESPERA_TERCERO` | `POST /api/requests/{id}/sla-suspensions` en `EN_GESTION` o `EN_TERRENO`, con motivo público | `POST /api/requests/{id}/sla-suspensions/{suspensionId}/end`, al cerrar, o sola a los 20 días hábiles | Responsable, con Operar trámites |

**Tope de `ESPERA_TERCERO`.** A los 20 días hábiles, requests la termina y publica `request.sla-resumed`. Una espera de un tercero no puede detener el plazo sin fin: es el incentivo perverso que evita EP3-06, sección 2.1. Una nueva suspensión exige un motivo nuevo y queda en el historial.

**A lo más una suspensión abierta.** Por construcción no se superponen: `SUBSANACION` y `ESPERA_CUPO` ocurren antes de la gestión y `ESPERA_TERCERO` durante ella. Una segunda suspensión mientras hay una abierta responde 409. Las suspensiones encadenadas (una después de otra) sí son válidas.

**Al cerrar** con una suspensión abierta, requests publica `request.sla-resumed` antes del evento de cierre, en la misma transacción. Así report siempre ve una suspensión cerrada.

#### 3.2 Cómputo

**`dueDate` es el día hábil número N del conteo, contando solo los días hábiles fuera de las suspensiones**, con N = `slaBusinessDays` más las prórrogas aprobadas. Para una suspensión que empieza el día S y termina el día R:
- el día S cuenta, si es hábil: el plazo ya corrió ese día;
- no cuentan los días hábiles posteriores a S hasta R, incluido R, porque el conteo se retoma desde el día siguiente (art. 25);
- una suspensión que empieza y termina el mismo día no descuenta ningún día.

Una suspensión que empieza después de `dueDate` no mueve la fecha: esos días no estaban en el conteo. Por eso la regla no suma días a `dueDate`.

Ejemplo, con un plazo de 5 días, alta el viernes 6-nov-2026 y sin feriados en esas semanas:

| Caso | Días que no cuentan | `dueDate` |
|---|---|---|
| Sin suspensión | - | Viernes 13-nov |
| Suspendido el martes 10 y reanudado el jueves 12 | Miércoles 11 y jueves 12 | Martes 17-nov |
| Suspendido y reanudado el martes 10 | Ninguno | Viernes 13-nov |
| Suspendido el lunes 16, ya vencido | Ninguno anterior a `dueDate` | Viernes 13-nov |

#### 3.3 Estado del plazo

`slaStatus` suma el valor `SUSPENDIDO` ("Suspendido"):

| Al suspender | Efecto en report |
|---|---|
| D es igual o anterior a `dueDate` | `due_date` y `due_soon_date` pasan a `null` y `sla_status` a `SUSPENDIDO`. El `UPDATE` diario ya los deja fuera (`due_date IS NOT NULL`, EP3-06, sección 5.1) |
| D es posterior a `dueDate` | Las fechas se conservan y sigue `VENCIDO`: suspender no oculta un atraso |

Al reanudar, report recalcula `dueDate` y `dueSoonDate` con las suspensiones cerradas y el estado según EP3-06, sección 4.1. report guarda cada suspensión con `started_on` y `ended_on`, y el recálculo al arrancar (EP3-06, sección 3.3) las considera.

### 4. Prórroga del plazo de atención

1. **Pedir.** El responsable, `POST /api/requests/{id}/extensions`, con `businessDays` (entero ≥ 1) y un motivo público, que se le comunica al vecino. Solo en un trámite abierto, con plazo y no vencido, sin otra prórroga pendiente. Publica `request.extension-requested`.
2. **Límite.** La suma de las prórrogas aprobadas no supera la mitad de `slaBusinessDays`, sin fracciones (art. 26). Con un plazo de 1 día no hay prórroga posible. Fuera del límite responde 400.
3. **Aprobar.** Quien tiene Aprobar prórrogas y no la pidió, `POST /api/requests/{id}/extensions/{extensionId}/decision`, con `approved`. Debe decidir a más tardar el día de `dueDate`: el art. 26 exige que la ampliación se pida y se conceda antes del vencimiento. Publica `request.extension-decided`.
4. **Vencimiento de la solicitud.** Si llega el día siguiente a `dueDate` sin decisión, requests la cierra con `decision = VENCIDA`. Mientras está pendiente, el plazo no cambia.
5. **Efecto.** Una aprobación suma sus días a N (sección 3.2). report recalcula `dueDate` y `dueSoonDate`, y el trámite puede volver de `POR_VENCER` a `DENTRO_DE_PLAZO`.

Un trámite sin plazo (`SIN_PLAZO`) no admite prórroga: responde 409.

**Validación en requests.** requests comprueba el límite y que el trámite no esté vencido calculando `dueDate` con el calendario compartido de EP3.5-22 y las reglas de este contrato. report sigue siendo la fuente de `slaStatus` y de los indicadores. Una prueba de contrato con los mismos casos en los dos servicios evita que difieran.

### 5. Cierres nuevos y reapertura en report

1. **Cierres nuevos.** `DESISTIDO`, `CERRADO_SIN_CONTACTO`, `DERIVADO` y `DUPLICADO` escriben `closedAt` y detienen el plazo. Si el trámite tenía plazo quedan en `NO_APLICA`, como `CANCELADO` (EP3-06, sección 2.3): nadie lo resolvió ni lo rechazó, así que no cuentan en el cumplimiento. Los derivados no cuentan como resueltos ni como rechazados (TRA-04).
2. **Reapertura.** Por la parte, por el responsable o por un recurso, abre un **ciclo nuevo**: `closedAt` vuelve a `null` y el plazo se cuenta de nuevo completo desde el día hábil siguiente a la reapertura, con el mismo `slaBusinessDays`. La evaluación del ciclo anterior se conserva, como en EP3-06, límite 3: un resultado ya informado no se reescribe.
3. **Indicadores.** El cumplimiento cuenta cada ciclo cerrado en `RESUELTO` o `RECHAZADO`. report informa aparte la tasa de reapertura y la de recursos con su resultado (EP3.5-45).

### 6. Fecha comprometida para el vecino

El vecino ve la fecha comprometida y sus cambios en el detalle y en la consulta pública (EP3.5-22, criterio 6; EP3.5-17). Reemplaza la regla de EP3-06, sección 7, de mostrarle solo los días.

| Situación | Qué ve |
|---|---|
| Con plazo, sin suspensión | "Fecha comprometida: {dueDate}", con la fecha en formato largo de Chile |
| Suspendido | "Plazo suspendido mientras {causa}", con la causa pública: "esperamos tus antecedentes", "esperamos cupo de atención" o "esperamos respuesta de {organismo o empresa}" |
| Vencido | La fecha comprometida y "La municipalidad no cumplió la fecha comprometida". No se oculta |
| Prórroga aprobada | La fecha nueva y, en el historial público, la anterior con el motivo |
| Sin plazo | No se muestra el bloque, como hoy |

- `POR_VENCER` y los demás estados internos no se le muestran: siguen siendo del personal.
- El historial público registra cada cambio de fecha con su causa. El vecino recibe la comunicación de la matriz (`comunicaciones.md`).
- **Fuente:** el BFF obtiene el trámite de requests, que controla el acceso, y después el plazo de report por `requestId` (la mejora del límite 6 de EP3-06).

### 7. Casos

| Caso | Regla |
|---|---|
| Año sin calendario | Vale EP3-06, sección 3.2, también para la subsanación, los recursos y las suspensiones |
| Horario de verano | No afecta: todos los plazos, incluidos los 30 días corridos de la reapertura, son fechas en `America/Santiago`. Solo las 4 horas de field se miden como instantes, que no dependen del cambio de hora |
| Proyección parcial en report | Las suspensiones se guardan y se aplican cuando llega `request.created` (EP3-06, sección 6.1) |
| Eventos de suspensión desordenados | report aplica el orden de `sequence` (EP3-02, sección 9.3) |
| Dos instancias de report | El listener bloquea la proyección (EP3-06, sección 5.2). El cierre automático de `ESPERA_TERCERO` y de las prórrogas vencidas corre en requests con el bloqueo del trámite: dos instancias no lo duplican, porque la segunda encuentra la suspensión o la solicitud ya cerrada |

### 8. Eventos

Usan el sobre y las reglas de `procedimiento-estados.md`, sección 8. Llevan `requestId` y `folio`.

| `eventType` | Campos propios |
|---|---|
| `request.sla-suspended` | `suspensionId` (uuid) y `cause` |
| `request.sla-resumed` | `suspensionId`, `cause` y `endedBy`: `ACCION`, `CIERRE` o `TOPE` |
| `request.extension-requested` | `extensionId` (uuid), `businessDays` y `reason` |
| `request.extension-decided` | `extensionId`, `decision` (`APROBADA`, `RECHAZADA` o `VENCIDA`) y `businessDays` |

`reason` de la prórroga viaja porque es público y explica una decisión del personal, como el motivo de rechazo (EP3-01, sección 8). El motivo de `ESPERA_TERCERO` no viaja: puede nombrar a un tercero, y report solo necesita la causa.

### 9. Límites conocidos

1. **Rebote posterior a la fecha de efecto.** No anula la notificación ya practicada. Si en ese caso debe repetirse es validación jurídica.
2. **Dos cálculos de `dueDate`.** requests lo calcula solo para validar la prórroga y report para todo lo demás. La prueba de contrato de la sección 4 es la que impide que difieran.
3. **Fecha de efecto del correo.** Aplicar el tercer día hábil del art. 46 a un correo electrónico mientras no existe el domicilio digital único es una analogía de diseño, no una interpretación legal.
4. **Duración máxima.** La alerta de los 5 meses queda sin uso hasta que exista un tipo formal.
