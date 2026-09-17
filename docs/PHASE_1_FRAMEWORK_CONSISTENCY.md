# Phase 1 — Framework Consistency

Date: 2026-09-17

Scope: verification and reconciliation only. Project 2, live GitHub Actions,
and real deployment experiments were not run.

## Authoritative source model

The source configuration is `01_pipeline.yaml` for executable workflow
structure and `02_goal.yaml` for developer intent. `03_workflow_model.yaml` is
the authoritative normalized workflow/policy representation consumed by the
BDI configuration. `bdi_agent.asl` contains the project-specific BDI
translation plus controller-derived runtime state and generic reasoning.

| Source configuration | Workflow-model representation | BDI representation |
|---|---|---|
| Pipeline job key (`build`, `test`, `security`, `staging`, `production`, `rollback_production`) | `entities(E)` | `entity(Entity)`; recovery targets also have `recovery_entity(Entity)` |
| Pipeline `needs` edges | `dependencies(D)` | `depends(Entity, Requirements)` |
| Dependency sink (`production` in this linear graph) | No explicit field; derived final entity | `final_phase(production)` |
| Job result and runtime measurements | `observable_properties(O)` and `execution.observation_schema` | percepts `status/2`, `duration/2`, `metric/3` |
| `02_goal.yaml: achieve(A)` | No separate goal section; retained as generated BDI goal data | `achievement(Entity, success)` and `achievement_satisfied/2` |
| `02_goal.yaml: maintain(M)` and `duration_unit` | `O.duration` plus observation duration unit | `max_duration/2`, `duration_ok/3`, `duration_violation/3`, `duration_unit/1` |
| `02_goal.yaml: avoid(V)` predecessor conditions | No separate avoidance section; represented by workflow observations and goal translation | `avoid_missing/2`, `avoidance_violation/1` |
| Recovery relationship implied by pipeline recovery job and model R | `recovery(R)` | `recovery(Entity, Recovery)` and `recovery_entity(Recovery)` |
| `execution.max_retries` in workflow model | `execution.max_retries: 1` | `max_retries(1)` |
| Execution attempt state | Not an external source value; `attempt_id_required: false` | `attempt_count/2`, `run_attempt/2`, `running/1` |

`final_phase(production)` is a project-specific BDI convenience belief: it is
derived from the dependency graph's terminal normal entity, not explicitly
declared in either YAML source. A future generator should derive it rather than
accepting an independent conflicting value.

The following BDI beliefs are controller state or derived state, not project
configuration: `run_sequence/1`, `attempt_count/2`, `run_attempt/2`,
`workflow_active`, `workflow_started`, `workflow_stopped`,
`workflow_completed`, `running/1`, `terminal/2`, `success_handling/1`, and
`master_goal_achieved`. `recovery_entity/1` and `achievement_satisfied/2` are
derived translations, not additional source configuration.

## Vocabulary contract

The layers are intentionally distinct:

| Semantic layer | Value/term | Meaning |
|---|---|---|
| External/raw execution | `success`, `failure`, `cancelled`, `skipped`, `timeout` | GitHub/mock execution conclusion before BDI normalization |
| External/raw runtime | `healthy`, `unhealthy`, `unknown` | `/health` response or unavailable health endpoint |
| Normalized observation | `Observation(Entity, execution_status, Value, Timestamp)` | Stable execution result; preserves the raw terminal value |
| Normalized observation | `Observation(Entity, health, Value, Timestamp)` | Stable health result; no OTel-specific type crosses the boundary |
| Normalized observation | `duration`, `latency`, `error_rate` | Milliseconds or numeric telemetry values |
| BDI percept | `status(Entity, success)` | Normalized execution `success` or runtime `healthy` |
| BDI percept | `status(Entity, fail)` | Any non-success execution conclusion or non-healthy runtime health; this is the canonical BDI failure value, not raw `failure` |
| BDI percept | `duration(Entity, Milliseconds)` | Normalized execution duration |
| BDI percept | `metric(Entity, latency, Value)` / `metric(Entity, error_rate, Value)` | Normalized telemetry metrics |
| Derived BDI belief | `phase_result(Entity, success/fail)` | Attempt result used for dependency and goal reasoning |
| Derived BDI belief | `duration_ok/3`, `duration_violation/3` | Maintenance evaluation |
| Derived BDI belief | `avoidance_violation/1`, `terminal/2` | Avoidance and terminal-state evaluation |

Thus `failure` is an external/normalized raw status, while `fail` is the
canonical BDI percept and derived phase value. `status` is a BDI predicate;
`execution_status` is an observation property; `phase_result` is an internal
derived result. `duration` is an observation/percept, whereas `latency` and
`error_rate` are telemetry metric properties. `health` is a raw/normalized
runtime property and is mapped to the BDI `status` percept; it is not itself a
phase result.

`cancelled`, `skipped`, and `timeout` are retained in the normalized
observation contract. The current generic adapter maps each non-success value
to BDI `fail`, because dependency progression only distinguishes acceptable
success from unacceptable completion. Attempt-qualified handler terms for the
three statuses remain vocabulary documentation, but the public BDI contract
does not pretend they are distinct progression outcomes.

## Reconciled mismatches and exact fixes

1. Retry policy conflicted: the workflow model said `0`, while BDI and the
   validated deterministic scenarios implement one retry. `03_workflow_model.yaml`
   is now authoritative with `max_retries: 1`; `bdi_agent.asl` already has the
   matching `max_retries(1)`. No second policy value was introduced.
2. The workflow model previously required an external attempt ID, but the
   stable `Observation` record has no attempt field. Attempt identity is
   derived by the controller from `attempt_count/2` and `run_attempt/2`.
   `attempt_id_required` is now `false`.
3. The master-goal assessment previously checked phase results directly. It
   now uses `achievement_satisfied/2`, which requires both a configured
   `achievement/2` fact and its matching successful phase result, and still
   checks maintenance and avoidance explicitly.
4. Recovery had two workflow implementations. The standalone
   `.github/workflows/rollback-production.yml` was removed. The remaining
   `entity-execution.yml` recovery branch is independently dispatchable with
   `entity=rollback_production`; it is not in normal `dependencies(D)`, is
   selected only through `recovery(Entity, Recovery)`, and is executed with
   `run_job(Recovery)`.

## Policy placement decisions

- `max_retries`, future `max_reobservations`, and observation duration/window
  belong in the workflow model's execution/observation policy because they
  govern controller execution and observation handling.
- Telemetry thresholds belong in `02_goal.yaml` when they express desired or
  undesired application state (maintenance/avoidance), then flow through `O`
  and generated BDI goal beliefs. Scrape/poll timing belongs in execution or
  observation policy. No future threshold should be duplicated in Java and
  AgentSpeak.

## Recovery verification

`rollback_production` is an entity in `E`, has no normal dependency entry, and
is the target of `recovery(production, rollback_production)`. The BDI recovery
plan invokes the same external action as normal jobs: `run_job(Recovery)`.
The sole remaining implementation is the rollback branch in
`.github/workflows/entity-execution.yml`; it is therefore independently
executable by dispatching that entity and is not selected by normal traversal.

## Test results

| Test | Result | Evidence |
|---|---|---|
| Java environment/mock adapter checks | PASS | `EnvironmentLayerTest` |
| GitHub executor local HTTP unit check | PASS | `GitHubActionsWorkflowExecutorTest` |
| Deterministic BDI scenarios | PASS | `run_scenarios.ps1`; scenarios 1–6 |
| Application Python unit tests | BLOCKED | Import failed: missing `opentelemetry` package |
| Docker Compose/container tests | BLOCKED | Docker CLI available, engine access denied |
| Parser/model tests | NOT AVAILABLE | No parser/model test suite or generator was found |
| External GitHub Actions experiments | NOT RUN | Explicitly out of Phase 1 scope |

The deterministic scenarios cover healthy progression, retry, permanent
failure/stop, production recovery, maintenance violation, and avoidance
violation. No real GitHub infrastructure or Project 2 was used.

## Unresolved design decisions

- Workflow/goal YAML is still translated manually into `bdi_agent.asl`; a
  generator is not implemented. The source mapping above is the contract for a
  future deterministic generator.
- The adapter deliberately collapses all non-success terminal statuses to BDI
  `fail`. If future policy needs different handling for timeout/cancellation,
  add an explicit normalized policy/derived belief rather than overloading
  `status/2`.
- OpenTelemetry is currently exposed through the application's Prometheus
  endpoint and directly scraped by Java; there is no collector or durable
  backend. This is outside Phase 1 and remains for later validation.

## Files modified in Phase 1

- `03_workflow_model.yaml`
- `bdi_agent.asl`
- removed duplicate `.github/workflows/rollback-production.yml`
- `docs/PHASE_1_FRAMEWORK_CONSISTENCY.md`
