# End-to-end integration design

## Interface mismatches and workarounds

The existing public contracts are intentionally small:

```java
void runJob(String entity)
List<Observation> getObservations()
String convert(Observation observation)
```

`Observation` contains only `entity`, `property`, `value`, and `timestamp`. Adding
experiment IDs, release IDs, or GitHub run IDs to that record would change the
stable telemetry-to-BDI abstraction. Therefore those fields remain in an
adapter-owned correlation registry and structured transition logs. Jason still
receives only generic beliefs such as `status(test,success)` and
`metric(production,latency,850)`.

The second mismatch is environmental: a GitHub-hosted runner can start Docker
containers during a workflow, but those containers and runner ports disappear
when the job ends and are not directly reachable from the local Java process.
The integration therefore requires `STAGING_*_URL` and `PRODUCTION_*_URL`
values pointing to persistent, reachable demo instances. The workflow's health
checks still validate the deployment it performs on the runner; the Java
observation provider monitors the configured reachable instances.

No BDI plan or public interface is changed to accommodate either issue.

## Transition chain

```text
Jason run_job(Entity)
  -> ObservationEnvironment.executeAction
  -> GitHubActionsWorkflowExecutor.dispatch
  -> GitHub workflow entity-execution.yml
  -> application/deployment checks
  -> reachable app health/metrics endpoints
  -> MultiTelemetryObservationProvider
  -> CompositeObservationProvider
  -> JasonBeliefAdapter
  -> ObservationEnvironment percept
  -> existing BDI plans reconsider
  -> next run_job(Entity)
```

The executor generates an experiment-scoped execution UUID and receives the
authoritative GitHub run ID. The registry associates:

```text
experiment_id, release_id, entity, execution_id, github_run_id, environment
```

Every transition is emitted as one structured JSON log event. The BDI decision
event is emitted by the adapter at the point where `run_job(Entity)` has been
accepted and its exact external run ID is known; this records the selected
`run_entity`/`run_job` action without adding decision logic to Jason.

## Healthy demonstration

Set runtime-only values:

```powershell
$env:GITHUB_TOKEN = '<token with Actions read/write access>'
$env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
$env:GITHUB_REF = 'main'
$env:BDI_EXPERIMENT_ID = 'healthy-001'
$env:BDI_RELEASE_ID = 'candidate-001'
$env:STAGING_HEALTH_URL = 'https://staging.example/health'
$env:STAGING_METRICS_URL = 'https://staging.example/metrics'
$env:PRODUCTION_HEALTH_URL = 'https://production.example/health'
$env:PRODUCTION_METRICS_URL = 'https://production.example/metrics'
powershell -ExecutionPolicy Bypass -File .\java-jason\run_healthy_demo.ps1
```

The command starts the Jason agent with the real GitHub adapter and writes
structured transition events to `java-jason\runtime-artifacts\healthy-001.jsonl`.
It requires the entity workflow to be present on the repository default branch,
valid GitHub credentials, and reachable telemetry endpoints. No failure
experiments are included in this demonstration.
