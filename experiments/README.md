# Reproducible experiment harness

The harness is configuration-driven. Scenario definitions are in
`scenarios.json`; the runner does not contain scenario-specific BDI rules.

## One command

From the repository root, configure the GitHub runtime values once:

```powershell
$env:GITHUB_TOKEN = '<runtime token>'
$env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
$env:GITHUB_REF = 'main'
powershell -ExecutionPolicy Bypass -File .\experiments\run_experiments.ps1
```

The token is read only from the process environment. It is not written to the
scenario files or result artifacts.

Run one scenario while developing the harness:

```powershell
powershell -ExecutionPolicy Bypass -File .\experiments\run_experiments.ps1 `
  -OnlyScenario healthy_pipeline
```

## What each run does

For every scenario the runner:

1. generates a unique experiment ID;
2. resets local staging and production containers with Docker Compose;
3. applies the scenario's local failure injection;
4. creates a per-entity/per-attempt GitHub input plan;
5. starts traffic for latency/error-rate experiments;
6. starts the unchanged BDI agent with `GitHubEnvironment`;
7. waits for a terminal BDI state or the configured timeout;
8. stops traffic and containers;
9. saves raw controller logs, structured transition logs, the execution plan, and
   `result.json`;
10. asserts the configured action sequence and expected terminal behaviour.

Results are written under:

```text
experiments/results/<experiment-id>/
  execution-plan.properties
  controller.stdout.log
  controller.stderr.log
  runtime.jsonl
  result.json
```

`result.json` contains the experiment ID, scenario, entity executions, execution
start/end times, GitHub run IDs, normalized observations, percept/belief changes,
BDI decisions, retry count, recovery actions, final workflow state, goal
satisfaction, and total pipeline duration.

The local Docker Compose services provide persistent endpoints for the telemetry
adapter. GitHub-hosted runners remain responsible for the actual workflow entity
execution and their own deployment checks. This preserves the existing adapter
boundary while avoiding inaccessible runner-local application ports.

The runner intentionally does not alter `bdi_agent.asl` or add BDI decision
rules. Failure injection is passed as GitHub workflow inputs and local service
environment variables.
