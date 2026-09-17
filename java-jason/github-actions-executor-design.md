# GitHub Actions WorkflowExecutor design

## Responsibility and boundary

`GitHubActionsWorkflowExecutor` is the adapter between the generic Java interface

```text
run_job(Entity)
```

and GitHub Actions. It maps an entity to one manually dispatched workflow run,
waits for that run to reach a terminal state, and publishes normalized execution
observations. The Jason agent sees only the existing `run_job(Entity)` action and
the existing generic observations.

The adapter owns GitHub API calls, authentication headers, dispatch correlation,
polling, timeout conversion, and execution logging. It does not select the next
entity, retry, infer dependencies, or select recovery.

## Relevant GitHub constraints

1. `workflow_dispatch` must be declared by the target workflow, and the workflow
   file must be present on the repository's default branch before it can be
   dispatched.
2. The dispatch ref identifies the workflow revision. The adapter therefore sends
   an explicit configured branch or tag.
3. A dispatch payload can contain workflow inputs. The dedicated entity workflow
   receives `entity`, `execution_id`, and, for rollback, `source_run_id`.
4. The current REST API can return the created workflow run when
   `return_run_details=true`; older behaviour returned HTTP 204 with no run ID.
   The adapter requires the run-details response. This avoids guessing which run
   belongs to a dispatch when several runs are concurrent.
5. A run has a lifecycle `status` such as `queued`, `in_progress`, or
   `completed`, plus a terminal `conclusion` such as `success`, `failure`,
   `cancelled`, or `timed_out`. The adapter polls the run identified by the
   returned ID, never the newest run globally.
6. GitHub tokens are supplied at runtime through environment/secret configuration;
   they are never stored in source files or workflow inputs.

References:

- [Create a workflow dispatch event](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
- [Workflow dispatch inputs](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatchinputs)
- [List/get workflow runs](https://docs.github.com/en/rest/actions/workflow-runs)

## Viable approaches

### 1. Dispatch and find the newest run

POST a dispatch, then list recent runs and choose the newest matching workflow,
branch, and timestamp.

This works with older GitHub API behaviour, but correlation is inherently racy:
another dispatch can occur between the POST and the list request, and timestamps
are not a durable execution key.

### 2. Dispatch with `return_run_details=true`, then poll the returned run

POST once, receive the GitHub `workflow_run_id`, and GET that exact run until it
terminates.

This is the recommended research-prototype approach. It is small, deterministic,
and naturally handles concurrent runs and stale historical runs.

### 3. Webhook-first execution

Dispatch the workflow and receive completion through a GitHub webhook server.

This avoids polling but requires a publicly reachable endpoint, webhook secret
verification, event persistence, retry handling, and lifecycle management. It is
unnecessarily large for the experiment's first real adapter.

### 4. GitHub CLI subprocess

Run `gh workflow run` and `gh run watch` from Java.

This is convenient for a developer workstation but adds a process/runtime
dependency, CLI login state, and weaker control over correlation and error
parsing.

## Selected design

Use approach 2:

```text
run_job(test)
  -> POST entity-execution.yml/dispatches
       {ref, return_run_details:true,
        inputs:{entity:test, execution_id:<uuid>}}
  <- {workflow_run_id:<github-id>}
  -> GET actions/runs/<github-id> until completed
  -> Observation(test, execution_status, success/failure/...)
  -> Observation(test, duration, milliseconds)
```

The UUID is included in the workflow run name and logs for human correlation;
the GitHub numeric run ID is the authoritative correlation key. Every in-flight
execution is represented by its own local record keyed by that run ID. The
adapter never substitutes a later run for a timed-out or completed run.

`rollback_production` receives the most recent successful `build` run ID recorded
by this adapter as `source_run_id`. This keeps rollback independently executable
while avoiding a new BDI argument or GitHub-specific belief. If no successful
build is known, the adapter rejects the request before dispatching it.

The workflow is one atomic GitHub job named `execute_entity`. Its ordinary shell
and Docker steps are implementation details. A requested entity is selected by a
validated workflow input; no other entity job is dispatched. Build work needed to
construct an image for staging or production is infrastructure inside that one
entity execution, not a separate BDI action.

## Trade-offs

- Polling is less immediate than webhooks, but requires no inbound service and is
  straightforward to test with a local HTTP server.
- `return_run_details=true` depends on the current GitHub REST API. If an older
  GitHub installation does not support it, a later compatibility mode can use
  unique `execution_id` matching in `run-name`; that mode is intentionally not
  enabled silently because ambiguous correlation is unsafe.
- `run_job` remains synchronous at the Java action boundary while the adapter
  polls. This keeps the current BDI semantics simple: the next plan is selected
  after the requested entity has a terminal observation.
- The single entity workflow duplicates some ordinary CI shell logic. That is
  acceptable for this minimal experiment and preserves the atomic entity
  abstraction; reusable workflows can remove duplication later.

## Independent testing

The adapter uses Java's standard HTTP client and accepts a configurable API base
URI. Tests can point it at a local `HttpServer` that returns deterministic
dispatch and run-status JSON. No GitHub account, token, or network access is
required for those tests.
