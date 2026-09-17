# Phase 2 — Configuration-to-BDI Transformation

Date: 2026-09-17

Scope: deterministic transformation of the supported Project 1 YAML subset.
Project 2, live GitHub Actions, and real deployment experiments were not run.

## Result

Implemented a strict, deterministic Python transformer:

```text
01_pipeline.yaml + 02_goal.yaml
        ↓
tools/model_transform.py
        ↓
03_workflow_model.yaml + bdi_project.asl
        ↓
bdi_agent.asl = generated bdi_project.asl beliefs + bdi_generic.asl
```

`bdi_generic.asl` contains the generic reasoning/controller plans and contains
no Project 1 entity literals. `bdi_project.asl` contains generated project
facts. `bdi_agent.asl` is the Jason runtime artifact generated from those two
inputs; it is not the source of project configuration.

## Separation of concerns

Generated project data includes:

- `entity/1`, `depends/2`, `recovery/2`, `recovery_entity/1`;
- derived `final_phase/1`;
- `achievement/2`, `max_duration/2`, `avoid_missing/2`;
- `duration_unit/1`, `max_retries/1`, and initial `attempt_count/2`.

Generic reasoning remains in `bdi_generic.asl`: dependency holding and next
entity selection, master-goal control, execution, observation handling,
success/failure/retry, recovery, maintenance, avoidance, and final assessment.
The only generic change required by translation was excluding
`recovery_entity/1` from normal `nextentity/1` traversal.

## Parser and validator

The parser uses PyYAML only as a syntax reader; all supported semantics and
validation are explicit Python code. It rejects:

- unknown top-level/job/goal keys;
- unknown dependencies and recovery targets;
- cyclic normal dependencies;
- malformed comparisons;
- unknown goal entities;
- unsupported observable properties or status values;
- unsupported achievement, maintenance, or avoidance forms;
- invalid retry policy values;
- ambiguous recovery conditions.

Recovery jobs are recognized only when their `if` expression contains exactly
one failure condition of the supported form
`needs.<entity>.result == 'failure'`, and that entity is their sole `needs`
target. Recovery jobs are excluded from normal `dependencies(D)`.

## Complete source-to-BDI traces

The following traces use the current Project 1 files. Line numbers refer to
the source files as generated/validated in this phase.

### Entity

```text
01_pipeline.yaml:11  build:
  → parsed entity = build
  → 03_workflow_model.yaml: workflow.entities(E) contains build
  → bdi_project.asl: entity(build).
```

### Dependency

```text
01_pipeline.yaml:24  test:
01_pipeline.yaml:25    needs: build
  → parsed dependency = (build, test)
  → 03_workflow_model.yaml: dependencies(D): from build, to test
  → bdi_project.asl: depends(test, [build]).
```

### Achievement

```text
02_goal.yaml:3  - production.status == success
  → parsed Achievement(production, status, ==, success)
  → workflow observation vocabulary includes status=success
  → bdi_project.asl: achievement(production, success).
```

### Maintenance

```text
02_goal.yaml:7  - production.duration <= 100000
  → parsed Maintenance(production, duration, <=, 100000)
  → 03_workflow_model.yaml: duration observable, milliseconds unit,
    required_for=[production]
  → bdi_project.asl: max_duration(production, 100000).
```

### Avoidance

```text
02_goal.yaml:12-13
  condition: production.status == success
  when: test.status != success
  → parsed Avoidance(production, test)
  → workflow status observation validates both entity references
  → bdi_project.asl: avoid_missing(production, test).
```

### Recovery

```text
01_pipeline.yaml:87  rollback_production:
01_pipeline.yaml:88    needs: production
01_pipeline.yaml:90    if: ... needs.production.result == 'failure'
  → parsed recovery = (production, rollback_production)
  → 03_workflow_model.yaml: recovery(R): from production, to rollback_production
  → bdi_project.asl:
       entity(rollback_production).
       recovery_entity(rollback_production).
       recovery(production, rollback_production).
```

## Determinism

The generator preserves source declaration order for entities, dependencies,
goals, and recovery relationships, and emits fixed observable/policy fields.
Running the same inputs twice produced byte-equivalent workflow-model and
belief outputs in the deterministic test.

## Tests

| Test | Result | Evidence |
|---|---|---|
| Valid pipeline | PASS | `test_valid_pipeline` |
| Unknown dependency | PASS | `test_unknown_dependency` |
| Cyclic dependency | PASS | `test_cyclic_dependency` |
| Unknown goal entity | PASS | `test_unknown_goal_entity` |
| Unknown observable | PASS | `test_unknown_observable` |
| Malformed comparison | PASS | `test_malformed_comparison` |
| Recovery target validation | PASS | `test_recovery_target_validation` |
| Retry policy translation | PASS | `test_retry_policy_and_goal_translation` |
| Achievement/maintenance/avoidance translation | PASS | same translation test and generated beliefs |
| Deterministic output | PASS | `test_deterministic_output` |
| Phase 1 Java unit checks | PASS | `EnvironmentLayerTest`, `GitHubActionsWorkflowExecutorTest` |
| Phase 1 deterministic Jason scenarios | PASS | `run_scenarios.ps1`, scenarios 1–6 |

Python application tests, Docker/container tests, and live external execution
remain as reported in Phase 1 and were not expanded in this phase.

## Files changed

- `01_pipeline.yaml` — made retry policy a source configuration value.
- `02_goal.yaml` — corrected avoidance entries to valid YAML mappings.
- `03_workflow_model.yaml` — regenerated output.
- `tools/model_transform.py` — parser, validator, and generators.
- `tools/test_model_transform.py` — transformation tests.
- `tools/requirements.txt` — transformer dependency.
- `bdi_generic.asl` — generic reasoning source.
- `bdi_project.asl` — generated project beliefs.
- `bdi_agent.asl` — generated Jason runtime composition.
- `docs/PHASE_2_MODEL_TRANSFORMATION.md` — this report.

## Unresolved decisions

- The supported YAML subset is intentionally strict and currently requires
  achievement status goals, duration upper-bound maintenance, and predecessor
  status avoidance. Broader goal syntax should be added only with explicit
  normalized BDI semantics and tests.
- PyYAML is a build-time parser dependency; package installation was not
  attempted during this phase because it was already available locally.
- A future structurally different Project 2 must use the same transformer and
  generic AgentSpeak file; that cross-project validation is a later phase.
