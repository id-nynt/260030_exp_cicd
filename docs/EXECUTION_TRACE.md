# Execution Traces

This trace follows the current implementation. A live GitHub execution was not
triggered during the audit.

## Healthy execution

### Startup and master goal

`java-jason/real.mas2j` selects `harness.GitHubEnvironment` and loads the root
`bdi_agent.asl`. `GitHubEnvironment.createComponents` wires the real executor,
composite provider, belief adapter, correlation registry, and structured logger
(`java-jason/src/main/java/harness/GitHubEnvironment.java:8-53`).

Static model/state beliefs are defined in `bdi_agent.asl:8-58`. The initial goal
`!master_goal` is at line 117. Its plan at lines 121-126 posts:

```text
!need_achieve(production, success)
!need_achieve(staging, success)
!check_avoidance
```

The first `need_achieve` start plan (`bdi_agent.asl:148-155`) sets
`workflow_started` and calls `!run_pipeline`.

### Build selection and dispatch

`nextentity(Entity)` (`bdi_agent.asl:68-79`) selects `build` because it is active,
not running, not terminal, not successful, and its empty dependency list holds.
The next-entity `run_pipeline` plan (`bdi_agent.asl:192-195`) calls
`!run_entity(build)`.

The generic entity plan (`bdi_agent.asl:210-231`) increments `run_sequence` and
`attempt_count`, clears old attempt state, adds `running(build)` and
`run_attempt(build,1)`, then invokes the only external action:

```text
run_job(build)
```

Jason calls `ObservationEnvironment.executeAction`
(`java-jason/src/main/java/harness/ObservationEnvironment.java:61-83`). It
validates the functor/arity, extracts `build`, logs the BDI action, and calls
`WorkflowExecutor.runJob("build")`.

`GitHubActionsWorkflowExecutor.runJob`
(`java-jason/src/main/java/harness/GitHubActionsWorkflowExecutor.java:65-105`):

1. validates the entity;
2. creates a UUID execution ID;
3. reads the optional per-attempt experiment injection;
4. POSTs a workflow dispatch request;
5. receives `workflow_run_id`;
6. polls that exact run until completion;
7. emits `execution_status` and `duration` observations.

The request targets `.github/workflows/entity-execution.yml`. Its single
`execute_entity` job conditionally executes the build branch, saves the Docker
image, and uploads `payment-image`.

### Result and belief update

After GitHub success, the executor queues:

```text
Observation(build, execution_status, success, timestamp)
Observation(build, duration, elapsed_ms, timestamp)
```

`CompositeObservationProvider` combines these with telemetry. The environment
poller calls `getObservations` once per second
(`ObservationEnvironment.java:120-136`).

`JasonBeliefAdapter.convert` maps execution success to
`status(build,success)` (`JasonBeliefAdapter.java:10-21`). The environment
publishes the Jason percept at `ObservationEnvironment.java:88-108`.

The BDI bridge (`bdi_agent.asl:240-250`) creates the attempt-qualified status.
The success handler (`bdi_agent.asl:259-270`) creates
`phase_result(build,success)`. The phase-result plan (`bdi_agent.asl:358-369`)
removes `running(build)`/`run_attempt`, checks maintenance and avoidance, and
calls `!run_pipeline`.

### Remaining normal entities

The same generic path repeats for `test`, `security`, `staging`, and
`production`. The dependency facts are:

```text
test       depends(test,[build])
security   depends(security,[test])
staging    depends(staging,[security])
production depends(production,[staging])
```

They are defined in `bdi_agent.asl:20-24`. The entity workflow executes only the
requested conditional branch; image building needed by an individual branch is
ordinary infrastructure inside that GitHub execution, not another BDI action.

For staging/production, the workflow starts the Docker service and checks
`/health`. The service is `app/payment_service.py`, built by `app/Dockerfile`.

### Production completion

Production has `max_duration(production,100000)` at `bdi_agent.asl:38`. The
production success bridge waits for duration (`bdi_agent.asl:273-316`). The
maintenance plan at `bdi_agent.asl:491-503` proves the duration is within the
limit, then avoidance is checked.

The completed `run_pipeline` plan (`bdi_agent.asl:180-188`) removes
`workflow_active`, adds `workflow_completed`, and calls `!check_master_goal`.
The master check (`bdi_agent.asl:560-579`) requires production and staging
success, acceptable production duration, and no avoidance violation before
adding `master_goal_achieved`.

The healthy action sequence is:

```text
build -> test -> security -> staging -> production
```

## Production failure and recovery

After staging success, production is selected through the same dependency rule.
Its failed execution returns `Observation(production,execution_status,fail,...)`.
The adapter creates `status(production,fail)`; the BDI failure bridge at
`bdi_agent.asl:318-325` creates `phase_result(production,fail)`.

The retry plan (`bdi_agent.asl:371-381`) sees `attempt_count(production,1)` and
`max_retries(1)`, removes running/phase state, and calls `!run_pipeline`. The
second production execution is therefore the only rerun; upstream successful
entities are not rerun.

On the second failure, the retry condition is false. The recovery failure plan
(`bdi_agent.asl:383-393`) resolves the static belief
`recovery(production,rollback_production)` (`bdi_agent.asl:27`), marks production
terminal, and calls `!recover(production)`.

The recovery-start plan (`bdi_agent.asl:413-436`) increments the recovery
attempt, adds `running(rollback_production)`, and invokes
`run_job(rollback_production)`. The current Java adapter sends that entity to
the rollback branch of `entity-execution.yml`, using the last successful build
run as `source_run_id`. It does not dispatch the separate
`.github/workflows/rollback-production.yml` by default.

Successful rollback uses `bdi_agent.asl:438-457`:

```text
-running(rollback_production)
+terminal(rollback_production,recovered)
-workflow_active
+workflow_stopped
!check_master_goal
```

Normal progression does not resume. Failed rollback uses
`bdi_agent.asl:459-478`, marks the recovery failed, and also stops the workflow.

The failure sequence is therefore:

```text
production failure
  -> status(production,fail)
  -> phase_result(production,fail)
  -> retry_allowed(production)
  -> second run_job(production)
  -> recovery(production,rollback_production)
  -> run_job(rollback_production)
  -> workflow_stopped
```

## HOW THIS PROJECT WORKS IN 5 MINUTES

### What starts the system?

`run_healthy_demo.ps1` or `experiments/run_experiments.ps1` compiles the Java
layer and starts Jason using `real.mas2j`. Jason loads `bdi_agent.asl` and
constructs `GitHubEnvironment`.

### How does BDI choose an entity?

`nextentity(Entity)` checks `workflow_active`, running/terminal/success state,
and `holds(Requirements)`. `holds` recursively requires successful dependency
phase results.

### How is that entity actually executed?

The BDI invokes `run_job(Entity)`. Java forwards the entity to
`GitHubActionsWorkflowExecutor`, which dispatches and polls one
`workflow_dispatch` run. GitHub executes the entity's ordinary Docker/test/
deployment steps.

### How does the result get back to BDI?

The executor emits normalized execution observations. Telemetry separately polls
health and metrics. The composite provider combines both, and the belief adapter
turns them into Jason percepts.

### How does BDI choose what happens next?

Status/duration bridge plans create qualified attempt beliefs and
`phase_result`. Success advances through dependency reasoning; failure retries,
recovers, or stops according to the AgentSpeak plans.

### How does telemetry reach BDI?

The app's OpenTelemetry SDK exposes Prometheus-compatible metrics and JSON health
status. `TelemetryAdapter` polls them, calculates normalized error rate/latency,
and emits `Observation` records. The Java environment publishes beliefs. There
is no collector or persistent telemetry backend.

### How does rollback work?

After production exhausts its retry budget, BDI resolves the recovery relation
and invokes the same generic action with `rollback_production`. The adapter
provides the previous successful build artifact run ID.

### What makes an experiment finish?

The experiment runner watches controller output for master success, workflow
stop, recovery completion/failure, or timeout. It stops traffic and containers,
writes JSONL plus `result.json`, and checks the configured action/state/
observation assertions.
