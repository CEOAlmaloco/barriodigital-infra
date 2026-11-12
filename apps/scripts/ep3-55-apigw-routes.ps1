# EP3-55: rutas Kafka/Report/Audit + assignees + X-Source-Ip (overwrite)
# Requiere: AWS CLI + sesión válida (Learner Lab). Región us-east-1.
# Uso: .\apps\scripts\ep3-55-apigw-routes.ps1 [-DryRun] [-BffHost 3.92.161.52]

param(
  [switch]$DryRun,
  [string]$ApiName = "barriodigital-http",
  [string]$Region = "us-east-1",
  [string]$BffHost = ""
)

$ErrorActionPreference = "Stop"

function Invoke-AwsJson {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
  $raw = & aws @AwsArgs --region $Region --output json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "aws $($AwsArgs -join ' '): $raw" }
  if ([string]::IsNullOrWhiteSpace("$raw")) { return $null }
  return ("$raw" | ConvertFrom-Json)
}

Write-Host "== EP3-55 API Gateway =="

$apis = Invoke-AwsJson apigatewayv2 get-apis
$api = $apis.Items | Where-Object { $_.Name -eq $ApiName } | Select-Object -First 1
if (-not $api) { throw "API '$ApiName' no encontrada" }
$ApiId = $api.ApiId
Write-Host "API: $ApiName ($ApiId) $($api.ApiEndpoint)"

$authorizers = Invoke-AwsJson apigatewayv2 get-authorizers --api-id $ApiId
$auth = $authorizers.Items | Where-Object { $_.Name -eq "entra-jwt" } | Select-Object -First 1
if (-not $auth) { throw "Authorizer entra-jwt no encontrado" }
$AuthorizerId = $auth.AuthorizerId
Write-Host "Authorizer: entra-jwt ($AuthorizerId)"

$integrations = Invoke-AwsJson apigatewayv2 get-integrations --api-id $ApiId
$catchAll = $integrations.Items |
  Where-Object { $_.IntegrationUri -match '/\{proxy\}$' -and $_.IntegrationUri -notmatch '/api/' } |
  Select-Object -First 1
if (-not $catchAll) { throw "Integración catch-all http://HOST:8080/{proxy} no encontrada" }

if (-not $BffHost) {
  if ($catchAll.IntegrationUri -match 'https?://([^/:]+)') { $BffHost = $Matches[1] }
  else { throw "No se pudo inferir BffHost" }
}
$Bff = "http://${BffHost}:8080"
Write-Host "BFF base: $Bff"

function Ensure-Integration([string]$Uri) {
  $existing = $integrations.Items | Where-Object { $_.IntegrationUri -eq $Uri } | Select-Object -First 1
  if ($existing) {
    Write-Host "OK integ $($existing.IntegrationId) -> $Uri"
    return $existing.IntegrationId
  }
  if ($DryRun) {
    Write-Host "DryRun create-integration $Uri"
    return "dry-run"
  }
  $j = Invoke-AwsJson apigatewayv2 create-integration `
    --api-id $ApiId `
    --integration-type HTTP_PROXY `
    --integration-method ANY `
    --payload-format-version 1.0 `
    --integration-uri $Uri
  Write-Host "new integ $($j.IntegrationId) -> $Uri"
  $integrations.Items += $j
  return $j.IntegrationId
}

function Set-SourceIp([string]$IntegId) {
  if ($IntegId -eq "dry-run") { return }
  $detail = Invoke-AwsJson apigatewayv2 get-integration --api-id $ApiId --integration-id $IntegId
  $val = $null
  if ($detail.RequestParameters) {
    $val = $detail.RequestParameters.'overwrite:header.X-Source-Ip'
  }
  if ($val -eq '$context.identity.sourceIp') {
    Write-Host "X-Source-Ip OK $IntegId"
    return
  }
  Write-Host "Set X-Source-Ip overwrite on $IntegId"
  if ($DryRun) { return }
  & aws apigatewayv2 update-integration `
    --api-id $ApiId `
    --integration-id $IntegId `
    --request-parameters "overwrite:header.X-Source-Ip=`$context.identity.sourceIp" `
    --region $Region | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "update-integration X-Source-Ip $IntegId" }
}

function Ensure-Route([string]$RouteKey, [string]$IntegId) {
  $routes = Invoke-AwsJson apigatewayv2 get-routes --api-id $ApiId
  $existing = $routes.Items | Where-Object { $_.RouteKey -eq $RouteKey } | Select-Object -First 1
  if ($DryRun) {
    Write-Host "DryRun route $RouteKey -> $IntegId"
    return
  }
  if ($existing) {
    & aws apigatewayv2 update-route `
      --api-id $ApiId `
      --route-id $existing.RouteId `
      --authorization-type JWT `
      --authorizer-id $AuthorizerId `
      --target "integrations/$IntegId" `
      --region $Region | Out-Null
    Write-Host "upd $RouteKey -> $IntegId"
    return
  }
  $c = Invoke-AwsJson apigatewayv2 create-route `
    --api-id $ApiId `
    --route-key $RouteKey `
    --authorization-type JWT `
    --authorizer-id $AuthorizerId `
    --target "integrations/$IntegId"
  Write-Host "new $RouteKey -> $IntegId ($($c.RouteId))"
}

# Integraciones con prefijo (mismo patrón que catalog/mq)
$kafkaId = Ensure-Integration "$Bff/api/kafka/{proxy}"
$reportId = Ensure-Integration "$Bff/api/report/{proxy}"
$auditId = Ensure-Integration "$Bff/api/audit/{proxy}"
$assigneesId = Ensure-Integration "$Bff/api/requests/assignees"
$takeId = Ensure-Integration "$Bff/api/requests/{id}/take"
$assigneeId = Ensure-Integration "$Bff/api/requests/{id}/assignee"

# X-Source-Ip en todas las integraciones HTTP_PROXY al BFF
$allIntegs = Invoke-AwsJson apigatewayv2 get-integrations --api-id $ApiId
foreach ($i in $allIntegs.Items) {
  if ($i.IntegrationType -eq "HTTP_PROXY" -and $i.IntegrationUri -like "*${BffHost}:8080*") {
    Set-SourceIp $i.IntegrationId
  }
}

foreach ($m in @("GET","POST","PUT","PATCH","DELETE")) {
  Ensure-Route "$m /api/kafka/{proxy+}" $kafkaId
}
Ensure-Route "GET /api/report/{proxy+}" $reportId
Ensure-Route "GET /api/audit/{proxy+}" $auditId
Ensure-Route "GET /api/requests/assignees" $assigneesId
Ensure-Route "POST /api/requests/{id}/take" $takeId
Ensure-Route "PUT /api/requests/{id}/assignee" $assigneeId

$apiDetail = Invoke-AwsJson apigatewayv2 get-api --api-id $ApiId
$cors = $apiDetail.CorsConfiguration
Write-Host "CORS origins: $($cors.AllowOrigins -join ', ')"
Write-Host "CORS methods: $($cors.AllowMethods -join ', ')"
Write-Host "CORS headers: $($cors.AllowHeaders -join ', ')"

Write-Host ""
Write-Host "Validación (sin token -> 401):"
$base = $api.ApiEndpoint.TrimEnd("/")
foreach ($p in @("/api/kafka/topics","/api/report/summary","/api/audit/events","/api/requests/assignees")) {
  $code = & curl.exe -s -o NUL -w "%{http_code}" "$base$p"
  Write-Host "  GET $p -> $code"
}

Write-Host "Listo. Documentar en docs/decisiones.md + evidencias."
if ($DryRun) { Write-Host "(DryRun: no se aplicaron cambios)" }
