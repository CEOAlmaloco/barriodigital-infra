<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: plazos en días hábiles (EP3-06)

Define el plazo de atención por tipo de trámite, cómo se cuenta en días hábiles, de dónde salen los feriados, los estados del plazo y cómo los calcula report. Es la base de EP3-24 (catalog), EP3-25 (BFF), EP3-31 (requests), EP3-36 y EP3-38 (report), EP3-46 y EP3-53 (frontend).

**Base legal, como fundamento de diseño:** la Ley 19.880 fija que los plazos de días son de días hábiles, y que los sábados, domingos y festivos son inhábiles (art. 25). El mismo artículo dice que los plazos se cuentan desde el día siguiente, y que una presentación electrónica en día inhábil se entiende hecha en la primera hora del primer día hábil siguiente. El art. 27 limita la duración de un procedimiento a seis meses. Este contrato aplica esas reglas por analogía al plazo de atención. No es una interpretación legal.

**Nombres:** los campos, columnas y propiedades van en inglés (convención 13 del backlog). Los valores de los enums de dominio van en español, como `RequestStatus` y `ActivityKind`.

### 1. Plazo por tipo y snapshot

#### 1.1 `slaBusinessDays` en catalog

| Regla | Valor |
|---|---|
| Rango | Entero de 1 a 120 días hábiles. El tope se ancla en el art. 27: seis meses son unos 120 a 125 días hábiles, y ningún plazo de atención debería superar la duración máxima de un procedimiento. Además evita errores de tipeo |
| `null` | Sin plazo, igual que `dailyQuota` en EP1.5-03. Un tipo nuevo, y los tipos existentes, quedan sin plazo hasta que el Admin lo defina |
| `POST` | Opcional, `null` si se omite |
| `PUT` | Reemplaza el valor completo, como el cupo: si el body no trae `slaBusinessDays`, el tipo pasa a sin plazo. El frontend envía siempre el campo. Una sola regla para todo el body es más fácil de seguir que dos |
| Quién lo edita | Solo el Admin. El orden de validación es el de catalog: 403, 400, 404. También vale para un body ilegible (sección 1.2) |
| Fuera de rango | 400 `El plazo debe ser un entero entre 1 y 120 dias habiles` |
| Auditoría | Cada cambio queda en `procedure-type.updated`, con `slaBusinessDays` en `before` y `after` (EP3-01, sección 7) |

#### 1.2 Lectura estricta del body en catalog

Jackson acepta por defecto `5.7` como 5 y `"5"` como 5. Para que un decimal o un string respondan 400, catalog configura:

```yaml
spring:
  jackson:
    deserialization:
      accept-float-as-int: false
    mapper:
      allow-coercion-of-scalars: false
```

1. **Aplica a todo catalog.** También endurece `dailyQuota` y `active`, que dejan de aceptar `"5"` y `"true"`. Cambia lo que aceptan EP1.5-02 y EP1.5-03, que llevan una nota fechada. El frontend ya envía números y booleanos (`<input type="number">` con un control `number | null`), el BFF reenvía el body como `Map<String, Object>` sin cambiar los tipos, y ningún test de catalog envía esos campos como string.
2. **Cubre números y booleanos, no texto.** `allow-coercion-of-scalars` no afecta a los campos de texto: un `label` enviado como número se sigue aceptando como texto.
3. **El 400 se arma según el campo.** `CatalogExceptionHandler` agrega un `@ExceptionHandler(HttpMessageNotReadableException.class)`, lee la ruta del campo desde la causa (`MismatchedInputException.getPath()`) y responde con el cuerpo de error de catalog (`status`, `error`, `message`):

| Campo | `message` |
|---|---|
| `slaBusinessDays` | `El plazo debe ser un entero entre 1 y 120 dias habiles` |
| `dailyQuota` | `El cupo diario debe ser un entero` |
| Cualquier otro campo, o un JSON roto | `El cuerpo de la solicitud no es valido` |

4. **El rol se revisa antes que el body.** Spring lee el body antes de que `CatalogService` compruebe el rol, así que un error de lectura llegaría antes que el 403. Para mantener el orden 403, 400, 404, el manejador revisa `X-User-Roles` con `AdminCaller.isAdmin` antes de armar el 400: si quien llama no es Admin, responde el mismo 403 que el servicio (`Solo Admin puede crear tipos de tramite` en `POST` y `Solo Admin puede editar tipos de tramite` en `PUT`).

#### 1.3 Snapshot en el alta

1. El BFF toma `slaBusinessDays` del tipo que ya valida `ProcedureTypeValidator` y lo reenvía en `X-Procedure-Sla-Days`, igual que `X-Procedure-Label`. Si el tipo no tiene plazo, el header no se envía (EP3-25).
2. requests lo guarda en el trámite, lo incluye en `request.created` y lo expone en `RequestView` para los cuatro roles (EP3-31). EP3-29 no lo expone porque la columna todavía no existe.
   - **Header inválido.** Un valor que no es un entero de 1 a 120 se guarda como `null`, con un `WARN` en el log, y el alta sigue. El BFF ya validó el rango contra catalog, así que un valor inválido sería un error del BFF, y no debe impedir que el vecino ingrese su trámite. Es la misma regla que `X-Procedure-Label` mal codificado.
3. **Editar el plazo del tipo no afecta a los trámites ya ingresados.** report calcula con el snapshot del alta. El plazo del tipo es una política de la municipalidad, y no se le cambia al vecino un compromiso ya informado.

### 2. Cómo se cuenta el plazo

#### 2.1 Desde cuándo corre

El plazo corre **desde el alta**, no desde la admisión:
- es el compromiso con el vecino, que espera desde que ingresó su solicitud;
- evita un incentivo perverso: con la admisión como inicio, demorarla detendría el reloj, y la espera por cupo agotado no contaría.

El **inicio** depende de un solo evento, `request.created`. Para detener el plazo, report usa además `request.status-changed` y `request.cancelled`, ordenados por `sequence` (EP3-02, sección 9.3).

#### 2.2 Reglas de conteo

1. **El día del alta se calcula en `America/Santiago`**, desde el `occurredAt` de `request.created`. Un alta del viernes a las 22:00 en Chile ya es sábado en UTC: sin la conversión caería en un día inhábil por error. Es la misma regla del año del folio (EP3-05, sección 1.1), y `occurredAt` es el mismo instante que `created_at`.
2. **Un alta en día inhábil se entiende hecha el primer día hábil siguiente** (art. 25).
3. **El conteo parte el día hábil siguiente** al día del alta, o al día en que se entiende hecha.
4. **`dueDate` es el día hábil número N** del conteo, con N = `slaBusinessDays`. Es una fecha (`LocalDate`) en `America/Santiago`, no un instante. Como solo se cuentan días hábiles, `dueDate` siempre es hábil, y la prórroga del art. 25 cuando el último día es inhábil ocurre sola.
5. **Las reglas 2 y 3 usan el mismo calendario** de la sección 3. Nadie implementa "inhábil = sábado o domingo" en una parte y con feriados en la otra.
6. **Sin pausas.** El plazo corre en todos los estados abiertos y se detiene en `RESUELTO`, `RECHAZADO` o `CANCELADO` (sección 2.3).
7. **Se mide con la hora del hecho**, el `occurredAt`, no con la llegada a Kafka (EP3-01, sección 4). Un evento atrasado por el outbox no mueve el plazo.

Ejemplos, con un plazo de 5 días y sin feriados en esa semana:

| Alta | Día 1 | `dueDate` |
|---|---|---|
| Viernes 6-nov-2026, 10:00 | Lunes 9-nov | Viernes 13-nov |
| Sábado 7-nov-2026 (se entiende hecha el lunes 9) | Martes 10-nov | Lunes 16-nov |

#### 2.3 Cierre

Un trámite cerrado se evalúa por fecha, con la misma regla:
- **`CUMPLIDO`:** la fecha del `occurredAt` del cambio a `RESUELTO` o `RECHAZADO`, en `America/Santiago`, es igual o anterior a `dueDate`;
- **`FUERA_DE_PLAZO`:** es posterior.

Un trámite sin plazo no es ni cumplido ni fuera de plazo.

Un trámite **`CANCELADO`** también se cierra: escribe `closedAt` y el plazo se detiene. Si tenía plazo queda en `NO_APLICA`: no es ni cumplido ni fuera de plazo, porque nadie lo resolvió ni lo rechazó, así que no entra en el cumplimiento. Sin plazo sigue en `SIN_PLAZO`.

### 3. Calendario de feriados

#### 3.1 Fuente

Solo report calcula plazos, así que el calendario vive solo en report. requests y el frontend no lo necesitan: el frontend muestra lo que calcula report.

**Archivo versionado `holidays-cl.yml` en report**, cargado con `@ConfigurationProperties`. Es determinista, se prueba sin red, y la EC2 no depende de un tercero. Se descartaron una API externa (el cálculo fallaría si no responde) y una tabla editable por el Admin (suma endpoint, pantalla y auditoría, fuera de la prioridad Alta).

1. **Contenido:** los feriados nacionales de 2026 y 2027, por fecha y con su nombre.
2. **Fuente oficial:** las fechas se toman del texto legal (BCN o Diario Oficial), no de memoria ni de sitios agregadores, porque varios feriados se trasladan según el año. El archivo cita la fuente y la fecha en que se verificó.
3. **El 31 de diciembre no se incluye.** Es feriado bancario, no feriado legal, y no hace inhábil el día para la administración.
4. **Feriados regionales:** solo los que aplican a la comuna del proyecto, Alto Biobío (Región del Biobío), que es la que valida `LocationRules`. Los feriados regionales vigentes (7 de junio en Arica y Parinacota, y 20 de agosto en Chillán y Chillán Viejo) no le aplican, así que el archivo no tiene feriados regionales. Se confirma con la fuente oficial al cargar el archivo. El Día Nacional de los Pueblos Indígenas es nacional y va incluido.

#### 3.2 Años sin calendario

El cálculo depende de **todos los años que cruza el conteo**, no solo del año del alta. Con un tope de 120 días hábiles, un conteo puede pasar al año siguiente.

Si el calendario no cubre algún año del conteo:
1. ese tramo se calcula solo con sábados y domingos. La fecha sale igual o más temprana que la correcta: el aviso nunca llega tarde, pero un cierre de ese tramo puede evaluarse `FUERA_DE_PLAZO` sin serlo (límite 3);
2. report registra `WARN calendario-feriados-incompleto year=2028`;
3. el health de report lo muestra en el componente informativo `sla`, siempre `UP`, con los años cubiertos y los que faltaron. Su detalle se ve sin autorización en el grupo `/actuator/health/sla`; el health general mantiene `when_authorized`, porque incluye la base de datos. Report no falla al arrancar por un archivo desactualizado, porque la reportería no es el core.

#### 3.3 Recálculo al arrancar

El archivo solo cambia con un redeploy de report. Al arrancar, report **recalcula `dueDate` y `dueSoonDate` de los trámites abiertos** con el calendario cargado:
- aplica un feriado nuevo, que por el art. 25 es inhábil aunque se haya declarado después del alta;
- corrige los tramos calculados solo con fines de semana mientras faltaba un año.

**Por qué no se congela la fecha:** el plazo por tipo es una política (sección 1.3), pero un feriado es un hecho legal. Una fecha congelada que no lo descuenta queda mal según la misma norma que usa el contrato.

Los trámites **cerrados** no se recalculan: su `CUMPLIDO` o `FUERA_DE_PLAZO` ya se evaluó. El recálculo tampoco toca los trámites sin plazo: trabaja sobre el snapshot de `slaBusinessDays`, nunca sobre el plazo actual del tipo en catalog. Tampoco toca las proyecciones parciales, que no tienen fecha de alta desde donde contar (sección 5.2).

### 4. Estados del plazo

#### 4.1 `slaStatus`

Un solo campo para todo el ciclo de vida:

| Situación | `slaStatus` | Texto en pantalla | Condición, con D = fecha actual en `America/Santiago` |
|---|---|---|---|
| Abierto | `DENTRO_DE_PLAZO` | "Dentro de plazo" | D es anterior a `dueSoonDate` |
| Abierto | `POR_VENCER` | "Por vencer" | D es igual o posterior a `dueSoonDate`, e igual o anterior a `dueDate` |
| Abierto | `VENCIDO` | "Vencido" | D es posterior a `dueDate` |
| Cerrado | `CUMPLIDO` | "Cumplido" | Sección 2.3 |
| Cerrado | `FUERA_DE_PLAZO` | "Fuera de plazo" | Sección 2.3 |
| Cerrado | `NO_APLICA` | "No aplica" | Cancelado con plazo (sección 2.3) |
| Sin plazo | `SIN_PLAZO` | "Sin plazo" | `slaBusinessDays` nulo, abierto o cerrado |

Una proyección parcial (sección 6.1) tiene `sla_status` en `null`, que significa "sin dato", distinto de `SIN_PLAZO`. EP3-07 define cómo se muestra en la API.

#### 4.2 Umbral de "por vencer"

El umbral es fijo: **2 días hábiles o menos**, contando D si es hábil y `dueDate`. Queda en configuración, `barriodigital.sla.due-soon-business-days: 2`, y el contrato fija el 2.

- **Por qué fijo:** es fácil de explicar en pantalla y da un día hábil completo de aviso antes del último. Un umbral proporcional, por ejemplo el 20 %, avisaría con 24 días de anticipación en un plazo de 120, y dejaría de ser una alerta.
- **Plazos cortos:** con `slaBusinessDays = 1`, el trámite nace `POR_VENCER`. Si entra el lunes, vence el martes, y ese mismo lunes quedan 2 días hábiles. Es correcto: ese plazo es urgente por definición.

#### 4.3 `dueSoonDate`

Para que el cálculo diario solo compare fechas, report guarda también `dueSoonDate`, la fecha en que el trámite pasa a `POR_VENCER`:

> `dueSoonDate` es el día siguiente al día hábil número (N + 1) contado hacia atrás desde `dueDate`, donde `dueDate` es el día 1 y N es `due-soon-business-days`.

Con N = 2: si `dueDate` es viernes, los días 1, 2 y 3 son viernes, jueves y miércoles, y `dueSoonDate` es el jueves. Si `dueDate` es martes, son martes, lunes y viernes, y `dueSoonDate` es el sábado; el funcionario ve el aviso el lunes.

`dueDate` y `dueSoonDate` se calculan juntos, y es el único lugar donde se usa el calendario.

#### 4.4 Nombres en report

| Campo | Columna | Contenido |
|---|---|---|
| `createdAt` | `created_at` | `occurredAt` de `request.created`. Nulo en una proyección parcial |
| `slaBusinessDays` | `sla_business_days` | Snapshot del plazo, tomado de `request.created`. Es la base del recálculo |
| `dueDate` | `due_date` | Sección 2.2 |
| `dueSoonDate` | `due_soon_date` | Sección 4.3 |
| `closedAt` | `closed_at` | `occurredAt` del cambio a `RESUELTO`, `RECHAZADO` o `CANCELADO` (sección 2.3) |
| `slaStatus` | `sla_status` | Sección 4.1 |

### 5. Cálculo y concurrencia

#### 5.1 Cuándo se calcula

| Momento | Qué hace |
|---|---|
| Al proyectar `request.created` | Con plazo: calcula `dueDate`, `dueSoonDate` y `slaStatus`. Sin plazo: `SIN_PLAZO` |
| Al proyectar un cierre | Escribe `closedAt`, vuelve a calcular `dueDate` con el calendario cargado y, si se cerró en `RESUELTO` o `RECHAZADO`, escribe `CUMPLIDO` o `FUERA_DE_PLAZO`; la cancelación sigue la sección 2.3. Un resultado ya evaluado no se recalcula. Un trámite `SIN_PLAZO` sigue en `SIN_PLAZO`, y una proyección parcial sigue con `sla_status` nulo |
| Al arrancar | Evaluación de las altas con `sla_status` nulo, proyectadas antes de que report calculara plazos; recálculo de la sección 3.3; `UPDATE` de estado, y recién entonces se inicia el listener |
| Todos los días a las 00:05 en `America/Santiago` | El `UPDATE` de estado |

Cumple K8: los vencimientos se calculan con un `@Scheduled`, sin evento adicional, y la API de report lee proyecciones ya materializadas.

**El `UPDATE` de estado** es una sola sentencia sobre el conjunto, sin calendario, que cubre los tres estados abiertos y es excluyente por construcción:

```sql
UPDATE report_request_projection
SET sla_status = CASE
    WHEN due_date < :hoy       THEN 'VENCIDO'
    WHEN due_soon_date <= :hoy THEN 'POR_VENCER'
    ELSE 'DENTRO_DE_PLAZO'
  END
WHERE closed_at IS NULL AND due_date IS NOT NULL
```

- `:hoy` es la fecha actual en `America/Santiago`. La tabla es `report_request_projection`.
- **Mueve los estados en las dos direcciones.** Si el recálculo posterga `dueDate` a una fecha más tardía, por un feriado nuevo o por un año que faltaba, un trámite `VENCIDO` puede volver a `POR_VENCER` o a `DENTRO_DE_PLAZO`, y uno `POR_VENCER` puede volver a `DENTRO_DE_PLAZO`. Con una sentencia por estado, ninguna condición lo devolvería.
- `due_date IS NOT NULL` deja fuera, de forma explícita, a los trámites sin plazo y a las proyecciones parciales.

**Horario de verano:** en septiembre, Chile adelanta el reloj de las 24:00 del sábado a la 01:00 del domingo, y ese domingo no existen las 00:05. No afecta, porque ningún estado cambia en domingo: un estado solo cambia en un día cuyo día anterior fue hábil, y `VENCIDO` empieza el día siguiente a una `dueDate`, que siempre es hábil. Spring no ejecuta el job ese domingo, porque la hora no existe, y no hace falta una segunda ejecución.

#### 5.2 Escrituras sin pérdidas

Tres procesos escriben la misma proyección: el listener, el recálculo al arrancar y el job diario. La regla es: **el listener bloquea la fila, y los procesos derivados escriben solo sus columnas.**

1. **El listener lee la proyección con `PESSIMISTIC_WRITE`** (`findByIdForUpdate`), dentro de su transacción. Al proyectar un cierre vuelve a calcular `dueDate` antes de evaluar, así un recálculo fallido al arrancar no deja una evaluación con la fecha vieja; el bloqueo ordena al listener con el recálculo: si el recálculo llegó primero, el listener espera; si el listener llegó primero, el recálculo espera y el `WHERE` lo deja fuera si el trámite se cerró. `@DynamicUpdate` no alcanza, porque no protege la lectura.
2. **El recálculo al arrancar** recorre los trámites abiertos con `created_at` y `sla_business_days` no nulos. Así deja fuera a los trámites sin plazo y a las proyecciones parciales, que no tienen desde dónde contar. Escribe con un `UPDATE` acotado por trámite (`@Modifying`), que solo toca `due_date` y `due_soon_date`, con `WHERE id = :id AND closed_at IS NULL`. **Cada trámite va en su propia transacción**, y se recorren por `id` ascendente. Va un `UPDATE` por trámite porque contar días hábiles necesita el calendario en Java.
3. **El job diario** escribe con el `UPDATE` de estado sobre el conjunto de la sección 5.1.
4. **Ningún proceso derivado lee la fila, la modifica en Java y la guarda completa.** En Oracle, un `UPDATE` que encuentra la fila cambiada por otra transacción vuelve a evaluar el `WHERE`: un trámite cerrado entremedio ya no cumple `closed_at IS NULL` y no se toca.
5. **El listener parte con `autoStartup=false`** y se inicia al terminar la evaluación de pendientes, el recálculo y el `UPDATE` de estado. Ordena el arranque. Lo que garantiza la corrección son las reglas 1 a 4. Si uno de esos pasos falla, el listener se inicia igual, porque detenerlo congelaría la proyección; el fallo queda en el log (`plazos-preparacion-incompleta`) y en el componente `sla` del health, y lo corrige el siguiente arranque.
6. **La evaluación de pendientes** escribe con un `UPDATE` acotado por trámite que solo toca `due_date`, `due_soon_date` y `sla_status`, con `WHERE id = :id AND sla_status IS NULL`: un trámite que el listener evaluó entremedio no se toca.
7. **Dos instancias** (la prueba de balanceo de EP3-36) corren las dos los procesos derivados. No hace falta un bloqueo distribuido: la evaluación de pendientes, el recálculo y el `UPDATE` de estado dan el mismo resultado si corren dos veces, y el bloqueo del listener cubre el recálculo de una instancia contra el listener de la otra.

#### 5.3 Deadlocks

report no tiene contadores compartidos: los KPIs son consultas agregadas sobre la proyección (EP3-07). Un ciclo de bloqueos necesita al menos dos transacciones que tengan cada una una fila y esperen la de la otra:

1. **El listener** bloquea solo la proyección de su trámite y no espera ninguna otra fila. Dos hilos nunca comparten una proyección, porque un trámite siempre cae en la misma partición.
2. **El recálculo** va un trámite por transacción (sección 5.2), así que cada transacción tiene una sola fila y no puede formar un ciclo.
3. **El `UPDATE` de estado** es el único que bloquea muchas filas en una sentencia. Con dos instancias (la prueba de balanceo de EP3-36), los dos jobs de las 00:05, o los dos arranques, pueden correr la misma sentencia a la vez y recorrer las filas en distinto orden. Si Oracle cancela una con `ORA-00060`, la sentencia completa se revierte, sin dejar nada a medias, y **se reintenta una vez**. Es seguro porque es idempotente. Si vuelve a fallar, se registra en el log y lo corrige la siguiente ejecución o el siguiente arranque.
4. **En el listener, un deadlock es recuperable** por si ocurriera. Spring traduce `ORA-00060` a una subclase de `PessimisticLockingFailureException`, y `DefaultErrorHandler` reintenta todo lo que no se registró como no recuperable, así que esa excepción **no** se registra como no recuperable.

### 6. Trámites sin plazo y trámites anteriores al outbox

#### 6.1 Trámites anteriores al outbox

report solo conoce un trámite por sus eventos, y `request.created` se registra en el outbox recién desde EP3-31. **report parte desde el despliegue:** los KPIs y los plazos cubren los trámites creados desde EP3-31, y la demo usa trámites nuevos. Se descartó un backfill de eventos sintéticos: es una issue en sí misma, toca la cadena crítica, y audit guardaría como reales eventos con un actor y una IP que no existieron.

Los trámites antiguos siguen vivos, y sus cambios posteriores sí publican eventos. Para eso, y para el `request.created` que se reprocesa desde la DLT, vale la regla de la **proyección parcial**:

1. Un evento de un trámite sin proyección **crea una proyección parcial** con lo que trae (estado actual, responsable, `sequence` y `folio`), sin datos de creación (`createdAt` nulo) y con `sla_status` nulo. No va a la DLT.
2. **Una proyección parcial no cuenta** en ningún KPI ni en los plazos.
3. **Si después llega el `request.created`** y el trámite sigue abierto, completa los datos de creación (`createdAt` y `slaBusinessDays`) y calcula `dueDate`, `dueSoonDate` y `slaStatus`, o `SIN_PLAZO` si no tiene plazo. No cambia el estado del trámite, porque su `sequence` es menor (EP3-02, sección 9.3). Desde ahí el trámite cuenta.
4. **Si la proyección parcial ya estaba cerrada** cuando llega el `created`, completa los mismos datos y evalúa de inmediato `CUMPLIDO` o `FUERA_DE_PLAZO` con la fecha de cierre ya guardada, o `SIN_PLAZO` si no tiene plazo.
5. **Un trámite antiguo nunca recibe su `created`,** así que queda parcial y fuera de los KPIs.

#### 6.2 Trámites sin plazo

Son los de tipos sin plazo y los creados antes de que el BFF reenvíe `X-Procedure-Sla-Days` (EP3-25):

1. **Se proyectan** con `dueDate` y `dueSoonDate` en `null` y `slaStatus` en `SIN_PLAZO`.
2. **No aparecen** en los listados de vencidos ni de por vencer, y el job no los toca.
3. **No cuentan en el cumplimiento:** el porcentaje se calcula con `CUMPLIDO` sobre `CUMPLIDO + FUERA_DE_PLAZO`.
4. **Definir un plazo después no les afecta**, por el snapshot. El recálculo al arrancar tampoco les calcula fechas.
5. **En pantalla**, el staff ve "Sin plazo" como texto neutro, no un estado vacío, para que no se confunda con un error de carga.

### 7. Qué ve cada rol

| Rol | Qué ve | Dónde |
|---|---|---|
| Vecino | El plazo en días, si el trámite tiene. No ve `dueDate` ni `slaStatus` | Detalle (EP3-46), con `slaBusinessDays` de `RequestView` |
| Funcionario, Admin y Auditor | `slaStatus`, `dueDate` y el plazo en días | Listado, detalle e `/inicio` (EP3-53, EP3-52) |

**Texto para el Vecino**, como plantilla:

> Plazo de atención: {slaBusinessDays} días hábiles, contados desde el día hábil siguiente al ingreso. Si ingresaste en sábado, domingo o festivo, el ingreso se considera hecho el día hábil siguiente.

- Con `slaBusinessDays = 1` va en singular: "1 día hábil".
- La segunda frase puede ir como texto secundario o en un tooltip.
- Si `slaBusinessDays` es `null`, el detalle no muestra el bloque.

La fila "Ver el estado del plazo" de la matriz de EP3-04 sigue en No para el Vecino: ve el compromiso en días, no el estado. Por eso se actualiza EP3-04, sección 6.1 (`slaBusinessDays` para los cuatro roles) y el límite 3.

### 8. Cambios en otros contratos

| Contrato | Cambio |
|---|---|
| EP1.5-02, sección 3 | Nota fechada: lectura estricta del body de catalog |
| EP1.5-03, sección 2 | Línea que remite a esa nota para `dailyQuota` |
| EP3-01, sección 6 | Los ejemplos de `request.created` y `request.status-changed` usan `sector: "ralco"` y un punto dentro de la caja de `LocationRules`. Antes usaban `Centro` y coordenadas de Viña del Mar, que el propio sistema rechaza con 400 |
| EP3-04, sección 6.1 | `folio` y `slaBusinessDays` visibles para los cuatro roles, y la nota de los campos que suma `RequestView` |
| EP3-04, límite 3 | Reescrito: el Vecino ve el plazo en días |

### 9. Cambios por capa

| Capa | Cambio | Issue |
|---|---|---|
| **catalog** | Columna `sla_business_days` nullable, `slaBusinessDays` en `ProcedureView`, POST y PUT con la sección 1.1. Lectura estricta y manejador de `HttpMessageNotReadableException` de la sección 1.2 | EP3-24 |
| **BFF** | `X-Procedure-Sla-Days` en el alta, sin header si no hay plazo | EP3-25 |
| **requests** | Columna del snapshot, `slaBusinessDays` en `request.created` y en `RequestView` | EP3-31 |
| **report**, consumidor | Proyección con `createdAt`, `slaBusinessDays` y `closedAt`, bloqueo de la proyección y proyección parcial | EP3-36 |
| **report**, plazos | Cálculo de `dueDate`, `dueSoonDate` y `slaStatus` al proyectar el alta y el cierre, `holidays-cl.yml`, recálculo al arrancar, `UPDATE` de estado al arrancar y a las 00:05 con su reintento ante deadlock, health del calendario y endpoints de plazos | EP3-38 |
| **frontend** | `slaStatus` con su texto en listado, detalle e `/inicio`. Plazo en días para el Vecino. Edición de `slaBusinessDays` por el Admin | EP3-46, EP3-52, EP3-53 |

**Tests que pide este contrato**, además de los de cada ficha:
- recálculo al arrancar: un trámite abierto calculado sin un feriado queda corregido;
- un trámite `VENCIDO` vuelve a `DENTRO_DE_PLAZO` cuando el recálculo posterga su `dueDate`;
- el job y el recálculo no tocan trámites sin plazo ni proyecciones parciales;
- proyección parcial completada por un `created` posterior, abierta y cerrada;
- lectura estricta en catalog: `"5"` y `5.7` responden 400 con su mensaje, y 403 si quien llama no es Admin.

### 10. Límites conocidos

1. **Trámites anteriores a EP3-31** (por plazo): no aparecen en los KPIs ni en los plazos, tampoco en "estados activos", aunque sigan abiertos. El timeline de audit de esos trámites empieza en el despliegue. Mejora futura: un backfill con eventos marcados como reconstruidos.
2. **Un feriado nuevo se aplica después del redeploy de report** (por diseño).
3. **Un trámite cerrado mientras faltaba un año en el calendario** conserva su evaluación, aunque se haya hecho solo con fines de semana (por diseño, para no reescribir resultados ya informados).
4. **Sin pausas** (por diseño): si el trámite espera una respuesta del vecino, por ejemplo una gestión con resultado `NO_CONTESTA`, el plazo sigue corriendo. Mejora futura: suspensión con motivo.
5. **Entre las 00:00 y las 00:05**, un trámite que acaba de vencer se ve con el estado del día anterior.
6. **El Vecino ve el plazo en días, no la fecha** (por plazo). Mejora futura: que el BFF obtenga el trámite de requests, que controla la propiedad, y después la `dueDate` de report por `requestId`.
