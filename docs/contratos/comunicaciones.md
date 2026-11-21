## Contrato: matriz de comunicaciones (EP3.5-03)

Define qué se comunica en cada paso del procedimiento: a quién, por qué canal, con qué valor y con qué plantilla, desde qué tarea existe cada comunicación, el comando que requests envía a notify y los eventos con que notify informa la entrega. Es la base de EP3.5-09 (interfaz veraz), EP3.5-10 (correo y SMS), EP3.5-23, EP3.5-24, EP3.5-27 (reglas y plantillas), EP3.5-28 (avisos en la aplicación) y EP3.5-37 (notificación formal). Los estados y transiciones están en [`procedimiento-estados.md`](procedimiento-estados.md), los plazos en [`procedimiento-plazos.md`](procedimiento-plazos.md) y los documentos en [`documentos.md`](documentos.md).

**Regla para la interfaz (UX-03, EP3.5-09).** Un texto solo promete una comunicación que esta matriz define y cuya columna "Desde" ya está desplegada. Hoy, antes de EP3.5-10, el correo es simulado (`EMAIL_MODE=logging`), así que la interfaz no promete ningún envío.

### 1. Tipos

| `kind` | Qué es | ¿Se desactiva? | Constancia |
|---|---|---|---|
| `INFORMATIVA` | Seguimiento: avisa un hecho que la persona puede consultar en el detalle | Sí, por preferencia (EP3-65, y por canal y categoría en EP3.5-27) | Estado de entrega, con el destino enmascarado |
| `FORMAL` | Comunica un acto que abre un plazo, exige una actuación o cierra el trámite. Su fecha de efecto inicia los plazos de subsanación y de recurso (`procedimiento-plazos.md`, sección 2) | Nunca. La persona solo elige el medio (COM-06) | Destino usado, huella del contenido, envío y fecha de efecto (sección 4.6) |

Toda comunicación de un cierre recurrible es `FORMAL`, porque desde ella corre el plazo del recurso.

### 2. Destinatarios

| Código | Quién |
|---|---|
| `PARTE` | En una `FORMAL`, el `REPRESENTANTE` vinculado si existe, y si no el `TITULAR`; el otro recibe una copia `INFORMATIVA` (sección 4.4). En una `INFORMATIVA`, ambos |
| `PUBLICO` | `INTERESADO` y `ADHERENTE` vinculados, y los titulares de los trámites `DUPLICADO` del trámite. Solo reciben comunicaciones `INFORMATIVA` públicas, sin datos del titular |
| `RESPONSABLE` | El funcionario responsable del trámite |
| `JEFATURA` | La jefatura de la unidad responsable (EP3.5-13 y EP3.5-14). Hasta que exista, el Admin |
| `UNIDAD_DESTINO` | La bandeja de la unidad que recibe una derivación interna |
| `CUADRILLA` | Los integrantes de la cuadrilla asignada a la orden |
| `REVISOR`, `AUTORIDAD` | Quien revisa y quien resuelve un recurso (`procedimiento-estados.md`, sección 7.2) |

### 3. Canales

| `channel` | Qué es | Desde |
|---|---|---|
| `CORREO` | Correo real a direcciones de prueba, con SES en sandbox o un SMTP gratuito (E4) | EP3.5-10 |
| `SMS` | SMS simulado, que llega a una bandeja de prueba (E4) | EP3.5-10 |
| `PRESENCIAL` | Constancia registrada en la oficina cuando la persona se presenta (art. 46) | EP3.5-23 |
| `APLICACION` | Centro de avisos dentro de la aplicación | EP3.5-28 |
| `PUSH` | Push del navegador con claves propias (E4) | EP3.5-28 |
| `CASILLA_UNICA` | Adaptador simulado de la plataforma de notificaciones del Estado (sección 9) | EP3.5-37 |
| `CARTA` | Carta certificada, registrada a mano con su número de envío (art. 46) | EP3.5-37 |

**Avisos al personal.** Hasta EP3.5-28, los avisos al personal no son mensajes de notify: son bloques de `/inicio` y de las bandejas, calculados al consultar (EP3-04, sección 7). Desde EP3.5-28 llegan también al centro de avisos. El personal no recibe correos: el directorio no guarda su correo (`dominio-modelo.md`, sección 4.2).

### 4. Reglas de destino

#### 4.1 Contacto que sirve para avisar

| Contacto | ¿Sirve? |
|---|---|
| `CORREO` `DECLARADO` o `VERIFICADO` | Sí |
| `TELEFONO` `VERIFICADO` | Sí (E9) |
| `TELEFONO` `DECLARADO` | No |
| Cualquiera `REBOTADO` | No, hasta que la persona lo registre de nuevo (`dominio-modelo.md`, sección 3.2) |

Hasta EP3.5-15, el único contacto es `solicitante_email`, que se trata como un correo `DECLARADO`.

#### 4.2 Elección del canal

notify elige el canal entre los de la fila de la matriz, en su orden, con el contacto preferido de cada tipo que obtiene de requests (`dominio-contextos.md`, sección 4). Hasta EP3.5-27, un `SMS` se envía solo si la persona no tiene un correo que sirva; desde EP3.5-27, según su preferencia por canal. `APLICACION` y `PUSH` se suman a los demás canales, no los reemplazan.

#### 4.3 Preferencias

- **`INFORMATIVA`:** requests no publica el comando si la persona la desactivó, como hace hoy con `emailEnabled` (EP3-65).
- **`FORMAL`:** requests siempre lo publica. Desactivar los avisos no la detiene. Esto cambia la regla actual de EP3-65 para el rechazo, que pasa a ser `FORMAL` con EP3.5-23.

#### 4.4 Representante

Si el trámite tiene un `REPRESENTANTE` vinculado, la comunicación `FORMAL` va al representante y es la que produce efecto (art. 22); el titular recibe la misma comunicación como `INFORMATIVA`. Sin representante, la `FORMAL` va al titular.

#### 4.5 Sin destino

| Tipo | Si la persona no tiene un contacto que sirva |
|---|---|
| `INFORMATIVA` | notify la registra `SIN_DESTINO` y no hay alternativa. La persona ve el hecho en el detalle y en la consulta por folio |
| `FORMAL` | notify la registra `SIN_DESTINO`. requests deja la comunicación **pendiente por otro medio**, visible para el responsable (fila P18), y el plazo que depende de ella no empieza. Se practica en la oficina cuando la persona se presenta (`PRESENCIAL`) o, desde EP3.5-37, por carta certificada |

Un `REBOTADO` o `FALLIDO` en una `FORMAL` sigue la misma regla (`procedimiento-plazos.md`, sección 2, regla 3).

#### 4.6 Qué se guarda de cada envío

notify guarda, por envío: plantilla y su versión, `kind`, destinatario (`personId` y papel), canal, estado y sus fechas.
- **`FORMAL`:** además el destino completo usado y la huella SHA-256 del contenido enviado. Es la prueba de la comunicación (COM-04) y responde lo que `dominio-contextos.md` deja abierto en su sección 4.
- **`INFORMATIVA`:** solo el destino enmascarado (`v***@example.com`, `+569****5678`).

La retención de estos registros es de EP3.5-38.

#### 4.7 Contenido

- Enlace al detalle del trámite, folio y unidad responsable con su cargo, nunca el nombre del funcionario (E9). Un acto oficial lleva el nombre y el cargo de la autoridad que lo firma (D-05).
- Nunca `interventionReason`, notas internas, datos de otras partes, el RUN ni datos de contacto.
- Correo en HTML accesible con versión de texto (COM-01). SMS de hasta 160 caracteres, con el folio y el enlace, sin datos personales.

### 5. Matriz para el vecino y las partes

"Desde" es la tarea que hace real la fila. "Vigente" significa que existe hoy, con el correo simulado; se vuelve real con EP3.5-10.

| # | Hecho | Destinatario | Tipo | Canal | Plantilla | Documento | Desde |
|---|---|---|---|---|---|---|---|
| V01 | Alta (T01) | `PARTE` | `INFORMATIVA` | `CORREO`, `APLICACION` | `INGRESO_CONFIRMADO` | `COMPROBANTE`, enlazado | EP3.5-10 (correo), EP3.5-11 (comprobante), EP3.5-28 (aplicación) |
| V02 | Primera asignación | `PARTE` | `INFORMATIVA` | `APLICACION` | `EN_ATENCION` | - | EP3.5-28. Hoy, solo el hito del historial. Una reasignación no se comunica (EP3-04, sección 6.2) |
| V03 | Admisión (T02, T04) | `PARTE` | `INFORMATIVA` | `CORREO` | `TRAMITE_ADMITIDO` | - | Vigente (`email.admitted`) |
| V04 | Espera de cupo (T03) | `PARTE` | `INFORMATIVA` | `CORREO` | `EN_ESPERA_CUPO`, con la fecha estimada | - | EP3.5-35 |
| V05 | Paso a `EN_GESTION` (T09) | `PARTE` | `INFORMATIVA` | `APLICACION` | `EN_GESTION` | - | EP3.5-28. Sin correo: es un paso interno, y la vuelta desde `EN_TERRENO` (T11) no se comunica |
| V06 | Visita programada (T10) | `PARTE` | `INFORMATIVA` | `CORREO`, `SMS` | `VISITA_PROGRAMADA`, con la fecha si la orden la tiene | - | Vigente sin fecha (`email.visit`); EP3.5-24 suma la fecha |
| V07 | Reprogramación de la visita | `PARTE` | `INFORMATIVA` | `CORREO`, `SMS` | `VISITA_REPROGRAMADA` | - | EP3.5-24 |
| V08 | Solicitud de antecedentes (T05) | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `REQUERIMIENTO_ANTECEDENTES`, con la lista, el plazo y la consecuencia de no responder (art. 31) | `REQUERIMIENTO_ANTECEDENTES` | EP3.5-23 |
| V09 | Subsanación por vencer, un día hábil antes | `PARTE` | `INFORMATIVA` | `CORREO`, `SMS` | `RECORDATORIO_ANTECEDENTES` | - | EP3.5-28 |
| V10 | Antecedentes recibidos (T06) | `PARTE` | `INFORMATIVA` | `CORREO` | `ACUSE_ANTECEDENTES` | `ACUSE_ANTECEDENTES` | EP3.5-23 |
| V11 | Comentario del vecino | `PARTE` | - | - | Sin mensaje: el detalle muestra el comentario registrado como acuse | - | Vigente |
| V12 | Suspensión o reanudación por espera de un tercero | `PARTE` | `INFORMATIVA` | `CORREO` | `PLAZO_SUSPENDIDO`, `PLAZO_REANUDADO`, con la fecha nueva | - | EP3.5-22. Las suspensiones por subsanación y por cupo se comunican con V04 y V08 |
| V13 | Prórroga aprobada | `PARTE` | `INFORMATIVA` | `CORREO` | `PLAZO_PRORROGADO`, con la fecha nueva y el motivo | - | EP3.5-22 |
| V14 | Derivación interna | `PARTE` | `INFORMATIVA` | `APLICACION` | `CAMBIO_DE_UNIDAD` | - | EP3.5-28, con la derivación de EP3.5-31 |
| V15 | Corrección de un dato que el vecino ve | `PARTE` | `INFORMATIVA` | `CORREO` | `DATOS_CORREGIDOS` | - | EP3.5-14 |
| V16 | Resolución (T12) | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `RESPUESTA_RESUELTO`, con la respuesta y cómo reclamar | `RESPUESTA` | Vigente sin respuesta (`email.resolved`); EP3.5-23 |
| V17 | Rechazo (T13) | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `RESPUESTA_RECHAZADO`, con el motivo, la respuesta y cómo reclamar | `RESPUESTA` | Vigente sin respuesta (`email.rejected`); EP3.5-23 |
| V18 | Derivación a otro órgano (T19) | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `DERIVACION_EXTERNA`, con el órgano y su contacto (art. 14) | `OFICIO_DERIVACION` | EP3.5-31 |
| V19 | Desistimiento por subsanación vencida (T07) | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `DESISTIMIENTO_DECLARADO` | `RESPUESTA` | EP3.5-23 |
| V20 | Cierre sin contacto (T15) | `PARTE` | `FORMAL` | Todos los que sirvan | `CIERRE_SIN_CONTACTO`, con los intentos y cómo reclamar | `RESPUESTA` | EP3.5-23 |
| V21 | Marcado como duplicado (T16) | `PARTE` del duplicado | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `DUPLICADO_VINCULADO`, con el folio principal | - | EP3.5-30 |
| V22 | Cancelación (T08) | `PARTE` | `INFORMATIVA` | `CORREO` | `ACUSE_CANCELACION` | - | EP3.5-10 |
| V23 | Desistimiento del titular (T14) | `PARTE` | `INFORMATIVA` | `CORREO` | `ACUSE_DESISTIMIENTO` | - | EP3.5-23 |
| V24 | Cierre, para los demás | `PUBLICO` | `INFORMATIVA` | `CORREO` | `CIERRE_PUBLICO`, con el estado de cierre y la respuesta pública | - | EP3.5-30 |
| V25 | Reapertura (T18, T20) | `PARTE` y `PUBLICO` | `INFORMATIVA` | `CORREO` | `REAPERTURA` | - | EP3.5-32 |
| V26 | Recurso presentado | `PARTE` | `INFORMATIVA` | `CORREO` | `ACUSE_RECURSO`, con el plazo para resolver | - | EP3.5-32 |
| V27 | Recurso resuelto | `PARTE` | `FORMAL` | `CORREO`, `SMS`, `PRESENCIAL` | `RESOLUCION_RECURSO`, con el resultado, el fundamento y si agota la vía administrativa | `RESOLUCION_RECURSO` | EP3.5-32 |
| V28 | Invitación a la encuesta, al resolver | `PARTE` | `INFORMATIVA` | `CORREO` | `INVITACION_ENCUESTA` | - | EP3.5-50 (D-19) |

Desde EP3.5-37, `CASILLA_UNICA` pasa a ser el primer canal de toda fila `FORMAL`, y `CARTA` el último.

Los códigos de verificación de contacto (EP3.5-15) no son comunicaciones del trámite: son transaccionales, no se desactivan y no están en la matriz.

### 6. Avisos al personal y a las cuadrillas

| # | Hecho | Destinatario | Dónde | Desde |
|---|---|---|---|---|
| P01 | Asignación o reasignación | `RESPONSABLE` nuevo | "Mis asignados" en `/inicio`; centro de avisos | Vigente; EP3.5-28 |
| P02 | Comentario del vecino | `RESPONSABLE` | Centro de avisos, en menos de un minuto (COM-07) | EP3.5-28 |
| P03 | Antecedentes recibidos | `RESPONSABLE` | `/inicio`; centro de avisos | EP3.5-23; EP3.5-28 |
| P04 | Subsanación vencida | `RESPONSABLE` | Bandeja de desistimientos por confirmar | EP3.5-23 |
| P05 | Cancelación o desistimiento del titular | `RESPONSABLE` y `JEFATURA` | `/inicio`; centro de avisos | EP3.5-23; EP3.5-28 |
| P06 | Orden cancelada por el cierre del trámite | `JEFATURA` | `/inicio`; centro de avisos | EP3.5-24; EP3.5-28 |
| P07 | Orden asignada | `CUADRILLA` | "Mis órdenes" (`mine=true`); centro de avisos y push | EP3.5-24; EP3.5-28 |
| P08 | Orden no aceptada en plazo | `JEFATURA` | `/inicio` | EP3.5-24 |
| P09 | Orden rechazada por la cuadrilla, visita fallida o validación rechazada | `JEFATURA` | `/inicio` | EP3.5-24 |
| P10 | Plazo por vencer | `RESPONSABLE` | `/inicio`; centro de avisos, una sola vez (COM-07) | Vigente (EP3-52); EP3.5-28 |
| P11 | Plazo vencido | `JEFATURA` | `/inicio`; bandeja de jefatura; centro de avisos | Vigente para el Admin; EP3.5-43; EP3.5-28 |
| P12 | Prórroga solicitada | `JEFATURA` | `/inicio` | EP3.5-22 |
| P13 | Prórroga decidida o vencida | `RESPONSABLE` | `/inicio` | EP3.5-22 |
| P14 | Derivación interna recibida | `UNIDAD_DESTINO` | Bandeja de la unidad | EP3.5-31 |
| P15 | Recurso presentado | `REVISOR` y `AUTORIDAD` | `/inicio` | EP3.5-32 |
| P16 | Recurso a 5 días hábiles de su plazo de resolución | `AUTORIDAD` | `/inicio` | EP3.5-32 |
| P17 | Reapertura | `RESPONSABLE`, o la bandeja de la unidad si ya no tiene | `/inicio` | EP3.5-32 |
| P18 | Comunicación `FORMAL` sin destino, rebotada o fallida | `RESPONSABLE` | Historial interno y "Notificación pendiente por otro medio" en `/inicio` | EP3.5-10 (rebote); EP3.5-23 (pendiente) |
| P19 | Rebote o falla de una `INFORMATIVA` | `RESPONSABLE` | Historial interno | EP3.5-10 |

### 7. Comando `notification.requested`

Las comunicaciones nuevas de la matriz usan **un solo comando de RabbitMQ**, en vez de un `email.*` por fila. Así EP3.5-27 cambia reglas y plantillas sin agregar colas.

**Topología** (EP2-02). EP3.5-10 la agrega a [`rabbit-topologia.md`](rabbit-topologia.md) y a las claves de YAML con que mq-admin protege las colas del sistema:

| Exchange | Tipo | Routing key | Cola | Argumentos |
|---|---|---|---|---|
| `cmd.direct` | direct | `notification.requested` | `q.cmd.notification` | `x-dead-letter-exchange=cmd.dead.dlx`, `x-dead-letter-routing-key=notification.dead` |
| `cmd.topic` | topic | `notification.*` | `q.cmd.notification` | los mismos |
| `cmd.dead.dlx` | direct | `notification.dead` | `q.cmd.notification.dlq` | ninguno |

**Sobre.** El de EP2-01, sección 2, con `type = notification.requested`. `correlationId` es el `requestId`.

**Payload:**

| Campo | Tipo | Regla |
|---|---|---|
| `requestId` | uuid | No nulo |
| `folio` | string | No nulo |
| `templateCode` | enum | Una plantilla de las secciones 5 y 6 |
| `kind` | enum | `INFORMATIVA` o `FORMAL` |
| `recipientRole` | enum | `TITULAR`, `REPRESENTANTE`, `INTERESADO` o `ADHERENTE` |
| `recipientPersonId` | uuid | Nulo hasta EP3.5-15 |
| `recipientEmail` | string | Transitorio. Se retira con los mismos tres pasos de `solicitanteEmail` (`dominio-contextos.md`, sección 5.3) |
| `documentType` | enum | El documento que notify genera y enlaza antes de enviar (`documentos.md`). Nulo si la fila no tiene documento |
| `variables` | objeto | Los datos de la plantilla. Todos opcionales: `procedureLabel`, `orgUnitName`, `staffPosition`, `dueDate`, `scheduledFor`, `publicResponse`, `rejectionReason`, `remedyItems` (lista), `primaryFolio`, `organizationName`, `appealDueDate` y `authorityName` |

Reglas:
1. requests publica el comando por el outbox de EP3.5-10, en la misma transacción de la acción.
2. requests aplica las preferencias a las `INFORMATIVA` (sección 4.3). notify elige el canal y resuelve el contacto (sección 4.2).
3. notify reconoce el comando por `eventId` con su idempotencia persistente (EP3.5-10), y genera el documento con ese `eventId` como `source_event_id` (`dominio-modelo.md`, sección 5).
4. `variables` nunca lleva datos de contacto, `interventionReason`, notas internas ni datos de otras partes. Sí lleva el texto público que la plantilla muestra (la respuesta, la lista de antecedentes), que ya es para la persona.
5. Un comando malformado (sin `templateCode`, con un `kind` que no corresponde a la plantilla) es no recuperable y va a su DLQ (EP2-03).

**Transición.** Los comandos actuales (`email.admitted`, `email.visit`, `email.resolved`, `email.rejected`, `certificate.receipt` y `certificate.resolved`) siguen hasta que EP3.5-27 los migre a este comando; `crew.ticket` lo retira field (`field.md`, sección 8). Orden de despliegue: primero notify acepta `notification.requested`, después requests lo publica.

### 8. Tópico `notify.events`

notify informa el resultado de cada envío. Lo necesita requests, que es dueño del contacto y de los plazos: un rebote marca el correo como rebotado (EP3.5-10, criterio 3) y la fecha de efecto inicia los plazos de subsanación y de recurso.

| Parámetro | Valor |
|---|---|
| Productor | notify, por outbox en su base de datos (EP3.5-10) |
| Key | `notificationId`: ordena los estados de un mismo envío |
| Consumidores | requests (`requests-group`) y audit (`audit-group`) |
| DLT | `notify.events.requests.DLT` y `notify.events.audit.DLT` |
| Parámetros | Los de `requests.events` (EP3-01, sección 2). Cumple la regla entre retenciones con los mismos valores |

Lo crea kafka-admin como tópico del sistema, como `field.events`.

**Evento `notification.status-changed`**, versión 1, con el sobre de EP3-01, sección 4, `producer = notify`, `sequence` del outbox de notify y el actor de sistema `{ "id": "notify", "name": "Sistema", "role": "Sistema" }`.

| Campo | Tipo | Regla |
|---|---|---|
| `notificationId` | uuid | No nulo |
| `commandId` | uuid | `eventId` del comando que originó el envío. requests lo usa para saber a qué acción corresponde |
| `requestId` | uuid | No nulo en las comunicaciones del trámite |
| `templateCode`, `kind`, `recipientRole` | enum | Los del comando |
| `recipientPersonId` | uuid | Nulo hasta EP3.5-15 |
| `contactId` | uuid | El `person_contact` usado. Nulo si es `SIN_DESTINO` o antes de EP3.5-15 |
| `channel` | enum | Sección 3. Nulo si es `SIN_DESTINO` |
| `status` | enum | `ENVIADO`, `ENTREGADO`, `REBOTADO`, `RECHAZADO`, `FALLIDO` o `SIN_DESTINO` |
| `effectiveDate` | fecha | Solo en una `FORMAL` con efecto (`procedimiento-plazos.md`, sección 2) |
| `documentIds` | lista de uuid | Documentos enlazados. Vacía si no hay |

| `status` | Significado |
|---|---|
| `ENVIADO` | El proveedor aceptó el mensaje |
| `ENTREGADO` | El proveedor confirmó la entrega. Con un SMTP sin acuse de entrega, el envío queda en `ENVIADO` |
| `REBOTADO` | El destino no existe o no acepta mensajes. Es una falla permanente |
| `RECHAZADO` | El proveedor no aceptó el mensaje, o la persona lo marcó como spam |
| `FALLIDO` | Se agotaron los reintentos de una falla temporal (EP2-03) |
| `SIN_DESTINO` | La persona no tiene un contacto que sirva (sección 4.5) |

No viajan el destino, el contenido ni la huella: quedan en notify.

**Qué hace requests:** registra el resultado en el historial interno; con `REBOTADO` y `contactId`, deja el contacto `REBOTADO` (hasta EP3.5-15, deja de usar ese correo para avisos); con `effectiveDate`, calcula `remedyDueDate` o `appealDueDate`; y con una `FORMAL` sin efecto, deja la comunicación pendiente por otro medio (sección 4.5).

**Orden de despliegue:**
1. kafka-admin crea `notify.events` y sus DLT.
2. requests y audit se despliegan con su consumo.
3. notify publica.

### 9. Integración real

| Plataforma | Interfaz prevista | En el laboratorio | Condición que la habilitaría |
|---|---|---|---|
| CasillaÚnica (plataforma de notificaciones del Estado) | Canal `CASILLA_UNICA` en notify: envía la `FORMAL` al domicilio digital único de la persona y recibe la fecha de envío, de la que sale la fecha de efecto (art. 46) | Adaptador simulado: registra el envío y la persona lo ve en la aplicación como su casilla (EP3.5-37) | Procedimiento registrado en CPAT (INT-01), convenio con la Secretaría de Gobierno Digital y la fase de notificaciones electrónicas de la Ley 21.180 vigente para el municipio |
| DocDigital (comunicaciones entre órganos) | Envío del `OFICIO_DERIVACION` al órgano destino de una derivación (INT-02) | Correo al buzón de prueba del órgano, o registro manual del envío (EP3.5-31) | Convenio y adhesión del municipio y del órgano destino |

### 10. Pruebas

Cada fila de las secciones 5 y 6 tiene una prueba automatizada en la tarea de su columna "Desde" (COM-08). La prueba parte del hecho y comprueba el comando publicado, con su `templateCode`, su `kind` y su destinatario, o el aviso visible para el personal. Además:
- una `FORMAL` se publica aunque la persona desactivó los avisos;
- una `FORMAL` sin destino queda pendiente y no inicia su plazo;
- un rebote antes de la fecha de efecto la anula;
- ningún comando ni evento lleva datos de contacto.

EP3.5-25 cubre los recorridos de extremo a extremo.

### 11. Límites conocidos

1. **Sin correo al personal.** Los avisos al personal llegan por la aplicación, no por correo.
2. **Entrega sin acuse.** Con un SMTP gratuito sin informe de entrega, un correo queda en `ENVIADO` y nunca en `ENTREGADO`.
3. **Comunicación formal sin canal electrónico.** Hasta EP3.5-37, una `FORMAL` a una persona sin correo ni teléfono verificado se practica solo cuando se presenta en una oficina. Hasta entonces, el plazo que depende de ella no corre.
4. **SMS simulado.** Ningún SMS sale del laboratorio (E4).
5. **Comandos antiguos.** Hasta que EP3.5-27 migre los `email.*`, conviven dos formas de comando hacia notify.
