# Contratos verificables

Los contratos en prosa están en [`docs/contratos/`](../docs/contratos/README.md). Su versión verificable vive en el repositorio que la implementa, junto a la prueba que la exige, para que un cambio de código y su contrato viajen en el mismo PR.

| Contrato | Dónde | Prueba |
|---|---|---|
| API HTTP de cada servicio | `contracts/openapi.json` en bff, requests, catalog, report, audit, mq-admin y kafka-admin. notify no expone API propia | `OpenApiContractTest`: genera el OpenAPI desde los controladores y falla si no coincide con el publicado |
| Eventos de `requests.events` | `contracts/events/` en requests | `EventSchemaContractTest`: valida el JSON que publica el relay |
| Eventos de `audit.timeline` | `contracts/events/` en catalog, mq-admin y kafka-admin | `EventSchemaContractTest`: valida el JSON real de cada acción auditada |

Cada esquema de evento lleva su versión en el nombre (`request.created.v1.schema.json`) y sigue las reglas de [`kafka-topicos.md`](../docs/contratos/kafka-topicos.md): un campo nuevo, quitado o con otro tipo obliga a actualizar el esquema, y la sección 11 decide si sube `schemaVersion`.

Los consumidores (report y audit) aceptan campos que no conocen (sección 5, regla 4), así que un cambio compatible del productor no los rompe.
