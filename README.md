# Demo payment service

This is the standalone application for the experimental harness. It deliberately contains no BDI or GitHub Actions control logic.

The service exposes a small UI at `/`, `/health`, `/pay`, and `/metrics`. OpenTelemetry instruments Flask requests and payment spans. Metrics include request count, error count, and latency, with service version and deployment environment attributes.

## Prerequisites

- Docker Desktop with Compose

## Build

```powershell
docker compose build
```

## Start staging and production

```powershell
docker compose up -d
```

Open these links in a browser:

- http://localhost:8081/ — staging UI
- http://localhost:8082/ — production UI

## Verify `/health`

```powershell
Invoke-RestMethod http://localhost:8081/health
Invoke-RestMethod http://localhost:8082/health
```

## Generate normal traffic

```powershell
1..10 | ForEach-Object { Invoke-RestMethod -Method Post -Uri http://localhost:8081/pay -ContentType 'application/json' -Body '{"amount":10}' }
1..10 | ForEach-Object { Invoke-RestMethod -Method Post -Uri http://localhost:8082/pay -ContentType 'application/json' -Body '{"amount":10}' }
```

View metrics at http://localhost:8081/metrics and http://localhost:8082/metrics.

## Inject high latency

Recreate staging with an additional 1500 ms delay:

```powershell
$env:STAGING_FAILURE_MODE = 'latency'
$env:STAGING_EXTRA_LATENCY_MS = '1500'
docker compose up -d --force-recreate staging
Invoke-RestMethod http://localhost:8081/health
```

## Inject errors

Recreate production with a deterministic 50% error rate:

```powershell
$env:PRODUCTION_FORCE_ERROR_RATE = '0.5'
docker compose up -d --force-recreate production
1..4 | ForEach-Object { try { (Invoke-WebRequest -Method Post -Uri http://localhost:8082/pay -UseBasicParsing).StatusCode } catch { $_.Exception.Response.StatusCode.value__ } }
```

For errors on every payment request instead:

```powershell
$env:PRODUCTION_FAILURE_MODE = 'error'
docker compose up -d --force-recreate production
```

## Make the health check fail

```powershell
$env:STAGING_FAILURE_MODE = 'unhealthy'
docker compose up -d --force-recreate staging
Invoke-WebRequest http://localhost:8081/health -UseBasicParsing
```

The last command returns HTTP 503.

## Return services to healthy state

```powershell
Remove-Item Env:STAGING_FAILURE_MODE -ErrorAction SilentlyContinue
Remove-Item Env:STAGING_EXTRA_LATENCY_MS -ErrorAction SilentlyContinue
Remove-Item Env:PRODUCTION_FAILURE_MODE -ErrorAction SilentlyContinue
Remove-Item Env:PRODUCTION_FORCE_ERROR_RATE -ErrorAction SilentlyContinue
docker compose up -d --force-recreate staging production
Invoke-RestMethod http://localhost:8081/health
Invoke-RestMethod http://localhost:8082/health
```

## Run automated tests

Tests run inside the application image, so Python does not need to be installed on the host:

```powershell
docker build -t payment-service-test ./app
docker run --rm payment-service-test python -m unittest discover -s . -p 'test_*.py'
```

## Stop

```powershell
docker compose down
```

## Research demonstration

Follow the literal experiment procedure in
[`docs/EXPERIMENT_GUIDE.md`](docs/EXPERIMENT_GUIDE.md).

The complete demonstration procedure is documented in
[`docs/FINAL_DEMO_GUIDE.md`](docs/FINAL_DEMO_GUIDE.md). The required external
machine and GitHub setup is documented in
[`docs/USER_SETUP.md`](docs/USER_SETUP.md).

After setup, the primary command is:

```powershell
.\run-demo.ps1 -Mode real
```

This command validates and generates the model, opens the telemetry and BDI
monitor windows, and starts the Java/Jason controller. Real mode refuses to
start unless the persistent deployment target is explicitly confirmed.

The current implementation status is reported in
[`docs/FINAL_DEMO_RESULTS.md`](docs/FINAL_DEMO_RESULTS.md) and
[`docs/DEMO_STATUS.md`](docs/DEMO_STATUS.md).
