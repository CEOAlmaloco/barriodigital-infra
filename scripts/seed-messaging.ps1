# Seed de demo para RabbitMQ + Kafka (lab local).
# No es una BD: publica mensajes/eventos reales en brokers ya levantados.
# Uso (desde la raíz de barriodigital-infra):
#   .\scripts\seed-messaging.ps1
#   .\scripts\seed-messaging.ps1 -Target rabbit
#   .\scripts\seed-messaging.ps1 -Target kafka
#   .\scripts\seed-messaging.ps1 -PurgeFirst

param(
  [ValidateSet('all', 'rabbit', 'kafka')]
  [string]$Target = 'all',
  [switch]$PurgeFirst,
  [string]$MqEnvFile = '',
  [string]$MgmtBase = 'http://127.0.0.1:15672',
  [string]$KafkaContainer = 'kafka-1',
  [string]$KafkaBootstrap = 'localhost:9092'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $MqEnvFile) {
  $MqEnvFile = Join-Path $Root 'mq\.env'
}

function Read-DotEnv([string]$Path) {
  $map = @{}
  if (-not (Test-Path $Path)) {
    throw "No está $Path. Copia mq\.env.example a mq\.env."
  }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { return }
    $key = $line.Substring(0, $i).Trim()
    $val = $line.Substring($i + 1).Trim()
    # Compose: $$ → $
    $val = $val -replace '\$\$', '$'
    $map[$key] = $val
  }
  return $map
}

function New-Id {
  return [guid]::NewGuid().ToString()
}

function Invoke-RabbitPublish {
  param(
    [string]$User,
    [string]$Pass,
    [string]$RoutingKey,
    [string]$Payload,
    [string]$Exchange = 'amq.default'
  )
  $body = @{
    properties       = @{
      delivery_mode = 2
      content_type  = 'application/json'
    }
    routing_key      = $RoutingKey
    payload          = $Payload
    payload_encoding = 'string'
  } | ConvertTo-Json -Compress -Depth 6

  $pair = '{0}:{1}' -f $User, $Pass
  $bytes = [Text.Encoding]::ASCII.GetBytes($pair)
  $auth = [Convert]::ToBase64String($bytes)
  $ex = [uri]::EscapeDataString($Exchange)
  $uri = "$MgmtBase/api/exchanges/%2F/$ex/publish"
  $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ Authorization = "Basic $auth" } `
    -ContentType 'application/json' -Body $body
  if (-not $resp.routed) {
    Write-Warning "No ruteó a $RoutingKey (¿existe la cola?)."
  }
}

function Clear-RabbitQueue {
  param([string]$User, [string]$Pass, [string]$Queue)
  $pair = '{0}:{1}' -f $User, $Pass
  $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
  $q = [uri]::EscapeDataString($Queue)
  Invoke-RestMethod -Method Delete -Uri "$MgmtBase/api/queues/%2F/$q/contents" `
    -Headers @{ Authorization = "Basic $auth" } | Out-Null
}

function New-RabbitEnvelope {
  param([string]$Type, [string]$RequestId, [hashtable]$Extra = @{})
  $payload = @{
    requestId         = $RequestId
    procedureType     = 'bache'
    procedureLabel    = 'Bache en calle'
    address           = 'Los Aromos 120'
    solicitanteEmail  = 'vecino.demo@example.com'
    folio             = 'BD-2026-SEED001'
  }
  foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] }
  return (@{
    type          = $Type
    eventId       = (New-Id)
    timestamp     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    traceId       = (New-Id)
    correlationId = $RequestId
    payload       = $payload
  } | ConvertTo-Json -Compress -Depth 6)
}

function Seed-Rabbit {
  Write-Host '=== RabbitMQ seed ==='
  $envMap = Read-DotEnv $MqEnvFile
  $user = $envMap['RABBITMQ_DEFAULT_USER']
  $pass = $envMap['RABBITMQ_DEFAULT_PASS']
  if (-not $user -or -not $pass) {
    throw 'mq/.env sin RABBITMQ_DEFAULT_USER / RABBITMQ_DEFAULT_PASS'
  }

  $queues = @(
    'q.cmd.email', 'q.cmd.crew', 'q.cmd.certificate',
    'q.cmd.email.dlq', 'q.cmd.crew.dlq', 'q.cmd.certificate.dlq'
  )

  if ($PurgeFirst) {
    foreach ($q in $queues) {
      Write-Host "  purge $q"
      Clear-RabbitQueue -User $user -Pass $pass -Queue $q
    }
  }

  # Acumulación Ready (notify puede consumirlas; DLQ sí permanecen).
  $readyPlan = @(
    @{ Queue = 'q.cmd.email'; Type = 'email.admitted'; Count = 12 },
    @{ Queue = 'q.cmd.crew'; Type = 'crew.ticket'; Count = 8 },
    @{ Queue = 'q.cmd.certificate'; Type = 'certificate.receipt'; Count = 5 }
  )
  foreach ($plan in $readyPlan) {
    for ($i = 0; $i -lt $plan.Count; $i++) {
      $rid = New-Id
      $json = New-RabbitEnvelope -Type $plan.Type -RequestId $rid
      Invoke-RabbitPublish -User $user -Pass $pass -RoutingKey $plan.Queue -Payload $json
    }
    Write-Host ("  {0}: +{1} msg" -f $plan.Queue, $plan.Count)
  }

  # DLQ persistentes (sin consumidor).
  $dlqPlan = @(
    @{ Queue = 'q.cmd.email.dlq'; Type = 'email.rejected'; Count = 4; Extra = @{ rejectionReason = 'Seed: rechazo de demo' } },
    @{ Queue = 'q.cmd.crew.dlq'; Type = 'crew.ticket'; Count = 2; Extra = @{} },
    @{ Queue = 'q.cmd.certificate.dlq'; Type = 'certificate.resolved'; Count = 3; Extra = @{} }
  )
  foreach ($plan in $dlqPlan) {
    for ($i = 0; $i -lt $plan.Count; $i++) {
      $rid = New-Id
      $json = New-RabbitEnvelope -Type $plan.Type -RequestId $rid -Extra $plan.Extra
      Invoke-RabbitPublish -User $user -Pass $pass -RoutingKey $plan.Queue -Payload $json
    }
    Write-Host ("  {0}: +{1} msg" -f $plan.Queue, $plan.Count)
  }

  Write-Host 'RabbitMQ OK (colas + DLQ).'
}

function New-KafkaRequestEvent {
  param([string]$RequestId, [int]$Sequence, [string]$EventType = 'request.created')
  $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
  $payload = switch ($EventType) {
    'request.created' {
      @{
        requestId       = $RequestId
        folio           = ('BD-2026-{0:D6}' -f (1000 + $Sequence))
        procedureType   = 'bache'
        procedureLabel  = 'Bache en calle'
        sector          = 'ralco'
        latitude        = -37.9946
        longitude       = -71.4962
        status          = 'INGRESADO'
        slaBusinessDays = 5
      }
    }
    'request.status-changed' {
      @{
        requestId          = $RequestId
        folio              = ('BD-2026-{0:D6}' -f (1000 + $Sequence))
        procedureType      = 'bache'
        sector             = 'ralco'
        fromStatus         = 'ADMITIDO'
        toStatus           = 'EN_GESTION'
        reason             = $null
        interventionReason = $null
      }
    }
    default { @{ requestId = $RequestId } }
  }
  return (@{
    eventId       = (New-Id)
    eventType     = $EventType
    schemaVersion = 1
    occurredAt    = $now
    producer      = 'requests'
    traceId       = (New-Id)
    sequence      = $Sequence
    actor         = @{ id = (New-Id); name = 'Seed Demo'; role = 'Vecino' }
    payload       = $payload
  } | ConvertTo-Json -Compress -Depth 8)
}

function New-KafkaAuditEvent {
  param([int]$Sequence)
  $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
  return (@{
    eventId       = (New-Id)
    eventType     = 'queue.purged'
    schemaVersion = 1
    occurredAt    = $now
    producer      = 'mq-admin'
    traceId       = (New-Id)
    actor         = @{
      id       = (New-Id)
      name     = 'Admin Seed'
      role     = 'Admin'
      sourceIp = '127.0.0.1'
    }
    payload       = @{
      resourceType = 'queue'
      resourceId   = 'q.cmd.email'
      action       = 'purged'
      before       = @{ messages = $Sequence }
      after        = @{ messagesRemoved = $Sequence }
    }
  } | ConvertTo-Json -Compress -Depth 8)
}

function Publish-KafkaLines {
  param(
    [string]$Topic,
    [string[]]$Lines
  )
  if ($Lines.Count -eq 0) { return }
  # Una línea por mensaje; sin línea vacía final (console-producer falla con parse.key).
  $clean = foreach ($line in $Lines) {
    ($line -replace "[\r\n]+", ' ').Trim()
  }
  $clean = @($clean | Where-Object { $_ -and $_.Contains('|') })
  # Sin newline final: WriteAllLines / Get-Content -Raw dejan una línea vacía y parse.key falla.
  $payload = [string]::Join("`n", $clean)
  $payload | docker exec -i $KafkaContainer kafka-console-producer `
    --bootstrap-server $KafkaBootstrap `
    --topic $Topic `
    --property 'parse.key=true' `
    --property 'key.separator=|' | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo kafka-console-producer en $Topic (exit $LASTEXITCODE)"
  }
}

function Seed-Kafka {
  Write-Host '=== Kafka seed ==='
  $null = docker exec $KafkaContainer kafka-topics --bootstrap-server $KafkaBootstrap --list 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "No responde $KafkaContainer. ¿Está arriba el compose de kafka/?"
  }

  $requestLines = [System.Collections.Generic.List[string]]::new()
  for ($i = 1; $i -le 40; $i++) {
    $rid = New-Id
    $evt = if ($i % 5 -eq 0) {
      New-KafkaRequestEvent -RequestId $rid -Sequence (2000 + $i) -EventType 'request.status-changed'
    } else {
      New-KafkaRequestEvent -RequestId $rid -Sequence (2000 + $i)
    }
    $requestLines.Add("$rid|$evt")
  }
  Publish-KafkaLines -Topic 'requests.events' -Lines $requestLines.ToArray()
  Write-Host '  requests.events: +40 eventos'

  $auditLines = @()
  for ($i = 1; $i -le 12; $i++) {
    $key = "queue:q.cmd.email"
    $auditLines += "$key|$(New-KafkaAuditEvent -Sequence $i)"
  }
  Publish-KafkaLines -Topic 'audit.timeline' -Lines $auditLines
  Write-Host '  audit.timeline: +12 eventos'

  # DLT: valor JSON (headers completos requieren productor con headers; el listado igual muestra mensajes).
  $dltLines = @()
  for ($i = 1; $i -le 5; $i++) {
    $rid = New-Id
    $evt = New-KafkaRequestEvent -RequestId $rid -Sequence (9000 + $i)
    $dltLines += "$rid|$evt"
  }
  Publish-KafkaLines -Topic 'requests.events.report.DLT' -Lines $dltLines
  Write-Host '  requests.events.report.DLT: +5 eventos'

  $dltAudit = @()
  for ($i = 1; $i -le 3; $i++) {
    $rid = New-Id
    $dltAudit += "$rid|$(New-KafkaRequestEvent -RequestId $rid -Sequence (9100 + $i))"
  }
  Publish-KafkaLines -Topic 'requests.events.audit.DLT' -Lines $dltAudit
  Write-Host '  requests.events.audit.DLT: +3 eventos'

  # Grupo demo con lag: consume 1, luego quedan mensajes nuevos sin leer en este grupo.
  Write-Host '  creando consumer group seed-demo-group (lag)...'
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  docker exec $KafkaContainer kafka-console-consumer `
    --bootstrap-server $KafkaBootstrap `
    --topic requests.events `
    --group seed-demo-group `
    --from-beginning `
    --max-messages 1 `
    --timeout-ms 15000 1>$null 2>$null
  $ErrorActionPreference = $prevEap

  $lagBurst = [System.Collections.Generic.List[string]]::new()
  for ($i = 1; $i -le 25; $i++) {
    $rid = New-Id
    $lagBurst.Add("$rid|$(New-KafkaRequestEvent -RequestId $rid -Sequence (3000 + $i))")
  }
  Publish-KafkaLines -Topic 'requests.events' -Lines $lagBurst.ToArray()
  Write-Host '  requests.events: +25 (para lag de seed-demo-group)'

  Write-Host 'Kafka OK (topics + DLT + grupo seed-demo-group).'
}

Write-Host "Seed messaging · target=$Target · purge=$PurgeFirst"
if ($Target -eq 'all' -or $Target -eq 'rabbit') { Seed-Rabbit }
if ($Target -eq 'all' -or $Target -eq 'kafka') { Seed-Kafka }
Write-Host 'Listo. Refresca Admin → RabbitMQ / Kafka.'
