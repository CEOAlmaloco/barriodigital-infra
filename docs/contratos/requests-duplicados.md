<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: aviso de posible duplicado (EP3-75)

### 1. Propósito

Evitar que un mismo problema genere varios trámites. El Vecino ve, antes de enviar el alta, los trámites abiertos parecidos cercanos, y decide si igual reporta: el aviso **no bloquea** el alta. El Funcionario y el Admin ven los posibles duplicados de un trámite ya ingresado, para detectarlos al admitirlo (EP3-05). Es solo lectura: no escribe, no genera eventos Kafka ni comandos RabbitMQ y no toma bloqueos.

### 2. Endpoints

```
GET /api/requests/duplicates?procedureType=bache&latitude=-37.8742&longitude=-71.5915&sector=ralco
GET /api/requests/{id}/duplicates
```

| Ruta | Roles | Base de la búsqueda |
|---|---|---|
| `/duplicates` | Vecino | `procedureType` obligatorio, y un punto, un sector o ambos |
| `/{id}/duplicates` | Funcionario, Admin | Tipo, punto y sector del trámite `{id}`, en cualquier estado, que se excluye del resultado |

El Auditor no las usa: es una herramienta operativa y no de auditoría. El Funcionario consulta cualquier trámite, no solo los suyos, porque los duplicados se revisan antes de tomarlo.

### 3. Regla de coincidencia

Un posible duplicado es un trámite **abierto** (no `RESUELTO`, `RECHAZADO` ni `CANCELADO`) del **mismo `procedureType`** que cumple una de estas condiciones:

1. **Por distancia:** si hay punto, tiene punto a una distancia igual o menor que el radio. La distancia se calcula con Haversine.
2. **Por sector:** si hay un sector comparable, es del mismo sector. Si además hay punto, solo cuentan los trámites **sin punto**: uno con punto del mismo sector ya se evaluó por distancia.

El sector `otro` ("Otro sector de la comuna") **no es comparable**: abarca demasiado para indicar un duplicado. No impide buscar por cercanía. Sin punto y con `otro`, no hay con qué comparar y la lista viene vacía, no con error.

**Radio y tope:** `barriodigital.duplicates.radius-meters` (150 m) y `max-results` (5), en la configuración de requests. Se validan al arrancar: de 10 a 2000 m y de 1 a 20. El cliente no elige el radio, porque uno grande permitiría recorrer la comuna.

### 4. Orden y tope

1. Primero los que coinciden por distancia, de la **distancia exacta** menor a la mayor.
2. Después los que coinciden por sector, del más reciente al más antiguo.
3. Los empates se ordenan por fecha de ingreso descendente y después por `id`, así el orden es estable.

El tope se aplica **después** de ordenar los dos grupos juntos: no se recortan candidatos antes. La consulta a la base filtra por una caja de latitud y longitud que contiene todo el círculo del radio, y la distancia exacta se calcula sobre ese resultado, así un recorte previo no puede dejar fuera al más cercano.

### 5. Respuesta

Lista JSON, vacía si no hay coincidencias:

```json
[
  {
    "id": null,
    "folio": "BD-2026-000123",
    "procedureType": "bache",
    "procedureLabel": "Bache en calle",
    "status": "EN_GESTION",
    "sector": "ralco",
    "distanceMeters": 40,
    "createdDate": "2026-11-11",
    "hasAssignee": null,
    "mine": false
  }
]
```

| Campo | Vecino | Funcionario, Admin |
|---|---|---|
| `folio`, `procedureType`, `procedureLabel`, `status`, `sector` | Sí | Sí |
| `distanceMeters` | Redondeada a 10 m; `null` si coincidió por sector | Igual |
| `createdDate` | Día de ingreso en `America/Santiago` | Igual |
| `mine` | Si el trámite es suyo | `null` |
| `id`, `hasAssignee` | `null` | Sí, para abrir el detalle |

**Minimización de datos (leyes 19.628 y 21.719):** la respuesta nunca lleva datos del solicitante, descripción, dirección, referencia, coordenadas, imagen ni responsable. La descripción y la dirección pueden contener datos personales, y el punto de un trámite puede ubicar una vivienda. El Vecino recibe el folio para citarlo en una consulta, pero sigue sin poder abrir un trámite ajeno (404, EP3-04).

### 6. Errores

Orden: identidad, rol, existencia del trámite y parámetros.

| Código | Causa |
|---|---|
| 400 | falta `X-User-Id` (`USER_ID_REQUIRED`) |
| 403 | el rol no corresponde a la ruta |
| 404 | el trámite `{id}` no existe (`REQUEST_NOT_FOUND`) |
| 400 | `procedureType` ausente o con mal formato |
| 400 | solo una coordenada, una coordenada que no es un número finito, o un punto fuera de la comuna |
| 400 | `sector` que no es una clave del alta |
| 400 | no llega ni punto ni sector |

### 7. Oracle

Índice `idx_municipal_requests_type_status (procedure_type, status)`, que Hibernate crea por nombre al arrancar. No hay columnas ni tablas nuevas.

### 8. Capas

| Capa | Cambio | Issue |
|---|---|---|
| **requests** | Las dos rutas de la sección 2, con la regla, el orden y la respuesta de las secciones 3 a 5 | EP3-75 |
| **BFF** | Proxy de las dos rutas con sus roles, reenviando parámetros e identidad | EP3-77 |
| **frontend** | Aviso no bloqueante en el alta y panel de posibles duplicados en el detalle para el personal | EP3-79, EP3-84 |
| **Gateway** | Sin cambios: las dos rutas son `GET` y entran por `/{proxy+}` | |

### 9. Límites conocidos

1. **Solo compara punto o sector.** Un trámite sin punto y sin sector comparable no aparece, y no se compara el texto de la dirección.
2. **El tipo se compara exacto:** un `alumbrado` no se cruza con un `otro` que describe lo mismo.
3. **No distingue la precisión del punto:** un punto `APROXIMADO` se trata igual que uno `EXACTO`.
4. **Ubicación aproximada por muchas consultas:** con consultas desde puntos distintos se podría acotar dónde está un trámite ajeno. El redondeo a 10 m, el radio fijo y el tope lo dificultan, pero no lo impiden.
5. **Fuera de alcance:** seguir o apoyar un trámite ajeno, como en FixMyStreet, requiere decidir qué parte de un trámite es pública y avisar a quien no es el titular. Marcar un trámite como duplicado de otro o fusionarlos cambia el modelo del expediente. Ambos quedan como trabajo futuro.
