# Flujo completo con las colas de la nube (EP2-32)

Recorrido del 18 de octubre de 2026, sin mocks. El broker es el clúster de `ec2-mq` (`172.31.46.156:5672`, Management `http://54.81.56.155:15672`). Las apps están en `54.175.48.178`. El alta y los cambios de estado del trámite trazado entraron por el API Gateway `https://0yo277ntr8.execute-api.us-east-1.amazonaws.com`.

`develop` de requests ya publicaba estos eventos (PRs [18](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/18) y [19](https://github.com/CEOAlmaloco/ms-barriodigital-requests/pull/19), commit `48ebe2f`). La EC2 todavía corría el jar anterior, que solo publicaba `email.admitted` y `email.resolved`. Se reconstruyó únicamente `bd-requests` con ese `develop`, con catalog y notify ya healthy. No se recreó el BFF.

## Trámite trazado

Vecino creó `d0d8a189-bfa4-4005-8056-bf36e1eda8e4` (`bache`, Pasaje Los Aromos 120). El Gateway respondió **201** e `INGRESADO`.

La máquina de estados no salta de `ADMITIDO` a `EN_TERRENO`. El funcionario pasó por `EN_GESTION`, que no publica. Los cuatro `PUT /api/requests/{id}/status` por el Gateway respondieron **200**.

| Paso | HTTP | Qué llegó a notify |
|---|---|---|
| Alta | 201 | `certificate.receipt`. PDF `certificate-receipt-8d7bdb105913711ec99d9132e2db9d3229359549a2571d606553c811343efd12.pdf` (18096 bytes) en el volumen `certificates` |
| `ADMITIDO` | 200 | `email-simulado type=email.admitted`. El cupo de `bache` pasó de 8 a 7 |
| `EN_GESTION` | 200 | Nada. Esta transición no publica |
| `EN_TERRENO` | 200 | `crew-ticket` con `requestId` de este trámite y `email-simulado type=email.visit`, los dos a las 00:03:26Z |
| `RESUELTO` | 200 | `email-simulado type=email.resolved` y `certificate.resolved`. PDF `certificate-resolved-effebb4b37169a3370aad5bd520d6324274cd24838702cb51bfa504ffee7f74a.pdf` |

`bache` no tenía límite (`dailyQuota` null): en ese estado `reserve` responde 200 y no descuenta. Para ver el descuento se fijó `dailyQuota` 8 en catalog, con el header `X-User-Roles: Admin` que el BFF reenvía. La admisión por el Gateway lo dejó en 7. Después del recorrido se volvió a dejar `bache` sin límite.

El correo es simulado (`EMAIL_MODE=logging`): notify registra `entrega-real=false`. El ticket queda en el log `crew-ticket`, no en otra bandeja.

## Mensaje inválido

Se publicó en `cmd.topic`, routing key `email.admitted`, delivery mode 2, el sobre de `docs/rabbitmq-mensaje-muerto.md` con `solicitanteEmail` null y `eventId` `11111111-2222-4333-8444-555555555555`.

notify respondió:

```text
ERROR mensaje-muerto cola=q.cmd.email eventId=11111111-2222-4333-8444-555555555555 motivo="solicitanteEmail debe ser una direccion unica valida" intentos=0
```

`q.cmd.email.dlq` quedó con 1 mensaje y 0 consumidores. Las colas de trabajo quedaron en 0.

## Broker detenido

Se creó otro trámite directo a requests (`0e659474-6016-4a47-b3d9-68dfcec97224`, 201 en 0,78 s) y se hizo `docker compose stop` en `ec2-mq`, sin `-v`. Con los dos nodos parados, `PUT /api/requests/{id}/status` a `ADMITIDO` contra `http://54.175.48.178:8081` respondió **200** en **0,78 s**. El estado quedó `ADMITIDO`. El hilo HTTP no esperó al broker. El publicador registró:

```text
ERROR No se pudo publicar type=email.admitted correlationId=0e659474-6016-4a47-b3d9-68dfcec97224
```

Ese mensaje no entró a ninguna cola. Después se hizo `docker compose start`: `rabbitmq-1` y `rabbitmq-2` volvieron healthy.

## Reinicio del compose de apps

`docker compose restart` en `~/barriodigital` reinició catalog, notify, requests y el BFF a la vez (arranques entre 00:07:10Z y 00:07:11Z). `depends_on` no ordena un restart. Los cuatro quedaron healthy.

No apareció `mensaje devuelto` en el log de requests. El único error de publicación sigue siendo el `email.admitted` del broker detenido, anterior al restart. `q.cmd.email.dlq` siguió en 1. Las tres colas de trabajo volvieron a tener un consumidor. Los PDF del volumen siguieron ahí.
