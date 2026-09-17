# Demonstration status

Date: 2026-09-17

This report audits the current repository against the required research
demonstration. It distinguishes code existence from tested behavior.

## Executive result

The configuration transformation, generic BDI reasoning, deterministic mock
execution, GitHub dispatch adapter, telemetry adapter, and structured logging
exist in the repository.

The complete real demonstration is **not yet proven**.

The blocking issue is:

> **PERSISTENT DEPLOYMENT NOT IMPLEMENTED**

The GitHub workflows deploy staging and production into Docker containers on
GitHub-hosted `ubuntu-latest` runners. Those containers are reachable only
inside the job and disappear when the job finishes. The local Java telemetry
adapter cannot continuously observe those deployments, and a later local
failure injection cannot modify them.

The repository now includes a visible local launcher and separate telemetry/BDI
monitors, but real mode intentionally refuses to start until a persistent
deployment target has been confirmed.

## Required workflow audit

| Demonstration step | Existing implementation | Tested? | Missing/problem | File responsible |
|---|---|---:|---|---|
| Developer fills pipeline.yaml | `01_pipeline.yaml` exists | PARTIAL | Supported subset is parsed; pipeline job scripts referenced by the source are not used by the BDI entity workflow | `01_pipeline.yaml`, `tools/model_transform.py` |
| Developer fills goal.yaml | `02_goal.yaml` exists | PARTIAL | Parser supports achievement, duration maintenance, and status-based avoidance only | `02_goal.yaml`, `tools/model_transform.py` |
| Framework validates both | Deterministic parser/validator exists | WORKING | Validated by negative configuration tests | `tools/model_transform.py`, `tools/test_model_transform.py` |
| Generates workflow_model.yaml | Deterministic generation exists | WORKING | Generated output must not be manually edited | `tools/model_transform.py` |
| Generates project BDI beliefs/configuration | Generates `bdi_project.asl` and composes `bdi_agent.asl` | WORKING | Output is generated into repository files | `tools/model_transform.py` |
| Starts Java/Jason BDI controller | `run_healthy_demo.ps1`, `run-demo.ps1` | PARTIAL | Real mode needs credentials and persistent endpoints; mock mode is runnable | `java-jason/run_healthy_demo.ps1`, `run-demo.ps1` |
| BDI selects executable entity | Generic `nextentity(Entity)` reasoning | WORKING | Proven by eight deterministic scenarios | `bdi_generic.asl` |
| BDI calls `run_job(Entity)` | Java environment implements the single external action | WORKING | Proven by Java tests and mock scenarios | `ObservationEnvironment.java` |
| Requested CI/CD entity executes through GitHub Actions | REST dispatch/poll adapter and `workflow_dispatch` workflow exist | UNTESTED | No real GitHub dispatch was run in this audit | `GitHubActionsWorkflowExecutor.java`, `.github/workflows/entity-execution.yml` |
| Deployment is performed through GitHub Actions | Staging/production Docker commands exist | PARTIAL | Deployment is only runner-local and ephemeral | `.github/workflows/entity-execution.yml`, `.github/workflows/ci-cd.yml` |
| Execution result returns to Java/Jason | Exact run polling emits normalized execution observations | UNTESTED | Requires a real GitHub run | `GitHubActionsWorkflowExecutor.java`, `CompositeObservationProvider.java` |
| Deployed application exposes OpenTelemetry runtime telemetry | App exposes Prometheus metrics from the OpenTelemetry SDK | WORKING | No collector or persistent telemetry backend exists | `app/payment_service.py`, `telemetry/TelemetryAdapter.java` |
| Runtime telemetry is normalized and delivered to BDI | Health/metrics adapter and Jason belief adapter exist | PARTIAL | Local persistent Compose endpoints work conceptually; hosted-runner deployments are unreachable | `TelemetryAdapter.java`, `JasonBeliefAdapter.java` |
| BDI evaluates new state and chooses continue/rerun/recover/stop | Generic plans implement these decisions | WORKING | Deterministic mock validation passed; runtime degradation support is limited to normalized status failure and configured recovery | `bdi_generic.asl` |
| Controlled failures/runtime degradation can be injected | Workflow input plan and local service environment injection exist | PARTIAL | Execution failure is supported; live runtime injection only affects a persistent local target, not an ephemeral GitHub runner deployment | `ExperimentExecutionPlan.java`, `inject-error.ps1`, `entity-execution.yml` |
| Telemetry changes are visible | New telemetry monitor displays health, error rate, latency, and freshness for staging/production | PARTIAL | Requires reachable persistent endpoints; no dashboard | `tools/telemetry_monitor.ps1` |
| BDI beliefs/decisions/actions are visible | MAS console and BDI JSON-lines monitor exist | WORKING | Real event stream requires a real run; mock output is proven | `tools/bdi_monitor.ps1`, `StructuredEventLogger.java` |
| Logs are saved for comparison | Scenario JSON/logs and real JSONL structured logs exist | WORKING | Real log content not produced without real run | `java-jason/scenario-artifacts`, `StructuredEventLogger.java` |

## Critical deployment questions

### Is deployment performed by GitHub Actions?

Yes. The workflow executes Docker build, test, staging, production, and
rollback commands on GitHub-hosted runners.

### Where does the resulting application run?

It runs inside Docker on the GitHub Actions runner executing the current job.

### Does it remain alive after the runner terminates?

No. The runner and its containers are ephemeral.

### Can the local Java telemetry adapter reach it continuously?

No. The local adapter can only reach URLs configured through
`STAGING_HEALTH_URL`, `STAGING_METRICS_URL`, `PRODUCTION_HEALTH_URL`, and
`PRODUCTION_METRICS_URL`. The runner-local ports are not reachable from the
research machine after the job.

### Can failure injection modify the running deployment?

Only while a persistent deployment target exists. The current local Compose
services are persistent on the research machine, but they are not the result of
the GitHub deployment. Changing them does not change the ephemeral GitHub
deployment.

### Can rollback replace/recover persistent production?

The rollback workflow can execute a rollback command, but the current
`rollback_production` job also runs on an ephemeral hosted runner. It does not
replace a persistent production service.

## Minimum deployment target options

1. **Recommended for this research demo: self-hosted GitHub runner.** Install
   a Linux self-hosted runner with Docker on the research machine or a
   dedicated lab VM, give it a label such as `bdi-demo`, and run deployment
   jobs there. The workflow must select that label instead of
   `ubuntu-latest`. Containers and ports then remain on the same persistent
   host that the Java adapter can reach.

2. **Remote persistent Docker VM.** Keep GitHub-hosted build/test jobs, then
   deploy the image to a persistent VM through SSH or a controlled registry
   pull. Configure the Java adapter with the VM's health and metrics URLs.

3. **Managed deployment platform.** Use a persistent container service. This is
   the most operationally realistic but is unnecessary for the first research
   demonstration.

No cloud infrastructure was added because the repository does not contain
credentials, a target host, or a deployment choice. Selecting and configuring
one of these targets is the remaining external decision.

## Generation path

The deterministic path now works:

```text
01_pipeline.yaml + 02_goal.yaml
  -> tools/model_transform.py
  -> 03_workflow_model.yaml
  -> bdi_project.asl
  -> bdi_agent.asl = generated project facts + bdi_generic.asl
```

This is executable, not documentation-only. The command is:

```powershell
py .\tools\model_transform.py
```

The direct test command is also now runnable from the repository root:

```powershell
py .\tools\test_model_transform.py
```

## Visible commands added

### Mock validation

```powershell
.\run-demo.ps1 -Mode mock
```

This validates/generates the model and runs all eight deterministic BDI
scenarios. It uses no GitHub, Docker, or live telemetry.

### Real mode

```powershell
$env:GITHUB_TOKEN = '<token>'
$env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
$env:GITHUB_REF = 'main'
$env:STAGING_HEALTH_URL = 'https://persistent-host/health'
$env:STAGING_METRICS_URL = 'https://persistent-host/metrics'
$env:PRODUCTION_HEALTH_URL = 'https://persistent-host/health'
$env:PRODUCTION_METRICS_URL = 'https://persistent-host/metrics'
$env:BDI_PERSISTENT_DEPLOYMENT_CONFIRMED = '1'
.\run-demo.ps1 -Mode real
```

Real mode opens a telemetry monitor window, a BDI structured-event monitor
window, and runs the Java/Jason controller in the invoking window. It refuses
to run until `BDI_PERSISTENT_DEPLOYMENT_CONFIRMED=1` is set deliberately.

### Runtime injection

For a local Compose service (development-only):

```powershell
.\inject-error.ps1 -Scenario high-error-rate -Entity production
.\inject-error.ps1 -Scenario high-latency -Entity production
.\inject-error.ps1 -Scenario unhealthy -Entity production
.\inject-error.ps1 -Scenario healthy -Entity production
```

For the actual GitHub persistent deployment, set
`BDI_DEPLOYMENT_MODE=runner`, `BDI_DEPLOYMENT_HOST`, and, for a remote host,
`BDI_DEPLOYMENT_SSH_USER` before using the same commands. In runner mode the
script stops/starts or recreates the actual `payment-production` or
`payment-staging` container on the deployment host.

For an execution failure plan, create the plan before starting real mode:

```powershell
.\inject-error.ps1 -Scenario execution-failure -Entity production
```

The telemetry monitor visibly reports health, error rate, latency, and data
freshness. The BDI monitor reports structured decisions, percepts, normalized
beliefs, GitHub run IDs, and terminal events when available.

High-error-rate and high-latency are currently visible observations only. The
current goal vocabulary has no configured error-rate or latency threshold, so
they do not independently trigger a BDI recovery plan. The first complete
runtime response supported by the current model is an unhealthy health
observation normalized to `status(production,fail)`, followed by configured
recovery selection.

## Changes made in this pass

- Added `run-demo.ps1` for validation/generation and visible mock/real startup.
- Added `tools/telemetry_monitor.ps1` for staging/production live telemetry.
- Added `tools/bdi_monitor.ps1` for structured BDI decision/event viewing.
- Added `inject-error.ps1` for controlled local service and execution-plan
  injection.
- Added `tools/__init__.py` and a direct-execution import fallback so the
  documented model test command works from the repository root.
- Added a generic parameterized runtime-failure response in
  `bdi_generic.asl`; regenerated `bdi_agent.asl`.

## Tests actually run

| Test | Result |
|---|---|
| `py tools/test_model_transform.py` | PASS, 9 tests |
| `py tools/model_transform.py` | PASS |
| `run_scenarios.ps1` | PASS, 8/8 deterministic scenarios |
| `run-demo.ps1 -Mode mock` | PASS |
| mock MAS launcher | PASS; Jason RTS and mind inspector started |
| real GitHub Actions dispatch | NOT RUN |
| real persistent deployment | BLOCKED; no target configured |
| real end-to-end telemetry-to-BDI recovery | NOT RUN |
| Docker application tests | NOT RUN in this pass |

## Remaining blockers

1. Choose and provision a persistent deployment target.
2. Change the deployment workflow to target that host while preserving the
   atomic `run_job(Entity)` interface.
3. Configure reachable telemetry URLs for that target.
4. Run one real healthy pipeline through build, test, security, staging, and
   production.
5. Run one real unhealthy-production case and verify telemetry-to-BDI recovery
   and rollback on the persistent target.
6. Add explicit goal configuration for error-rate/latency thresholds if those
   metrics must trigger BDI decisions rather than only be displayed.
