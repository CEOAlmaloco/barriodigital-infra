## Contrato: integraciones diferidas (EP3.5-02)

Define las integraciones que EP3.5 deja fuera de alcance, la interfaz prevista de cada una y la condición que la habilitaría. Ninguna se implementa en el laboratorio: no hay convenios, sistemas municipales reales ni tipos de trámite que las exijan (sección 2.6 del catálogo). ClaveÚnica está en [`identidad.md`](identidad.md), sección 4. Las plataformas de comunicación y documentos del Estado (CasillaÚnica, FirmaGob, DocDigital) son de EP3.5-03.

### 1. Regla común

Cada integración entra como un puerto en el servicio dueño del dato (`dominio-contextos.md`) y un adaptador por sistema externo, igual que la arquitectura hexagonal de requests. Mientras no se cumpla su condición:
- **no existe adaptador ni configuración;**
- **no se agregan columnas ni campos** que solo esa integración usaría.

Al habilitarla, la tarea que la implementa actualiza este contrato con su API, sus eventos y sus pruebas.

| Mejora | Servicio dueño | Prioridad del catálogo | Estado en EP3.5 |
|---|---|---|---|
| INT-04 Datos del Estado | requests | P3 | Interfaz documentada |
| INT-05 Sistemas municipales | requests y field | P2 | Referencias externas manuales (EP3.5-37) |
| INT-07 Multi-municipio | Todos | P3 | Fuera de alcance (D-18) |
| INT-08 Pagos | requests | P3 | Fuera de alcance |

### 2. INT-04: interoperabilidad con datos del Estado

**Para qué.** El art. 17, letra d), de la Ley 19.880 reconoce el derecho a no presentar documentos que emanen de otro órgano de la Administración y estén en su poder, y dispone que ese órgano los remita al que tramita el procedimiento. Es el fundamento de esta integración, no una capacidad que BarrioDigital ya tenga. Un trámite formal podría necesitar un certificado que otro organismo ya tiene.

**Interfaz prevista.**
- **Puerto en requests:** consultar un dato de una persona para un trámite. Recibe `requestId`, `personId` y el tipo de dato, y devuelve el documento o un resultado negativo.
- **Adaptador:** la Red de Interoperabilidad del Estado (PISEE).
- **Activación:** el tipo de trámite de catalog declara qué dato necesita. La consulta ocurre en la admisión, nunca en el alta del vecino.
- **Registro:** cada consulta queda en el historial interno con su base legal.
- **Minimización:** se guarda solo el documento que el trámite exige, como adjunto `INTERNA`.

**Condición para habilitarla:**
1. un tipo de trámite formal que exija un dato que ya tiene otro organismo (D-01, opción b);
2. un convenio de interoperabilidad con el organismo y la Secretaría de Gobierno Digital;
3. la base legal del tratamiento y una evaluación de impacto aprobadas (EP3.5-18).

### 3. INT-05: sistemas municipales existentes

**Inventario previsto y decisión por sistema:**

| Sistema | Interfaz prevista | Mientras no se integra |
|---|---|---|
| Oficina de Partes o gestor documental | El número de ingreso en `external_ref` y, si el sistema tiene API, el envío del documento al expediente | `external_ref` manual (EP3.5-37) |
| Inventario de activos | `asset_id` en la orden de trabajo, leído del inventario por API o importación | La dirección y la referencia de la orden |
| Bodega | Consumo de materiales por orden de trabajo | Notas de la visita |
| Juzgado de Policía Local | Número de causa en `external_ref` cuando un trámite termina en una denuncia | `external_ref` manual |
| Portal de Transparencia | La OIRS deriva una solicitud de acceso a información a su procedimiento de la Ley 20.285 y registra el número de la solicitud | Derivación manual con `external_ref` |

**Condición para habilitar cada sistema:**
1. un municipio real con ese sistema identificado y un encargado;
2. una API o un formato de exportación documentado;
3. un contrato y pruebas de la integración antes del código (INT-05).

### 4. INT-07: multi-municipio

**Decisión.** D-18: no en EP3.5. La red de oficinas de un municipio se resuelve con unidades y puntos de atención (EP3.5-14 y EP3.5-16), no con varios municipios.

**Qué exigiría:**
- **Datos:** un `municipality_id` en toda entidad, filtrado en cada consulta y en cada evento, como key adicional de las proyecciones.
- **Configuración:** catálogo, calendario y territorio separados por municipio.
- **Identidad:** un emisor o un tenant por municipio, y la identidad interna con el municipio (`identidad.md`, sección 1).
- **Marca:** logo, nombre y textos por municipio en el frontend.
- **Reportería:** sin agregados entre municipios.

**Condición para habilitarlo:** una decisión estratégica de servir a otro municipio. Su criterio de aceptación es que dos municipios de prueba no vean datos ni configuración del otro.

### 5. INT-08: pagos

**Interfaz prevista.**
- **Puerto de cobro en requests.**
- **Activación:** el tipo de trámite de catalog declara el monto o la regla de cálculo.
- **Pago:** se inicia después de la admisión, con estados `PENDIENTE`, `PAGADO`, `RECHAZADO` y `ANULADO`.
- **Adaptador:** la pasarela que use el municipio.
- **Conciliación diaria** con la pasarela (como ARQ-06).
- **Comprobante:** documento generado por notify.
- **Datos:** BarrioDigital no guarda datos de tarjetas ni de cuentas: los procesa la pasarela.

**Condición para habilitarla:**
1. un tipo de trámite con cobro aprobado por el municipio;
2. un contrato con la pasarela;
3. la conciliación definida con la unidad de finanzas.

No se implementa sin las tres (INT-08).
