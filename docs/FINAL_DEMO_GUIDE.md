# Final demonstration guide

This is the literal procedure for the first real research demonstration. It
does not replace GitHub Actions with local pipeline execution.

## STEP 1 — Configure and generate

Edit:

```text
01_pipeline.yaml
02_goal.yaml
```

Then run:

```powershell
py .\tools\model_transform.py
py .\tools\test_model_transform.py
```

Expected telemetry window: not started yet.

Expected BDI window: not started yet.

Expected GitHub: no run yet.

Expected browser: no deployment yet.

Expected generated files:

```text
03_workflow_model.yaml
bdi_project.asl
bdi_agent.asl
```

## STEP 2 — Validate the BDI controller without external infrastructure

Run:

```powershell
.\run-demo.ps1 -Mode mock
```

Expected telemetry window: explicitly not started; mock mode has no live
application endpoint.

Expected BDI window: deterministic scenario output showing continue, retry,
stop, and rollback decisions.

Expected GitHub: no run; this step is intentionally local validation.

Expected browser: no deployment.

## STEP 3 — Complete one-time user setup

Follow [USER_SETUP.md](USER_SETUP.md).

Do not continue until:

- the self-hosted runner is online;
- the deployment workflow targets that runner;
- Docker is running on that host;
- ports 8081 and 8082 are reachable;
- health and metrics endpoints respond;
- the workflow file exists on the selected branch.

## STEP 4 — Configure the real controller

In the PowerShell window that will start the controller:

```powershell
$env:GITHUB_TOKEN = '<token>'
$env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
$env:GITHUB_REF = 'main'
$env:STAGING_HEALTH_URL = 'http://<persistent-host>:8081/health'
$env:STAGING_METRICS_URL = 'http://<persistent-host>:8081/metrics'
$env:PRODUCTION_HEALTH_URL = 'http://<persistent-host>:8082/health'
$env:PRODUCTION_METRICS_URL = 'http://<persistent-host>:8082/metrics'
$env:BDI_DEPLOYMENT_MODE = 'runner'
$env:BDI_DEPLOYMENT_HOST = '<persistent-host>'
$env:BDI_DEPLOYMENT_SSH_USER = '<ssh user>' # remote host only
$env:BDI_EXPERIMENT_ID = 'healthy-001'
$env:BDI_RELEASE_ID = 'candidate-001'
$env:BDI_LOG_FILE = 'java-jason/runtime-artifacts/healthy-001.jsonl'
$env:BDI_PERSISTENT_DEPLOYMENT_CONFIRMED = '1'
```

Expected telemetry window: endpoints are reachable before BDI starts.

Expected BDI window: not started yet.

Expected GitHub: no new run yet.

Expected browser: open the staging and production base URLs.

## STEP 5 — Start the healthy real demonstration

Run from the repository root:

```powershell
.\run-demo.ps1 -Mode real
```

This performs validation/generation, checks configuration, opens one telemetry
window, opens one structured BDI event window, and starts Java/Jason.

Expected telemetry window:

```text
entity=staging | health=healthy | error_rate=...
entity=production | health=healthy | error_rate=...
```

It must refresh continuously and show latency and freshness.

Expected BDI window:

```text
bdi_decision ... entity=build
github_dispatch_accepted ... entity=build
execution_terminal ... status=success
percept_published ... belief=status(build,success)
bdi_decision ... entity=test
```

Expected GitHub:

```text
build -> test -> security -> staging -> production
```

Each entity must show its GitHub run ID, terminal status, conclusion, and
duration in the structured JSONL log.

Expected browser:

- staging UI shows environment `staging`;
- production UI shows environment `production`;
- `/health` reports healthy;
- `/metrics` displays Prometheus metrics.

Evidence files:

```text
java-jason/runtime-artifacts/healthy-001.jsonl
```

Do not mark this step successful until the containers remain alive after the
GitHub jobs finish.

## STEP 6 — Inject unhealthy production

Run:

```powershell
.\inject-error.ps1 -Scenario unhealthy -Entity production
```

This command must target the same persistent host used by
`PRODUCTION_HEALTH_URL`. With `BDI_DEPLOYMENT_MODE=runner`, it operates on the
actual persistent `payment-production` container; it must not target an
unrelated local Compose instance.

Expected telemetry window:

```text
entity=production | health=unhealthy
```

Expected BDI window:

```text
observation_collected ... production ... health=unhealthy
percept_published ... belief=status(production,fail)
runtime failure detected
bdi_decision ... entity=rollback_production
```

Expected GitHub:

- a new `rollback_production` workflow run;
- a real run ID;
- completed success or explicit failure;
- recorded duration.

Expected browser:

Production becomes healthy again after rollback.

Evidence files:

```text
java-jason/runtime-artifacts/healthy-001.jsonl
```

If the command only changes local Compose while the BDI monitors another host,
the experiment is invalid.

## STEP 7 — Inject high error rate

Run:

```powershell
.\inject-error.ps1 -Scenario high-error-rate -Entity production
```

Expected telemetry window: production error rate increases.

Expected BDI window: the metric appears as a normalized metric belief. A
recovery decision is not complete until an error-rate threshold is configured
in `02_goal.yaml` and translated into the generic assessment path.

Expected GitHub: no recovery run until the threshold feature is implemented and
tested.

Expected browser: repeated `/pay` requests show failures.

This step is currently a planned extension, not a completed demonstration.

## STEP 8 — Stop and preserve evidence

Stop Java/Jason with `Ctrl+C`, close monitor windows, and save:

```text
java-jason/runtime-artifacts/*.jsonl
java-jason/scenario-artifacts/*.json
java-jason/scenario-artifacts/*.log
```

Do not commit tokens or private infrastructure details.

## Interpretation rule

A mock scenario passing is not evidence that GitHub deployment, persistent
runtime telemetry, or real rollback passed. Those require the real run records.
