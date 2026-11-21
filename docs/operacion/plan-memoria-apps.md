# Plan de memoria de la EC2 de apps

Reparte la memoria de la EC2 de apps entre los nueve servicios de EP3.5 y el antivirus de EP3.5-11. Los valores son una estimación: EP3.5-05 los mide en la `t3.large` y ajusta los `mem_limit` de `apps/compose.ec2.yml` y `apps/compose.ec2.jars.yml`. field (EP3.5-24) y el antivirus (EP3.5-11) entran con el valor que deje la medición.

## 1. Situación actual

En la `t3.medium` (4 GiB, 4.096 MiB), los `mem_limit` de los ocho servicios suman **4.096 MiB**, toda la RAM de la instancia. No queda reserva para el sistema operativo, Docker ni la caché de disco: si todos los servicios llegaran a su límite a la vez, el kernel terminaría procesos antes de que Docker aplique los límites.

| Servicio | `mem_limit` | Heap (`compose.ec2.yml`) |
|---|---|---|
| bff | 512 MiB | 384 MiB |
| requests | 768 MiB | 512 MiB |
| catalog | 512 MiB | 384 MiB |
| notify | 512 MiB | 384 MiB |
| report | 512 MiB | 384 MiB |
| audit | 384 MiB | 256 MiB |
| mq-admin | 384 MiB | 256 MiB |
| kafka-admin | 512 MiB | 384 MiB |
| **Total** | **4.096 MiB** | |

## 2. Reparto en la `t3.large`

8 GiB (8.192 MiB), según E1 del backlog.

| Componente | `mem_limit` | Motivo |
|---|---|---|
| bff | 512 MiB | Sin cambio |
| requests | 768 MiB | Sin cambio. Suma personas y el consumo de `field.events`; la medición dirá si alcanza |
| catalog | 512 MiB | Sin cambio |
| notify | 768 MiB | Suma base de datos, cliente de S3 e idempotencia persistente, además de la generación de PDF |
| report | 512 MiB | Sin cambio |
| audit | 384 MiB | Sin cambio |
| mq-admin | 384 MiB | Sin cambio |
| kafka-admin | 512 MiB | Sin cambio |
| field | 512 MiB | Servicio nuevo, del tamaño de catalog |
| **Servicios** | **4.864 MiB** | |
| Antivirus (ClamAV) | 1.536 MiB | Sección 3 |
| Sistema operativo, Docker y agentes | 1.024 MiB | Incluye el agente de CloudWatch de EP3.5-19 |
| **Total asignado** | **7.424 MiB** | |
| Margen | 768 MiB | Para la caché de disco y para picos |

El heap de cada servicio queda en torno al 70 % de su límite, como hoy: el resto lo usan metaspace, hilos, buffers directos y el código nativo de la JVM. `compose.ec2.jars.yml` lo expresa con `-XX:MaxRAMPercentage=65.0`, que se ajusta solo con el límite.

## 3. Antivirus

La documentación de ClamAV recomienda entre 3 y 4 GiB para el servidor o el contenedor. Solo cargar las firmas ocupa más de 1,2 GiB, y la recarga diaria duplica ese consumo por un momento ([ClamAV en Docker](https://docs.clamav.net/manual/Installing/Docker.html)). En este plan corre con menos de lo recomendado, con estas medidas:

- **`ConcurrentDatabaseReload no`:** evita duplicar la memoria al recargar. Durante la recarga, el análisis espera y los adjuntos quedan `PENDIENTE` unos segundos (`contratos/dominio-modelo.md`, sección 3.5).
- **Tamaño máximo de análisis igual a la cuota de adjuntos de EP3.5-11**, para que un archivo grande no dispare la memoria.
- **Un solo contenedor**, sin réplica.

Si la medición de EP3.5-05 muestra que ClamAV necesita más de 1.536 MiB, o que el total no deja margen, el antivirus no se despliega. Los adjuntos quedan `SIN_ANALISIS` y el límite se declara, como prevé EP3.5-11.

## 4. Medición (EP3.5-05)

1. Levantar el compose completo en la `t3.large`, con field cuando exista.
2. Correr los flujos de EP2 y EP3 con la carga de demo (`apps/scripts/seed-demo.ps1` y `scripts/seed-messaging.ps1`) y registrar el pico de memoria de cada contenedor con `docker stats`.
3. Fijar cada `mem_limit` en el pico medido más un 25 %, redondeado hacia arriba a múltiplos de 128 MiB.
4. Comprobar que el total asignado deja al menos 512 MiB de margen. Si no, el primer recorte es el antivirus (sección 3).
5. Guardar la medición en `docs/evidencias/`.

Un contenedor que se reinicia con `ExitOnOutOfMemoryError` o que Docker termina por superar su límite (`OOMKilled` en `docker inspect`) indica que su límite está bajo. Las alarmas de EP3.5-19 lo detectan.
