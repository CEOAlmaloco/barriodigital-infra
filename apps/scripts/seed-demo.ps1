# Carga de demostración para el laboratorio local. Usa los flujos reales del sistema:
#   requests: trámites creados por la API de requests, igual que la colección de Postman.
#             Generan los eventos de Kafka (outbox) y los comandos de RabbitMQ que publica requests.
#   rabbit:   un comando no recuperable por cola. notify lo rechaza y RabbitMQ lo deja en la DLQ.
#   kafka:    mensajes sin eventType en requests.events. report y audit los envían a su DLT.
# No escribe en audit.timeline ni publica eventos de dominio armados a mano.
#
# Uso, desde la raíz de barriodigital-infra y con apps, mq y kafka levantados:
#   .\apps\scripts\seed-demo.ps1
#   .\apps\scripts\seed-demo.ps1 -Target requests -Count 20

param(
  [ValidateSet('all', 'requests', 'rabbit', 'kafka')]
  [string]$Target = 'all',
  [ValidateRange(1, 50)]
  [int]$Count = 12,
  [string]$RequestsUrl = 'http://localhost:8081',
  [string]$MqEnvFile = '',
  [string]$MgmtBase = 'http://127.0.0.1:15672',
  [string]$KafkaContainer = 'kafka-1',
  [string]$KafkaBootstrap = 'localhost:9092'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $MqEnvFile) {
  $MqEnvFile = Join-Path $Root 'mq\.env'
}

# Vecino ficticio: todos los trámites de la carga quedan a su nombre y se distinguen en /tramites.
$DemoCitizen = @{
  'X-User-Id'    = '6f1c0de0-5eed-4a11-8d00-000000000001'
  'X-User-Roles' = 'Vecino'
  'X-User-Name'  = 'Vecino de prueba'
  'X-User-Email' = 'vecino.prueba@example.com'
}

$Procedures = @(
  @{ Type = 'bache'; Description = 'Bache profundo frente al paradero, los vehículos lo esquivan por la berma.' },
  @{ Type = 'alumbrado'; Description = 'Luminaria apagada desde hace una semana en el cruce.' },
  @{ Type = 'basura'; Description = 'Microbasural junto al canal, con bolsas acumuladas.' },
  @{ Type = 'agua'; Description = 'Filtración de agua potable en la vereda.' },
  @{ Type = 'ruido'; Description = 'Ruidos molestos de maquinaria fuera de horario.' }
)
$Addresses = @('Los Aromos 120', 'Camino a Pitril km 3', 'Pasaje Los Robles 45', 'Avenida Ralco 210', 'Calle El Barco 18')
$SectorsWithoutPoint = @('pitril', 'quepuca', 'villa-ralco', 'malla')

function Read-DotEnv([string]$Path) {
  if (-not (Test-Path $Path)) {
    throw "No existe $Path. Copia mq\.env.example a mq\.env."
  }
  $map = @{}
  foreach ($raw in Get-Content $Path) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { continue }
    # Compose escribe $$ para un $ literal.
    $map[$line.Substring(0, $i).Trim()] = ($line.Substring($i + 1).Trim() -replace '\$\$', '$')
  }
  return $map
}

function Invoke-Requests([string]$Method, [string]$Path, $Body = $null) {
  $params = @{
    Method      = $Method
    Uri         = "$RequestsUrl$Path"
    Headers     = $DemoCitizen
    ContentType = 'application/json; charset=utf-8'
  }
  if ($null -ne $Body) {
    $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress))
  }
  return Invoke-RestMethod @params
}

# Cada cuarto trámite se cancela como lo haría el titular. Ni el alta ni la cancelación tocan el cupo:
# el cupo lo reserva el BFF al admitir.
function Add-DemoRequests {
  Write-Host '=== requests ==='
  try {
    Invoke-RestMethod -Uri "$RequestsUrl/actuator/health" | Out-Null
  } catch {
    throw "requests no responde en $RequestsUrl. Levanta apps/ antes de la carga."
  }

  $created = [System.Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $Count; $i++) {
    $procedure = $Procedures[$i % $Procedures.Count]
    $body = [ordered]@{
      description   = $procedure.Description
      procedureType = $procedure.Type
      address       = $Addresses[$i % $Addresses.Count]
    }
    if ($i % 2 -eq 0) {
      # Punto aproximado alrededor de Ralco, dentro de la caja de la comuna.
      $body.sector = 'ralco'
      $body.latitude = [math]::Round(-37.9946 + (($i % 5) - 2) * 0.004, 5)
      $body.longitude = [math]::Round(-71.4962 + (($i % 3) - 1) * 0.004, 5)
      $body.locationPrecision = 'APROXIMADO'
    } else {
      $body.sector = $SectorsWithoutPoint[$i % $SectorsWithoutPoint.Count]
    }
    $request = Invoke-Requests -Method Post -Path '/api/requests' -Body $body
    if ($i % 4 -eq 3) {
      Invoke-Requests -Method Post -Path "/api/requests/$($request.id)/cancel" | Out-Null
    }
    $created.Add($request)
  }
  $cancelled = [math]::Floor($Count / 4)
  Write-Host ("  {0} trámites creados, {1} cancelados por el titular" -f $Count, $cancelled)
  return $created
}

function Get-QueueDepth([hashtable]$Auth, [string]$Queue) {
  $q = [uri]::EscapeDataString($Queue)
  return (Invoke-RestMethod -Uri "$MgmtBase/api/queues/%2F/$q" -Headers $Auth).messages
}

function Send-RabbitMessage([hashtable]$Auth, [string]$Exchange, [string]$RoutingKey, [hashtable]$Message) {
  $body = @{
    properties       = @{ delivery_mode = 2; content_type = 'application/json' }
    routing_key      = $RoutingKey
    payload          = ($Message | ConvertTo-Json -Compress -Depth 5)
    payload_encoding = 'string'
  } | ConvertTo-Json -Compress -Depth 6
  $uri = "$MgmtBase/api/exchanges/%2F/$([uri]::EscapeDataString($Exchange))/publish"
  $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $Auth -ContentType 'application/json' -Body $body
  if (-not $resp.routed) {
    throw "RabbitMQ no enrutó $RoutingKey en $Exchange. ¿notify ya declaró la topología?"
  }
}

# Un comando por cola al que le falta un dato obligatorio para notify.
# notify lo rechaza sin reintentos y RabbitMQ lo deja en la DLQ con sus headers x-death.
function Send-DeadLetters([object[]]$Requests) {
  Write-Host '=== RabbitMQ ==='
  $envMap = Read-DotEnv $MqEnvFile
  $user = $envMap['RABBITMQ_DEFAULT_USER']
  $pass = $envMap['RABBITMQ_DEFAULT_PASS']
  if (-not $user -or -not $pass) {
    throw 'mq/.env no trae RABBITMQ_DEFAULT_USER y RABBITMQ_DEFAULT_PASS.'
  }
  $auth = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${user}:${pass}")) }

  $requestId = if ($Requests -and $Requests.Count -gt 0) { $Requests[0].id } else { [guid]::NewGuid().ToString() }
  $base = @{
    requestId        = $requestId
    procedureType    = 'bache'
    procedureLabel   = 'Bache en calle'
    address          = 'Los Aromos 120'
    solicitanteEmail = $DemoCitizen['X-User-Email']
  }
  $plan = @(
    @{ Queue = 'q.cmd.email.dlq'; Exchange = 'cmd.topic'; Key = 'email.rejected'; Drop = 'rejectionReason' },
    @{ Queue = 'q.cmd.crew.dlq'; Exchange = 'cmd.direct'; Key = 'crew.ticket'; Drop = 'address' },
    @{ Queue = 'q.cmd.certificate.dlq'; Exchange = 'cmd.topic'; Key = 'certificate.receipt'; Drop = 'procedureType' }
  )

  $before = @{}
  foreach ($step in $plan) {
    $before[$step.Queue] = Get-QueueDepth $auth $step.Queue
    $payload = $base.Clone()
    $payload.Remove($step.Drop)
    Send-RabbitMessage $auth $step.Exchange $step.Key @{
      type          = $step.Key
      eventId       = [guid]::NewGuid().ToString()
      timestamp     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
      traceId       = [guid]::NewGuid().ToString()
      correlationId = $requestId
      payload       = $payload
    }
  }

  # notify rechaza en milisegundos; si no llega, notify está detenido o no consume.
  $deadline = (Get-Date).AddSeconds(15)
  foreach ($step in $plan) {
    while ((Get-QueueDepth $auth $step.Queue) -le $before[$step.Queue]) {
      if ((Get-Date) -gt $deadline) {
        throw "No llegó el mensaje a $($step.Queue). Revisa que notify esté levantado."
      }
      Start-Sleep -Milliseconds 500
    }
    Write-Host ("  {0}: +1 (falta {1})" -f $step.Queue, $step.Drop)
  }
}

# Demo "Malformado" de docs/kafka.md: sin eventType, report y audit lo envían a su DLT con los headers
# kafka_dlt-*, así que se lista y se puede reprocesar desde kafka-admin.
function Send-MalformedEvents {
  Write-Host '=== Kafka ==='
  docker exec $KafkaContainer kafka-topics --bootstrap-server $KafkaBootstrap --list *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "No responde $KafkaContainer. Levanta kafka/ antes de la carga."
  }
  $lines = for ($i = 0; $i -lt 3; $i++) {
    $key = [guid]::NewGuid().ToString()
    $value = @{ eventId = [guid]::NewGuid().ToString(); schemaVersion = 1; producer = 'seed-demo'; payload = @{} } |
      ConvertTo-Json -Compress
    "$key|$value"
  }
  # Sin salto de línea final: console-producer con parse.key falla ante una línea vacía.
  [string]::Join("`n", $lines) | docker exec -i $KafkaContainer kafka-console-producer `
    --bootstrap-server $KafkaBootstrap `
    --topic requests.events `
    --property 'parse.key=true' `
    --property 'key.separator=|' | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Falló kafka-console-producer (exit $LASTEXITCODE)."
  }
  Write-Host '  requests.events: +3 sin eventType, van a requests.events.report.DLT y requests.events.audit.DLT'
}

Write-Host "Carga de demostración · $Target"
$requests = @()
if ($Target -in 'all', 'requests') { $requests = Add-DemoRequests }
if ($Target -in 'all', 'rabbit') { Send-DeadLetters $requests }
if ($Target -in 'all', 'kafka') { Send-MalformedEvents }
Write-Host 'Listo. Actualiza Inicio y Administración.'
