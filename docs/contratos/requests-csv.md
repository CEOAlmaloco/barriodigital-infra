<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Contrato: exportación CSV del listado (EP3-63)

### 1. Regla

La exportación es el listado de `GET /api/requests` (EP3-30) en un archivo, sin paginar. Usa **los mismos filtros, el mismo orden, la misma visibilidad y la misma proyección por rol** (EP3-04, sección 6). requests aplica todo eso con el mismo código del listado, así que no hay una segunda regla que pueda quedar distinta.

| Rol | Qué exporta |
|---|---|
| **Vecino** | Solo sus trámites, también al buscar o filtrar. Los filtros `assignee` y `contactDue` responden 403, igual que en el listado. Sin `assigneeId` ni `assigneeName`: ve "En atención" |
| **Funcionario y Admin** | Todos los trámites, con el correo del solicitante y el responsable |
| **Auditor** | Todos los trámites, sin el correo del solicitante |

**Por qué el Vecino también exporta:** es su propia información, y así guarda el registro de sus trámites sin tener que pedirlo a la municipalidad. No recibe más de lo que ya ve en `/tramites`.

### 2. Endpoint

```
GET /api/requests/export?status=&open=&from=&to=&assignee=&contactDue=&q=&procedureType=&sector=&sort=
```

Los parámetros y sus 400 son los del listado. `page` y `size` no aplican. Responde 200 con `text/csv; charset=UTF-8`, `Content-Disposition: attachment; filename="tramites-AAAA-MM-DD.csv"` (el día de Chile) y `Cache-Control: private, no-store`. Sin coincidencias, el archivo trae solo el encabezado.

### 3. Tope y consistencia

1. **Tope de 5000 trámites.** Si el resultado lo supera, responde 400 sin filas, nunca un archivo recortado: un CSV truncado se leería como completo en un informe. Quien exporta agrega filtros.
2. **Una sola instantánea.** requests lee con **un solo `SELECT`** limitado a 5001 filas, que recorre por lotes de 500. El conteo que decide el tope y las filas del archivo salen de esa misma lectura. Oracle entrega todas las filas de una consulta con la consistencia del momento en que empezó, así que un alta, un cambio de estado o un borrado concurrente no hace que un trámite salga dos veces ni que se pierda. Leer con varias páginas por offset sí lo haría.

### 4. Formato

1. **Para Excel en configuración chilena:** UTF-8 con BOM, separador `;`, fin de línea CRLF y cada celda entre comillas (RFC 4180). Fechas `yyyy-MM-dd HH:mm` en `America/Santiago`.
2. **Columnas:** Folio, Estado, Tipo, Título, Dirección, Sector, Ingreso, Última actualización, Plazo (días hábiles), En atención, Responsable, Solicitante, Correo solicitante, Motivo de rechazo. Un dato que el rol no ve queda como celda vacía. No lleva la descripción, la ubicación, la encuesta ni ids internos, por minimización (Ley 21.719).
3. **Fórmulas (CSV injection):** toda celda de texto cuyo primer carácter visible, después de espacios, caracteres de control e invisibles, es `=`, `+`, `-` o `@` (también en ancho completo), o que empieza con un carácter de control o invisible, lleva `'` adelante. El texto lo escriben vecinos y funcionarios, y sin esto Excel lo ejecutaría al abrirlo.

### 5. Errores

| Código | Causa |
|---|---|
| 400 | falta `X-User-Id`, un parámetro inválido como en el listado, o más de 5000 trámites |
| 403 | sin rol o con más de un rol, o el Vecino usa `assignee` o `contactDue` |

### 6. Capas

| Capa | Cambio | Issue |
|---|---|---|
| **requests** | `GET /api/requests/export` | EP3-63 |
| **BFF** | Ruta para los cuatro roles. Reenvía los filtros y la identidad, y devuelve el CSV con sus headers sin modificarlo | EP3-69 |
| **frontend** | "Exportar" en `/tramites` para los cuatro roles, con los filtros activos | EP3-70 |

### 7. Límites conocidos

1. **Sobre 5000 trámites** hay que exportar por partes, por fecha o por estado.
2. **Excel en inglés** espera coma: hay que importar el archivo indicando `;`.
3. **Sin auditoría de la descarga:** la exportación no publica un evento en `audit.timeline`.
