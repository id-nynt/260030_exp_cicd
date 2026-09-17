We are now entering the VALIDATION AND EXPERIMENTATION stage of this research prototype.

Do not expand the project unnecessarily. Much of the implementation already exists.

Your task from now on is to verify, correct, complete, and experimentally validate the existing framework.

Read before doing anything:

- PROJECT.md
- CURRENT_ARCHITECTURE.md
- IMPLEMENTATION_AUDIT.md
- EXECUTION_TRACE.md
- 01_pipeline.yaml
- 02_goal.yaml
- 03_workflow_model.yaml
- bdi_agent.asl
- relevant Java/Jason code
- GitHub Actions workflows
- telemetry code
- experiment harness

Treat the current audit as evidence of the current implementation, but verify important claims against the actual code.

# RESEARCH OBJECTIVE

We need to demonstrate a generic framework in which a developer describes:

1. a CI/CD workflow;
2. desired goals/constraints;

and the framework derives the workflow information required by a generic BDI controller.

The intended conceptual flow is:

Pipeline configuration

- Goal configuration
  ↓
  Parsing and validation
  ↓
  Workflow model W
  ↓
  Project-specific BDI beliefs/configuration
- Generic BDI reasoning
  ↓
  BDI controller
  ↓
  run_job(Entity)
  ↓
  Generic Java execution adapter
  ↓
  CI/CD system
  ↓
  Application/runtime
  ↓
  OpenTelemetry
  ↓
  Normalized observations
  ↓
  BDI beliefs
  ↓
  Reconsideration
  ↓
  continue / rerun / recover / stop

# CORE ABSTRACTION

The independently executable CI/CD entity/job is the atomic execution unit.

The BDI agent must NOT reason over or execute individual implementation steps.

For example:

test:
steps:

- unit tests
- integration tests

is represented to the BDI layer as:

entity(test)

and executed through:

run_job(test)

The CI/CD implementation owns the internal steps.

# RESPONSIBILITY BOUNDARIES

## Pipeline / CI/CD

Responsible for:

- executable jobs/entities;
- implementation steps/scripts;
- deployment;
- process/job timeout;
- actual execution result.

## Workflow model

Represents project-specific workflow structure.

Use the existing formal model consistently.

At minimum it must capture:

- E: executable entities;
- D: normal dependencies;
- O: observable properties;
- R: recovery relationships, if R remains part of the finalized formal model.

Do not silently change the formal model. If the current files disagree about W, report the disagreement first.

## Goal model

Represents developer intent.

Current categories are:

- achievement;
- maintenance;
- avoidance.

Goals describe desired/undesired states, not implementation-specific actions.

## Java/Jason environment

Infrastructure only.

Responsibilities:

- expose run_job(Entity);
- execute requested entity through WorkflowExecutor;
- receive normalized observations;
- publish percepts to Jason;
- provide logging/correlation.

It must NOT decide:

- which entity comes next;
- whether to retry;
- which recovery to select;
- whether achievement/maintenance/avoidance goals hold.

Those decisions belong to BDI reasoning/configuration.

## BDI

Responsible for:

- dependency reasoning;
- goal pursuit;
- belief updates;
- reconsideration;
- continuation;
- rerun;
- recovery selection;
- stopping progression.

The external execution interface should remain minimal:

run_job(Entity)

Do not reintroduce separate execution actions such as:

deploy(Entity)
retry_job(Entity)
rollback(Entity)
stop_workflow()
notify()

unless a concrete implementation requirement proves one is necessary. Report that requirement before changing the architecture.

# GENERICITY REQUIREMENT

The framework must work for at least TWO structurally different projects.

The same generic:

- parser/generator architecture;
- Java/Jason environment;
- WorkflowExecutor interface;
- Observation model;
- belief adapter;
- BDI reasoning plans;

must be reused.

Project-specific information may change:

- entity names;
- dependency graph;
- recovery relationships;
- goals;
- thresholds;
- application implementation;
- CI/CD implementation details.

The generic BDI reasoning layer must not require new project-specific plans for Project 2.

This is a primary validation criterion.

# TELEMETRY REQUIREMENT

OpenTelemetry must contribute to BDI reasoning, not merely exist in the application.

Maintain three explicit layers:

RAW TELEMETRY
→ NORMALIZED OBSERVATION
→ BDI BELIEF

Examples:

OpenTelemetry latency
→ Observation(entity, latency, value, timestamp)
→ metric(Entity, latency, Value)

OpenTelemetry error rate
→ Observation(entity, error_rate, value, timestamp)
→ metric(Entity, error_rate, Value)

GitHub execution result
→ Observation(entity, execution_status, value, timestamp)
→ status(Entity, success/fail)

Do not expose Prometheus/OpenTelemetry-specific structures directly to generic BDI reasoning.

At least one experimental scenario must demonstrate:

CI/CD execution reports success
BUT runtime telemetry violates a goal/condition
THEREFORE BDI does not simply accept the deployment as satisfactory.

Prefer testing both:

- high error rate;
- high latency.

# REQUIRED VALIDATION

We must demonstrate:

1. model/configuration consistency;
2. deterministic transformation from source configuration to workflow/BDI configuration;
3. generic BDI reasoning;
4. local/mock reasoning correctness;
5. real GitHub Actions execution;
6. real observation return path;
7. OpenTelemetry-to-BDI path;
8. healthy end-to-end execution;
9. transient failure handling;
10. permanent failure handling;
11. recovery handling;
12. maintenance violation;
13. avoidance violation;
14. telemetry-driven adaptation;
15. operation on Project 1;
16. operation on structurally different Project 2.

# CORE BEHAVIOURAL OUTCOMES

The framework should reason in terms of:

CONTINUE

- current entity acceptable;
- dependencies permit another entity;
- execute next entity.

RERUN

- current execution failed;
- retry policy permits another attempt;
- execute the same entity again.

RECOVER

- failure/goal violation requires configured recovery;
- resolve recovery(Entity, Recovery);
- execute Recovery through run_job(Recovery).

STOP

- progression must not continue;
- BDI stops initiating normal entities.

These are reasoning outcomes, not necessarily separate external APIs.

# EXPERIMENTAL EVIDENCE

Every experiment should record enough evidence to reconstruct:

- experiment ID;
- project;
- scenario;
- initial configuration;
- entity selected;
- run_job calls;
- execution IDs;
- attempt number;
- execution result;
- telemetry observations;
- BDI percepts;
- relevant belief changes;
- selected BDI plan/decision;
- retry/recovery action;
- final workflow state;
- achievement satisfaction;
- maintenance satisfaction;
- avoidance violation;
- total execution duration;
- decision/observation timing where available.

# SUCCESS CRITERION

Do NOT define success merely as "the application deployed."

The framework is considered successfully validated when:

For at least two structurally different CI/CD projects, project-specific workflow and goal information can be deterministically represented/generated, the same generic BDI reasoning layer can execute them through the generic run_job(Entity) interface, execution and OpenTelemetry observations return to the BDI layer, and predefined healthy/failure/runtime scenarios produce the expected continue, rerun, recover, or stop behaviour.

# WORKING METHOD

From now on work phase-by-phase.

For EVERY phase:

1. inspect current implementation;
2. compare it against the phase requirements;
3. identify mismatches;
4. run existing relevant tests before modifying code;
5. make the MINIMUM changes necessary;
6. add/update tests for the change;
7. rerun tests;
8. produce a concise phase report containing:
   - inspected;
   - already correct;
   - changed;
   - tests executed;
   - tests passed/failed;
   - unresolved issues;
   - files modified.

Do not silently redesign architecture.

Do not implement future phases while completing the current phase.

Do not create alternative duplicate implementations when an existing implementation can be corrected.

Do not report something as working unless it has actually been tested.

Clearly distinguish:

IMPLEMENTED
TESTED
NOT TESTED
PARTIAL
MISSING

If external credentials, Docker, GitHub, networking, or infrastructure prevent a test, report BLOCKED rather than claiming success.

Preserve evidence from each validation run for the research evaluation.
