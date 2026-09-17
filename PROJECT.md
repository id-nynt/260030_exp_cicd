We are implementing a research prototype for an adaptive CI/CD framework controlled by a BDI agent.

The purpose is to validate the framework experimentally, not to build a production DevOps platform.

## Core architecture

The prototype contains:

1. A small demo payment service application.
2. A GitHub Actions CI/CD pipeline.
3. OpenTelemetry instrumentation for runtime telemetry.
4. A telemetry/observation adapter.
5. A Java runtime hosting a Jason BDI agent.
6. A controller/bridge allowing the BDI agent to initiate CI/CD jobs.
7. Pipeline, goal, and workflow-model configuration files.

The conceptual execution cycle is:

workflow entity
→ execute complete CI/CD job
→ receive observations
→ update BDI beliefs
→ BDI evaluates goals/current state
→ continue, rerun, recover, or stop
→ execute the selected complete job

## Critical abstraction boundary

A CI/CD job/entity is the atomic executable unit.

The BDI agent MUST NOT execute or reason over individual YAML steps.

For example:

test:
steps:

- unit tests
- integration tests
- performance tests

is represented to BDI only as entity(test).

The BDI agent executes it through:

run_job(test)

The underlying CI/CD system executes all implementation-specific steps.

## External BDI execution capability

Keep the external execution interface minimal.

The primary external action is:

run_job(Entity)

Do NOT create separate external capabilities such as:

deploy(Entity)
retry_job(Entity)
rollback(Entity)

Instead:

- continue → run_job(next entity)
- rerun → run_job(current entity)
- recovery → resolve recovery(Entity, Recovery), then run_job(Recovery)
- stop → BDI stops initiating further entities

## Recovery

Recovery operations must be independently executable workflow entities.

Example:

entity(production).
entity(rollback_production).
recovery(production, rollback_production).

rollback_production is NOT part of normal dependency progression.

## Responsibility boundaries

GitHub Actions / CI/CD runtime owns:

- executing jobs
- executing scripts
- job timeout
- process termination
- reporting job result

OpenTelemetry owns:

- application/runtime telemetry collection

Java environment/adapter owns:

- communication with external systems
- converting observations into BDI percepts
- implementing run_job(Entity)

BDI owns:

- beliefs
- goals
- plans
- dependency reasoning
- continue/rerun/recovery/stop decisions

## Configuration/model layers

Pipeline YAML:

- executable jobs
- job dependencies
- scripts/steps

Goal YAML:

- achievement goals
- maintenance goals
- avoidance goals

Workflow model:
W = (E, D, O, R)

where:

- E = executable entities
- D = normal dependencies
- O = observable properties
- R = recovery relationships

BDI:

- generated/static workflow beliefs
- generated goal beliefs
- generic reasoning plans
- runtime beliefs

## Important constraints

Do not redesign these abstractions without explicitly explaining the problem first.

Do not decompose jobs into individual BDI actions.

Do not hard-code build/test/staging/production into generic controller logic.

Do not generate hundreds of scenario-specific BDI plans.

Prefer parameterized generic plans using Entity variables.

Before implementing a component:

1. state its responsibility;
2. state its inputs;
3. state its outputs;
4. state which other component it communicates with;
5. state how we can test it independently.

Keep the prototype minimal and experimentally observable.
