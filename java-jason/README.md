# Generic Java/Jason environment layer

This module is infrastructure only. It does not contain pipeline dependency reasoning, retry policy, recovery selection, or achievement/maintenance/avoidance logic.

## Interfaces

```java
interface WorkflowExecutor {
    void runJob(String entity) throws Exception;
}

interface ObservationProvider {
    List<Observation> getObservations() throws Exception;
}

interface BeliefAdapter {
    String convert(Observation observation);
}
```

The Jason environment accepts exactly one BDI-facing external action:

```text
run_job(Entity)
```

The Java environment forwards the entity unchanged to `WorkflowExecutor`. It does not decide what entity should run next.

## Belief mapping

Normalized observations are mapped generically:

```text
execution_status(success) -> status(Entity, success)
execution_status(other)   -> status(Entity, fail)
health(healthy)           -> status(Entity, success)
health(other)             -> status(Entity, fail)
duration(Time)            -> duration(Entity, Time)
error_rate(Value)         -> metric(Entity, error_rate, Value)
latency(Value)            -> metric(Entity, latency, Value)
other properties         -> observation(Entity, Property, Value)
```

This is representation conversion, not policy.

## Implementations

- `GitHubActionsWorkflowExecutor`: dispatches one GitHub Actions workflow entity.
- `TelemetryObservationProvider`: wraps the existing OpenTelemetry/Prometheus adapter.
- `MockWorkflowExecutor`: records requested entities and emits mock execution observations.
- `MockObservationProvider`: in-memory provider for tests.
- `ObservationEnvironment`: Jason transport and percept publication layer.

## Compile the Java layer

Jason 3.3.0 is installed locally at `C:\Program Files\jason-bin-3.3.0`. The following commands avoid requiring a separate Gradle installation:

```powershell
cd java-jason
New-Item -ItemType Directory -Force build\classes | Out-Null
$jasonJar = 'C:\Program Files\jason-bin-3.3.0\bin\jason'

& 'C:\Program Files\Java\jdk-23\bin\javac.exe' --release 17 `
  -cp $jasonJar `
  -d build\classes `
  (Get-ChildItem src\main\java\harness -Filter '*.java').FullName `
  (Get-ChildItem ..\telemetry -Filter '*.java').FullName
```

## Run the unit test

```powershell
New-Item -ItemType Directory -Force build\test-classes | Out-Null
& 'C:\Program Files\Java\jdk-23\bin\javac.exe' --release 17 `
  -cp "$jasonJar;build\classes" `
  -d build\test-classes `
  src\test\java\harness\EnvironmentLayerTest.java

& 'C:\Program Files\Java\jdk-23\bin\java.exe' `
  -cp "$jasonJar;build\classes;build\test-classes" `
  harness.EnvironmentLayerTest
```

## Run the Jason mock integration test

The Gradle task executes the `.mas2j` file and is the preferred way to start
the MAS console:

```powershell
cd java-jason
gradle runMock --console=plain --no-daemon
```

The real BDI MAS console is started with:

```powershell
cd java-jason
gradle runReal --console=plain --no-daemon
```

`runReal` executes `real.mas2j`, which loads the generated root-level
`bdi_agent.asl` and wires `GitHubEnvironment`. It requires the real-mode
environment variables described below.

```powershell
New-Item -ItemType Directory -Force build\tmp | Out-Null

& 'C:\Program Files\Java\jdk-23\bin\java.exe' `
  '-Djava.awt.headless=true' `
  ('-Djava.io.tmpdir=' + (Resolve-Path build\tmp)) `
  ('-Djava.util.logging.config.file=' + (Resolve-Path logging.properties)) `
  -cp "$jasonJar;build\classes" `
  jason.infra.local.RunLocalMAS mock.mas2j
```

Expected evidence includes:

```text
action agent=mock_agent run_job entity=test
belief=status(test,success)
INTEGRATION_BELIEF_RECEIVED status(test, success)
```

The mock test does not contact GitHub, Docker, OpenTelemetry, or the live application.

## GitHub Actions executor

The design and API constraints are documented in
[github-actions-executor-design.md](github-actions-executor-design.md).

`GitHubActionsWorkflowExecutor` dispatches `.github/workflows/entity-execution.yml`
with `workflow_dispatch`, requests the exact created run ID, polls only that run,
and publishes `execution_status` plus `duration` observations. It supports
`build`, `test`, `security`, `staging`, `production`, and
`rollback_production` without exposing GitHub concepts to Jason.

The adapter must be configured at runtime. For example, the required values are:

```text
GITHUB_API_URL=https://api.github.com
GITHUB_REPOSITORY=OWNER/REPOSITORY
GITHUB_WORKFLOW_FILE=entity-execution.yml
GITHUB_TOKEN=<runtime secret>
GITHUB_REF=main
```

The token is passed in the `Authorization` header and is never committed. A
successful `build` run ID is retained by the adapter and supplied as
`source_run_id` when `run_job(rollback_production)` is requested.

The real workflow can be run manually only after the workflow file is present on
the repository's default branch. The conventional chained `ci-cd.yml` remains
available separately; the entity workflow is the one used by the BDI executor.

## Real end-to-end healthy demonstration

See [end-to-end-integration.md](end-to-end-integration.md) for the required
reachable staging/production telemetry URLs and runtime-only GitHub settings.
After setting those values, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\java-jason\run_healthy_demo.ps1
```

Structured JSON-lines transition records are written to the configured
`BDI_LOG_FILE` (default: `java-jason\runtime-artifacts\runtime.jsonl`).

## Deterministic BDI scenario harness

`ScenarioEnvironment` uses only `ScenarioWorkflowExecutor` and `ScenarioObservationProvider`. It never calls GitHub Actions or OpenTelemetry. Each scenario supplies a fixed outcome sequence per entity, so the BDI agent can be evaluated repeatably.

Run all six scenarios and write logs plus JSON evaluation records:

```powershell
powershell -ExecutionPolicy Bypass -File .\java-jason\run_scenarios.ps1
```

The runner asserts the `run_job` sequence and writes one pair of artifacts per scenario under `java-jason\scenario-artifacts\`:

| Scenario | Expected result |
|---|---|
| 1 | `build,test,security,staging,production`; master goal achieved |
| 2 | `build,test,test,security,staging,production`; only `test` reruns |
| 3 | `build,test,test`; retry limit stops the workflow; no downstream entity |
| 4 | normal entities through two production attempts, then `rollback_production` |
| 5 | production duration violation, then `rollback_production` |
| 6 | avoidance violation, then `rollback_production` |

Each JSON record captures initial beliefs, normalized percepts, selected-plan log lines, `run_job` calls, belief changes, final beliefs, and achievement/maintenance/avoidance outcomes. The scenario environment stops the local MAS after the expected terminal action; this shutdown is test harness lifecycle code, not BDI policy.
