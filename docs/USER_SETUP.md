# User setup

This file lists prerequisites that cannot be completed by the repository alone.
Do not commit tokens or private runner registration values.

## CODEX can implement

- deterministic configuration validation and generation;
- Java/Jason controller and GitHub dispatch adapter;
- telemetry and BDI terminal monitors;
- workflow changes for an agreed self-hosted runner label;
- container cleanup/restart behavior for persistent staging/production;
- final real-run evidence checks.

## USER must configure

1. Choose a persistent host.

   Recommended first option: a Linux research machine or dedicated VM that
   runs Docker and a GitHub Actions self-hosted runner. The host must remain
   powered on for the experiment.

2. Install prerequisites on that host.

   - Docker Engine or Docker Desktop with Linux containers;
   - GitHub Actions runner;
   - network access to GitHub;
   - ports 8081 and 8082 available for staging and production;
   - enough disk space for the application images and artifacts.

3. Add the runner to the GitHub repository.

   In GitHub:

   ```text
   Repository Settings -> Actions -> Runners -> New self-hosted runner
   ```

   Select Linux/x64 unless the host uses another supported platform. Follow
   GitHub's generated registration commands on the host. Add the custom label:

   ```text
   bdi-demo
   ```

   Confirm the runner appears as **Idle** and **Online**. Runner registration
   tokens are temporary and must not be committed.

4. Select the deployment workflow runner.

   The current workflow uses `runs-on: ubuntu-latest`, which is ephemeral.
   Before a real run, the deployment workflow must target the persistent
   runner label:

   ```yaml
   runs-on: [self-hosted, bdi-demo]
   ```

   The simplest compatible choice for the current atomic
   `run_job(Entity)` design is to use this label for
   `.github/workflows/entity-execution.yml`, because each dispatch executes
   exactly one entity. Build/test/security then also run on the persistent
   runner, but the workflow remains structurally unchanged. A later
   optimization can split deployment jobs from build/test jobs after the first
   demonstration.

5. Make the persistent host reachable.

   If the runner is on the research machine, use:

   ```text
   http://localhost:8081/health
   http://localhost:8081/metrics
   http://localhost:8082/health
   http://localhost:8082/metrics
   ```

   If it is on a VM, allow inbound TCP 8081 and 8082 only from the research
   machine and use the VM address instead. Verify these URLs from the machine
   running Java/Jason.

6. Configure GitHub token permissions.

   Create a short-lived fine-grained token for the repository with the minimum
   Actions permissions required to dispatch workflows and read workflow runs
   and artifacts. Store it only in the current PowerShell process:

   ```powershell
   $env:GITHUB_TOKEN = '<token value; do not commit>'
   ```

7. Configure the local controller.

   ```powershell
   $env:GITHUB_REPOSITORY = 'OWNER/REPOSITORY'
   $env:GITHUB_REF = 'main'
   $env:STAGING_HEALTH_URL = 'http://<persistent-host>:8081/health'
   $env:STAGING_METRICS_URL = 'http://<persistent-host>:8081/metrics'
   $env:PRODUCTION_HEALTH_URL = 'http://<persistent-host>:8082/health'
   $env:PRODUCTION_METRICS_URL = 'http://<persistent-host>:8082/metrics'
   $env:BDI_DEPLOYMENT_MODE = 'runner'
   $env:BDI_DEPLOYMENT_HOST = '<persistent-host>'
   $env:BDI_DEPLOYMENT_SSH_USER = '<ssh user>' # required when host is remote
   $env:BDI_EXPERIMENT_ID = 'healthy-001'
   $env:BDI_RELEASE_ID = 'candidate-001'
   $env:BDI_LOG_FILE = 'java-jason/runtime-artifacts/healthy-001.jsonl'
   $env:BDI_PERSISTENT_DEPLOYMENT_CONFIRMED = '1'
   ```

8. Verify the target before starting BDI.

   ```powershell
   Invoke-RestMethod $env:STAGING_HEALTH_URL
   Invoke-RestMethod $env:PRODUCTION_HEALTH_URL
   Invoke-WebRequest $env:STAGING_METRICS_URL
   Invoke-WebRequest $env:PRODUCTION_METRICS_URL
   ```

   The health responses must report `healthy`, and the metrics URLs must
   return Prometheus-format content.

9. Confirm the workflow file is on the selected branch.

   ```text
   .github/workflows/entity-execution.yml
   ```

   The Java adapter dispatches this workflow by filename and branch. The
   workflow must be present on GitHub before starting the controller.

10. Configure failure injection access.

    Set `BDI_DEPLOYMENT_MODE=runner` and point `BDI_DEPLOYMENT_HOST` at the
    same persistent host used by the GitHub runner. For a remote Linux VM,
    configure SSH authentication and set `BDI_DEPLOYMENT_SSH_USER`. The
    injector then changes the actual `payment-production` or
    `payment-staging` container on that host rather than an unrelated local
    Compose service.

11. Confirm persistent container behavior.

    After a staging or production entity job completes, run on the deployment
    host:

    ```bash
    docker ps
    curl http://localhost:8081/health
    curl http://localhost:8082/health
    ```

    The containers must still be running after the GitHub job is marked
    complete. If a later deployment fails because a container name already
    exists, the workflow needs an explicit stop/remove-or-replace step before
    starting the replacement. That is a workflow correction, not a BDI
    controller change.

## Important security note

A self-hosted runner executes repository workflow code with access to its host.
Use a dedicated VM or disposable research machine, do not use a personal
workstation containing sensitive files, and restrict repository write access.

## Current blocker

The current workspace has no configured GitHub token, repository, telemetry
URLs, or persistent runner confirmation. Docker is installed, but the current
tool process cannot access the Docker engine. Real deployment testing cannot
be honestly completed until the user performs the setup above.
