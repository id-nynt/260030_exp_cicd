# Experiment guide

This guide describes the current GitHub-controlled experiment on a Windows
laptop using Docker Desktop, WSL2, a self-hosted GitHub Actions runner, and the
local Java/Jason BDI controller.

The three visible processes are:

1. BDI MAS Console: Gradle runs real.mas2j and shows AgentSpeak work.
2. BDI Decision Monitor: follows structured JSON events.
3. Telemetry Monitor: polls staging and production health and metrics.

GitHub Actions is a separate browser view. The BDI controller dispatches
.github/workflows/entity-execution.yml one entity at a time.

## One-time setup

1. Install Docker Desktop with Linux containers and WSL2 integration.
2. Install WSL2 Ubuntu.
3. Install Java/JDK 17 or newer, Gradle, Git, and Python with PyYAML.
4. Add a GitHub Actions self-hosted runner inside WSL2 Ubuntu.
5. Add the labels self-hosted, linux, x64, and bdi-demo.
6. Start the runner with:

~~~bash
./run.sh
~~~

7. Confirm GitHub shows the runner Online and Idle.
8. Confirm .github/workflows/entity-execution.yml contains:

~~~yaml
runs-on: [self-hosted, linux, x64, bdi-demo]
~~~

9. Commit and push that workflow to the branch used by the BDI controller:

~~~powershell
git add .github/workflows/entity-execution.yml
git commit -m "Use persistent runner for BDI entities"
git push origin main
~~~

The current workflow removes and replaces the named staging, production, and
rollback containers before starting them. This is required because the runner
is persistent.

## Start every experiment

### 1. Start Docker Desktop

Open Docker Desktop and wait until it reports that Docker is running.

Verify from PowerShell:

~~~powershell
docker info
docker context show
~~~

docker info must show Server information. Client-only output means Docker is
not available to the experiment.

### 2. Start the GitHub runner

Open WSL2 Ubuntu and run the runner:

~~~bash
cd /path/to/the/repository
./run.sh
~~~

Leave this terminal open. The GitHub job remains queued if the runner is not
online.

### 3. Generate the model

From the repository root in PowerShell:

~~~powershell
py .\tools\model_transform.py
py .\tools\test_model_transform.py
~~~

This reads:

~~~text
01_pipeline.yaml
02_goal.yaml
~~~

and generates:

~~~text
03_workflow_model.yaml
bdi_project.asl
bdi_agent.asl
~~~

Do not manually edit the generated files.

### 4. Set GitHub and deployment variables

Use a token with the minimum Actions dispatch, run-read, and artifact-read
permissions. Never commit the token.

~~~powershell
$env:GITHUB_TOKEN = '<token>'
$env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
$env:GITHUB_REF = 'main'

$env:BDI_EXPERIMENT_ID = 'laptop-demo-001'
$env:BDI_RELEASE_ID = 'candidate-001'
$env:BDI_LOG_FILE = 'java-jason/runtime-artifacts/laptop-demo-001.jsonl'

$env:STAGING_HEALTH_URL = 'http://localhost:8081/health'
$env:STAGING_METRICS_URL = 'http://localhost:8081/metrics'
$env:PRODUCTION_HEALTH_URL = 'http://localhost:8082/health'
$env:PRODUCTION_METRICS_URL = 'http://localhost:8082/metrics'

$env:BDI_DEPLOYMENT_MODE = 'runner'
$env:BDI_DEPLOYMENT_HOST = 'localhost'
$env:BDI_PERSISTENT_DEPLOYMENT_CONFIRMED = '1'
~~~

### 5. Start the BDI demonstration

Run:

~~~powershell
.\run-demo.ps1 -Mode real
~~~

This opens:

- TELEMETRY MONITOR;
- BDI DECISION MONITOR;
- BDI MAS CONSOLE.

The MAS Console is the Gradle task executing:

~~~text
gradle run
  -> jason.infra.local.RunLocalMAS
  -> java-jason/real.mas2j
  -> root bdi_agent.asl
~~~

Expected BDI Console output:

~~~text
Master goal started.
Pursuing achievement: production = success
Running entity: build.
[BDI Environment] action agent=bdi_agent run_job entity=build
[BDI Environment] observation ... belief=status(build,success)
build completed successfully.
Running entity: test.
...
Pipeline reached final success.
Master goal achieved.
~~~

### 6. Watch GitHub Actions

Open the repository Actions tab. Expected entity sequence:

~~~text
build -> test -> security -> staging -> production
~~~

Each entity is a separate workflow_dispatch execution.

| Entity | What GitHub Actions does |
|---|---|
| build | Builds the payment-service Docker image and uploads payment-image |
| test | Builds the image and runs Python unit tests inside Docker |
| security | Runs pip check, non-root-image, and secret checks |
| staging | Starts payment-staging on port 8081 and checks /health |
| production | Starts payment-production on port 8082 and checks /health |
| rollback_production | Downloads the build artifact and replaces production |

The BDI JSONL log records the entity, GitHub run ID, terminal status, and
duration.

### 7. Verify applications and telemetry

Open these browser URLs:

~~~text
http://localhost:8081/
http://localhost:8081/health
http://localhost:8081/metrics

http://localhost:8082/
http://localhost:8082/health
http://localhost:8082/metrics
~~~

The UI shows Payment Service, environment, version, health, and metrics links.

Verify the containers remain alive after GitHub finishes:

~~~powershell
docker ps
Invoke-RestMethod http://localhost:8081/health
Invoke-RestMethod http://localhost:8082/health
~~~

## Failure scenarios

### Scenario 1: build failure and retry

Create the plan before starting the controller:

~~~powershell
@'
build.1.failure_mode=build_failure
build.2.failure_mode=none
'@ | Set-Content .\experiments\manual-build-failure.properties

$env:BDI_EXECUTION_PLAN = (Resolve-Path .\experiments\manual-build-failure.properties)
$env:BDI_EXPERIMENT_ID = 'build-failure-001'
$env:BDI_LOG_FILE = 'java-jason/runtime-artifacts/build-failure-001.jsonl'
.\run-demo.ps1 -Mode real
~~~

Expected:

~~~text
run_job(build)
GitHub build fails
run_job(build)
GitHub build succeeds
test -> security -> staging -> production
~~~

This is a CI execution failure injected through GitHub workflow input.

### Scenario 2: test failure and retry

~~~powershell
@'
test.1.failure_mode=test_failure
test.2.failure_mode=none
'@ | Set-Content .\experiments\manual-test-failure.properties

$env:BDI_EXECUTION_PLAN = (Resolve-Path .\experiments\manual-test-failure.properties)
$env:BDI_EXPERIMENT_ID = 'test-failure-001'
$env:BDI_LOG_FILE = 'java-jason/runtime-artifacts/test-failure-001.jsonl'
.\run-demo.ps1 -Mode real
~~~

Expected:

~~~text
build -> test(fail) -> test(success) -> security -> staging -> production
~~~

### Scenario 3: production becomes unhealthy

Run this only after the healthy deployment is complete:

~~~powershell
$env:BDI_DEPLOYMENT_MODE = 'runner'
$env:BDI_DEPLOYMENT_HOST = 'localhost'
.\inject-error.ps1 -Scenario unhealthy -Entity production
~~~

This stops the actual persistent payment-production container on the runner
host. It is a runtime application failure, not a CI job failure.

Expected telemetry:

~~~text
production | health=unknown
~~~

Expected BDI process:

~~~text
health observation
-> status(production,fail)
-> runtime failure detected
-> recovery(production,rollback_production)
-> run_job(rollback_production)
~~~

Expected GitHub process:

~~~text
rollback_production workflow
-> old production container removed
-> previous build artifact downloaded
-> production container restarted
-> production health check succeeds
~~~

Verify:

~~~powershell
Invoke-RestMethod http://localhost:8082/health
docker ps
~~~

### Scenario 4: high error rate or high latency

~~~powershell
.\inject-error.ps1 -Scenario high-error-rate -Entity production
.\inject-error.ps1 -Scenario high-latency -Entity production
~~~

The telemetry monitor should show the changed metric. The current Project 1
goal model displays these metrics but does not yet translate an error-rate or
latency threshold into a BDI rollback decision. Do not claim threshold
adaptation is complete until that goal/model feature is implemented and tested.

Restore the persistent service:

~~~powershell
.\inject-error.ps1 -Scenario healthy -Entity production
~~~

### Scenario 5: failed recovery

Create the plan before starting the controller:

~~~powershell
@'
production.1.failure_mode=health_failure
production.2.failure_mode=health_failure
rollback_production.1.failure_mode=health_failure
'@ | Set-Content .\experiments\manual-recovery-failure.properties

$env:BDI_EXECUTION_PLAN = (Resolve-Path .\experiments\manual-recovery-failure.properties)
.\run-demo.ps1 -Mode real
~~~

Expected final state:

~~~text
rollback_production fails
production remains unhealthy
manual intervention required
~~~

## Stop and preserve evidence

Stop the MAS Console with Ctrl+C. Keep the runner available if more tests are
needed.

Evidence is saved under:

~~~text
java-jason/runtime-artifacts/
java-jason/scenario-artifacts/
~~~

Stop containers only after the experiment:

~~~powershell
docker rm -f payment-staging payment-production payment-production-rollback
docker compose down --remove-orphans
~~~

## Troubleshooting

| Symptom | Meaning | Action |
|---|---|---|
| Gradle is required | Gradle or wrapper is missing | Install Gradle or add java-jason/gradlew.bat |
| No BDI Console window | Launcher was not used | Run .\run-demo.ps1 -Mode real |
| No BDI actions | Wrong generated agent or mas2j | Run model generation, then gradle run from java-jason |
| GitHub job queued | Runner unavailable or label mismatch | Start WSL runner; verify bdi-demo label |
| Docker Server unavailable | Docker Desktop not running or inaccessible | Start Docker Desktop; rerun docker info |
| Health URL unavailable | Container/port is unavailable | Check docker ps and ports 8081/8082 |
| Dispatch fails | Token/repository/ref/workflow mismatch | Verify environment and workflow branch |
| Rollback port conflict | Existing container remained | Check cleanup step in entity-execution.yml |

