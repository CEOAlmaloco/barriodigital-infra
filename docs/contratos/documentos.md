## Contrato: catálogo de documentos (EP3.5-03)

Define qué documentos genera BarrioDigital, para quién, con qué visibilidad y si cada uno es informativo o un acto oficial. Completa el enum `document.type` de [`dominio-modelo.md`](dominio-modelo.md), sección 5. Los genera notify a partir del comando `notification.requested` ([`comunicaciones.md`](comunicaciones.md), sección 7). Lo implementan EP3.5-11 (almacenamiento y descarga), EP3.5-23, EP3.5-29 (plantillas, verificación y firma de demostración), EP3.5-31, EP3.5-32 y EP3.5-37.

### 1. Clases

| `documentClass` | Qué es | Firma |
|---|---|---|
| `INFORMATIVO` | Acredita un hecho registrado en la plataforma (un ingreso, una recepción, un envío). No decide nada | Sin firma. Lleva código de verificación |
| `ACTO_OFICIAL` | Decisión o requerimiento de la municipalidad con efectos: abre un plazo, cierra el trámite o lo envía a otro órgano | En producción, firma electrónica avanzada con FirmaGob de la autoridad competente (D-09, Ley 19.799). En el laboratorio, firma de demostración con el certificado propio del proyecto (E5) |

**Leyenda de demostración.** Todo documento generado en el laboratorio dice, en el encabezado y en la página de verificación, "Documento de demostración. Sin validez oficial". Es la salvaguarda para que un documento con datos ficticios y firma propia no pueda presentarse como un acto real.

### 2. Catálogo

| `type` | Se genera | Destinatario | Visibilidad | Clase | Tarea |
|---|---|---|---|---|---|
| `COMPROBANTE` | Alta (T01) | Titular y representante | `PUBLICA` | `INFORMATIVO` | EP3.5-11 |
| `REQUERIMIENTO_ANTECEDENTES` | Solicitud de antecedentes (T05) | Titular y representante | `PUBLICA` | `ACTO_OFICIAL`: abre el plazo de subsanación (art. 31) | EP3.5-23 |
| `ACUSE_ANTECEDENTES` | Antecedentes recibidos (T06) | Titular y representante | `PUBLICA` | `INFORMATIVO` | EP3.5-23 |
| `RESPUESTA` | Cierre con respuesta pública: `RESUELTO`, `RECHAZADO`, `CERRADO_SIN_CONTACTO` y `DESISTIDO` por subsanación vencida | Titular y representante | `PUBLICA` | `ACTO_OFICIAL`: cierra el trámite y abre el plazo del recurso | EP3.5-23 |
| `OFICIO_DERIVACION` | Derivación a otro órgano (T19) | Órgano destino, con copia al titular y al representante | `PUBLICA` | `ACTO_OFICIAL`: remite los antecedentes (art. 14) | EP3.5-31 |
| `RESOLUCION_RECURSO` | Recurso resuelto (sección 7 de `procedimiento-estados.md`) | Titular y representante | `PUBLICA` | `ACTO_OFICIAL`, firmado por la autoridad que resolvió | EP3.5-32 |
| `CONSTANCIA_NOTIFICACION` | Comunicación `FORMAL` con fecha de efecto | Titular, representante y personal | `PUBLICA` | `INFORMATIVO`: prueba de la notificación, no un acto | EP3.5-37 |
| `EXPEDIENTE` | A pedido, como exportación del expediente | Quien lo pide: una parte o el personal | `PUBLICA` para las partes, con solo lo público; completo para el personal | `INFORMATIVO`, con índice verificable | EP3.5-37 |
| `CERTIFICADO_RESOLUCION` | Ya no se genera: lo reemplaza `RESPUESTA` | Los que existen se conservan | `PUBLICA` | `INFORMATIVO` | Vigente hasta EP3.5-23 |

No generan documento:
- `CANCELADO` y el desistimiento del titular: reciben un acuse por comunicación (V22 y V23);
- `DUPLICADO`: su comunicación lleva el folio del principal (V21);
- **orden de trabajo y acta de visita:** field las muestra en su vista imprimible (EP3.5-24). No son documentos de notify porque una orden cubre varios trámites y `document` pertenece a un solo trámite. Si deben guardarse con versión, EP3.5-29 amplía el modelo.

### 3. Reglas

1. **Contenido común.** Folio como identificador principal, fechas en hora de Chile con la zona explícita (DOC-01), versión, tipo y código de verificación (EP3.5-29).
2. **Quién firma.** El personal aparece por su unidad y su cargo. Un `ACTO_OFICIAL` lleva además el nombre y el cargo de la autoridad que lo firma (D-05, Ley 19.880 art. 17 b).
3. **Qué nunca llevan.** `interventionReason`, notas internas, datos de otras partes, el RUN completo ni datos de contacto. La dirección del problema sí, porque es parte de la solicitud.
4. **Versiones.** Regenerar crea una versión nueva y conserva la anterior (`dominio-modelo.md`, sección 5). Un recurso con resultado `MODIFICA` genera una `RESPUESTA` nueva, no reemplaza la anterior.
5. **Acceso.** Se descargan a través del BFF, que primero comprueba el acceso al trámite con requests (`dominio-contextos.md`, sección 3). El `TITULAR` y el `REPRESENTANTE` vinculados ven los documentos `PUBLICA`. `INTERESADO` y `ADHERENTE` no los descargan, porque llevan el nombre del titular: ven la respuesta en el historial público.
6. **Accesibilidad.** PDF etiquetado, con orden de lectura y texto alternativo (UX-06, EP3.5-29).
7. **Retención.** La define EP3.5-38 (DOC-06).

### 4. Integración real

| Plataforma | Interfaz prevista | En el laboratorio | Condición que la habilitaría |
|---|---|---|---|
| FirmaGob | Firma electrónica avanzada de cada `ACTO_OFICIAL` por la autoridad competente, antes de enviarlo | Firma de demostración con el certificado propio guardado como secreto (EP3.5-29) | Convenio con la Secretaría de Gobierno Digital y autoridades con certificado de firma avanzada |
| Gestor documental municipal | Copia de los actos oficiales en el gestor o en la Oficina de Partes, con su número como `external_ref` (`dominio-modelo.md`, sección 3.6) | Registro manual del número (EP3.5-37) | Integración con el sistema municipal (INT-05) |
