# Phase 3 — Generic BDI Validation Using Mock Execution

Date: 2026-09-17

Scope: generated Project 1 configuration plus deterministic in-memory Jason
execution. No GitHub Actions, Docker deployment, or external infrastructure
was used.

## Harness and automatic assertions

The scenarios use the generated `bdi_agent.asl` from Phase 2, the generic
reasoning source `bdi_generic.asl`, `ScenarioEnvironment`, and
`ScenarioWorkflowExecutor`. The runner is:

```text
java-jason/run_scenarios.ps1
```

It automatically asserts for every scenario:

- exact `run_job` sequence;
- retry count;
- recovery selection;
- forbidden downstream/recovery actions;
- final workflow state;
- master-goal result;
- required normalized belief changes;
- maintenance and avoidance outcomes.

Machine-readable evidence is written to:

- `java-jason/scenario-artifacts/scenario1.json` through `scenario8.json`;
- `java-jason/scenario-artifacts/phase3-summary.json`.

All eight scenarios passed.

## Scenario definitions and results

| Scenario | Initial state | Input observations/outcomes | Expected → actual `run_job` sequence | Expected → actual final state | Retry | Recovery | Master goal |
|---|---|---|---|---|---:|---|---|
| 1 Healthy | `workflow_active` | all entities success; duration 42 ms | `build, test, security, staging, production` → identical | `completed_success` → identical | 0 → 0 | none → none | true → true |
| 2 Transient intermediate failure | `workflow_active` | test failure, then success; other entities success | `build, test, test, security, staging, production` → identical | `completed_success` → identical | 1 → 1 | none → none | true → true |
| 3 Permanent intermediate failure | `workflow_active` | test failure twice | `build, test, test` → identical | `stopped` → identical | 1 → 1 | none → none | false → false |
| 4 Final deployment retry succeeds | `workflow_active` | production failure, then success | `build, test, security, staging, production, production` → identical | `completed_success` → identical | 1 → 1 | none → none | true → true |
| 5 Final failure with successful recovery | `workflow_active` | production failure twice; rollback success | `build, test, security, staging, production, production, rollback_production` → identical | `recovered_stopped` → identical | 1 → 1 | rollback selected → identical | false → false |
| 6 Final failure with failed recovery | `workflow_active` | production failure twice; rollback failure | `build, test, security, staging, production, production, rollback_production` → identical | `recovery_failed` → identical | 1 → 1 | rollback selected → identical | false → false |
| 7 Maintenance violation | `workflow_stopped`, `running(production)`, `run_attempt(production,1)` | production success, duration 100001 ms; rollback success | `rollback_production` → identical | `recovered_stopped` → identical | 0 → 0 | rollback selected → identical | false → false |
| 8 Avoidance violation | `workflow_stopped`, `running(production)`, `run_attempt(production,1)` | production success while required predecessors are absent; rollback success | `rollback_production` → identical | `recovered_stopped` → identical | 0 → 0 | rollback selected → identical | false → false |

For scenarios 3, 7, and 8 the runner also asserted that forbidden entities
did not execute:

- scenario 3: `security`, `staging`, and `production` were never called after
  the permanent test failure;
- scenarios 7–8: no normal entity was initiated from the pre-initialized goal
  violation state.

## Belief-change evidence

The runner asserted the following normalized belief changes from the captured
percepts:

| Scenario | Required belief evidence |
|---|---|
| 1 | `status(build,success)`, `status(production,success)`, `duration(production,42)` |
| 2 | `status(test,fail)`, then `status(test,success)` |
| 3 | `status(test,fail)` |
| 4 | `status(production,fail)`, then `status(production,success)` |
| 5 | `status(production,fail)`, `status(rollback_production,success)` |
| 6 | `status(production,fail)`, `status(rollback_production,fail)` |
| 7 | `status(production,success)`, `duration(production,100001)`, `status(rollback_production,success)` |
| 8 | `status(production,success)`, `status(rollback_production,success)` |

The internal `phase_result/2`, `terminal/2`, `workflow_stopped`, and
`master_goal_achieved` transitions are reflected by the selected plans and
final-state assertions; the JSON artifact retains the complete captured
belief/percept lines.

## Fixes required by the mock validation

Two retry-attempt translation issues were demonstrated by the permanent and
failed-recovery scenarios:

1. The generic recovery plan now explicitly requires
   `not retry_allowed(Entity)`, so recovery cannot compete with a still-valid
   retry plan.
2. The generic attempt bridge accepts a fresh attempt duration together with
   the canonical `status(Entity, fail)` belief, allowing a repeated identical
   failure to produce a new attempt-qualified failure result.
3. `ObservationEnvironment` clears an entity’s execution-status and duration
   percept state at the start of `run_job(Entity)` and removes the exact prior
   percept before replacement. This ensures a repeated normalized value still
   creates a Jason reconsideration event for the new attempt.

These are generic execution/observation-boundary corrections. No project
entity name or project-specific plan was added to generic reasoning.

## Test status

| Test | Result |
|---|---|
| Eight deterministic BDI scenarios | PASS |
| Machine-readable per-scenario assertions | PASS |
| Generated Project 1 configuration used | PASS |
| Real GitHub Actions | NOT RUN by instruction |
| Docker/application experiments | NOT RUN |
| Project 2 | NOT RUN; later phase |

## Files changed

- `java-jason/src/main/java/harness/ScenarioEnvironment.java` — eight
  deterministic scenario definitions.
- `java-jason/run_scenarios.ps1` — complete machine-readable assertions and
  summary output.
- `java-jason/src/main/java/harness/ObservationEnvironment.java` — generic
  repeated-attempt percept reset.
- `bdi_generic.asl` — generic retry/recovery/observation corrections.
- generated `bdi_agent.asl` and scenario JSON artifacts.
- `docs/PHASE_3_BDI_VALIDATION.md` — this report.

Phase 3 is complete. No real execution or Project 2 work was started.
