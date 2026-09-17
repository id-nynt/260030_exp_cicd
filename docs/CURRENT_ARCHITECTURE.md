# Current Architecture

This document describes the repository as implemented, not only as proposed in
`PROJECT.md`. It deliberately distinguishes executable files from model/config
files and from generated artifacts.

## Relevant repository tree

```text
.
├── PROJECT.md
├── README.md
├── 01_pipeline.yaml
├── 02_goal.yaml
├── 03_workflow_model.yaml
├── CI_CD_ENTITIES.md
├── bdi_agent.asl
├── docker-compose.yml
├── app/
│   ├── Dockerfile
│   ├── payment_service.py
│   ├── requirements.txt
│   └── test_payment_service.py
├── .github/workflows/
│   ├── ci-cd.yml
│   ├── entity-execution.yml
│   └── rollback-production.yml
├── telemetry/
│   ├── Observation.java
│   ├── TelemetryAdapter.java
│   ├── README.md
│   └── demo.ps1
├── java-jason/
│   ├── real.mas2j
│   ├── mock.mas2j
│   ├── scenario.mas2j
│   ├── run_healthy_demo.ps1
│   ├── run_scenarios.ps1
│   ├── github-actions-executor-design.md
│   ├── end-to-end-integration.md
│   └── src/{main, test}/...
└── experiments/
    ├── scenarios.json
    ├── run_experiments.ps1
    └── README.md
```

Build classes, scenario logs, and experiment result directories are generated
runtime artifacts and are intentionally not expanded here.

## Important-file inventory

| File | Purpose | Layer | Kind | Calls/uses | Used by | Minimal end-to-end? |
|---|---|---|---|---|---|---|
| `PROJECT.md` | Architectural constraints and boundaries | project | documentation | Names interfaces and responsibilities | All implementation decisions | Yes, as specification |
| `01_pipeline.yaml` | Original abstract CI/CD model | model | configuration | Refers to `scripts/*.sh`, which are absent | Human/model review | No; not executable |
| `02_goal.yaml` | Achievement, maintenance, avoidance goals | goal model | configuration | Names production/staging/test status | Human and BDI translation | Yes conceptually |
| `03_workflow_model.yaml` | Generated entities, dependencies, observations, recovery | workflow model | generated configuration | Mirrors the intended model | Human/BDI review | Yes conceptually |
| `bdi_agent.asl` | Generic AgentSpeak controller and policy | BDI | source code | Uses Jason beliefs/events and `run_job(Entity)` | `real.mas2j`, `scenario.mas2j` | Yes |
| `app/payment_service.py` | Flask payment demo, failure injection, OTel metrics/traces | application | source code | Flask, OpenTelemetry, Prometheus exposition | Dockerfile, Compose, workflows | Yes |
| `app/test_payment_service.py` | Application tests | application | test | Imports `create_app` | Docker test step | Yes |
| `app/Dockerfile` | Reproducible app image | application/runtime | configuration | Installs requirements and launches service | Compose, GitHub workflows | Yes |
| `docker-compose.yml` | Persistent local staging/production instances | local runtime | configuration | Builds `./app`; maps ports 8081/8082 | README, experiment runner | Yes for local telemetry |
| `.github/workflows/ci-cd.yml` | Conventional chained GitHub pipeline | CI/CD | workflow configuration | Docker build, test, deploy, health checks | GitHub on push/manual dispatch | No for BDI entity dispatch; useful baseline |
| `.github/workflows/entity-execution.yml` | Independently dispatchable atomic entity workflow | CI/CD | workflow configuration | Uses `inputs.entity`; executes conditional steps | Java GitHub executor | Yes |
| `.github/workflows/rollback-production.yml` | Separate manual rollback workflow | CI/CD | workflow configuration | Downloads artifact and deploys rollback | Manual GitHub use | Not used by current Java default |
| `telemetry/Observation.java` | Stable normalized observation record | telemetry | source code | Serializes entity/property/value/timestamp | Telemetry adapter, Java layer | Yes |
| `telemetry/TelemetryAdapter.java` | Polls `/health` and `/metrics`, normalizes values | telemetry | source code | Java HTTP client and regex parsers | Telemetry providers | Yes |
| `java-jason/.../ObservationEnvironment.java` | Jason environment action/percept bridge | Java/Jason | source code | Calls `WorkflowExecutor`, `ObservationProvider`, `BeliefAdapter` | MAS environment | Yes |
| `java-jason/.../WorkflowExecutor.java` | Generic `runJob(String entity)` boundary | Java/Jason | source code | No implementation dependency | Executor implementations | Yes |
| `java-jason/.../GitHubActionsWorkflowExecutor.java` | Dispatches and polls one GitHub run | Java/Jason | source code | GitHub REST API, experiment plan, structured logger | `GitHubEnvironment` | Yes for real path |
| `java-jason/.../GitHubEnvironment.java` | Wires real executor, telemetry, correlation, logging | Java/Jason | source code | All real adapters | `real.mas2j` | Yes |
| `java-jason/.../JasonBeliefAdapter.java` | Maps normalized observations to Jason literals | Java/Jason | source code | `Observation` fields | `ObservationEnvironment` | Yes |
| `java-jason/.../CompositeObservationProvider.java` | Combines telemetry and execution observations | Java/Jason | source code | Provider delegate and queue | `GitHubEnvironment` | Yes |
| `java-jason/.../StructuredEventLogger.java` | Writes JSON-lines transition records | cross-cutting | source code | Java filesystem/logging | Real environment and executor | Yes for evaluation |
| `java-jason/.../Mock*.java` | Mocks for isolated environment tests | Java/Jason | test support | Generic interfaces | Unit/mock tests | No |
| `java-jason/.../Scenario*.java` | Deterministic in-memory BDI scenario harness | BDI test | test support | Jason environment and mock observations | `run_scenarios.ps1` | No for real path |
| `java-jason/run_healthy_demo.ps1` | Starts real MAS/controller | integration | script | Invokes Gradle `runReal`, which launches `real.mas2j` | Developer | Yes |
| `java-jason/run_scenarios.ps1` | Runs six earlier mock BDI scenarios | BDI test | script | Java/Jason scenario MAS | Developer | No |
| `experiments/scenarios.json` | Twelve configuration-driven experiment definitions | experiments | configuration | Defines local and GitHub injections/assertions | `run_experiments.ps1` | Yes for experiment protocol |
| `experiments/run_experiments.ps1` | Resets Docker, starts controller, collects/asserts results | experiments | script | Docker Compose, Java, scenario catalog | Developer/experiment execution | Yes |
| `experiments/README.md` | Experiment usage and result schema | experiments | documentation | Documents runner | Developer | Yes |
| `java-jason/real.mas2j` | MAS configuration using real environment | Jason runtime | configuration | Loads `bdi_agent.asl`, `GitHubEnvironment` | `run_healthy_demo.ps1`, experiment runner | Yes |
| `java-jason/mock.mas2j` | MAS configuration using mock environment | Jason test | configuration | Loads `mock_agent.asl` | README/manual test | No |
| `java-jason/scenario.mas2j` | MAS configuration using deterministic scenario environment | Jason test | configuration | Loads root `bdi_agent.asl` | `run_scenarios.ps1` | No |

## Actual data and control flow

```text
AgentSpeak bdi_agent.asl
  -- run_job(Entity) external action -->
ObservationEnvironment.executeAction
  -- WorkflowExecutor.runJob(entity) -->
GitHubActionsWorkflowExecutor
  -- POST workflow_dispatch + GET exact run -->
.github/workflows/entity-execution.yml
  -- Docker build/test/deploy/health steps -->
payment_service.py in a runner container
  -- OTel SDK / PrometheusMetricReader -->
/health and /metrics HTTP endpoints
  -- TelemetryAdapter.pollOnce -->
TelemetryObservationProvider / MultiTelemetryObservationProvider
  -- CompositeObservationProvider -->
ObservationEnvironment.publishObservations
  -- JasonBeliefAdapter.convert -->
Jason percepts such as status(test,success)
  -- BDI event/plan reconsideration -->
next run_job(Entity)
```

The execution-observation path is parallel to the runtime telemetry path:
`GitHubActionsWorkflowExecutor` publishes `execution_status` and `duration` to
`CompositeObservationProvider`; the environment polls and converts them in the
same way.

The application exposes an OpenTelemetry-backed Prometheus endpoint. There is
no OpenTelemetry Collector or remote Prometheus backend in this repository.
`TelemetryAdapter` directly scrapes the application endpoint. Therefore the
conceptual arrow “OpenTelemetry -> collector/backend” is **NOT IMPLEMENTED**;
the implemented arrow is “OpenTelemetry SDK -> Prometheus exposition -> Java
HTTP poller”.

The real deployment telemetry arrow is also only partial: GitHub-hosted runner
containers are ephemeral and their ports are not reachable by local Java after
the job. `GitHubEnvironment` expects persistent reachable URLs from
`STAGING_HEALTH_URL`, `STAGING_METRICS_URL`, `PRODUCTION_HEALTH_URL`, and
`PRODUCTION_METRICS_URL`; the experiment runner supplies local Compose URLs.

## Correlation and structured logging

`CorrelationContext`, `CorrelationRegistry`, and `StructuredEventLogger` keep
experiment/release/entity/execution/run/environment metadata outside the Jason
belief vocabulary. The major events are:

```text
integration_started
bdi_action_requested
bdi_decision
github_dispatch_accepted
github_execution_started
observation_collected
percept_published
execution_terminal
```

These are written to `BDI_LOG_FILE` as JSON lines. The stable `Observation` type
is deliberately unchanged; correlation is log/adapter metadata, not a new BDI
term.
