<!-- Movido desde docs/decisiones.md. Sin cambio de reglas. -->

## Cupo diario nulo y día en Chile (EP1.5-03)

`dailyQuota` y `remainingQuota` en null significan sin límite. El seed y el POST no ponen 10: un tipo nuevo no queda limitado hasta que el Admin lo pida. El día del reset es `America/Santiago`, no UTC, para que no cambie a las 20:00 o 21:00.

El PUT reemplaza el cupo completo. Si el cuerpo no trae `dailyQuota`, el tipo pasa a sin límite. El frontend tiene que mandar siempre el campo cuando quiere conservar el número; si lo omite, lo saca. En Oracle, `ddl-auto: update` no relaja un NOT NULL ya creado: hace falta un `ALTER` manual de `daily_quota` y `remaining_quota`.
