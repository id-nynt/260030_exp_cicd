# GitHub Actions entity contract

The workflows expose one atomic pipeline entity per job. The BDI layer is not implemented here and no individual GitHub Actions step is an entity.

## `build`

- Trigger: push to `main`, or manual `workflow_dispatch`.
- Dependencies: none.
- Inputs: repository source, optional `service_version` workflow input.
- Outputs: Docker image artifact named `payment-image` containing `payment-service-image.tar`.
- Terminal results: success, failure, timeout, cancelled.
- Relevant telemetry: image build duration, image metadata, workflow/job status.

## `test`

- Trigger: automatically after successful `build`.
- Dependencies: `build`.
- Inputs: `payment-image` artifact.
- Outputs: automated test result and workflow/job status.
- Terminal results: success, failure, timeout, cancelled, skipped.
- Relevant telemetry: test duration, test output, workflow/job status.

## `security`

- Trigger: automatically after successful `test`.
- Dependencies: `test`.
- Inputs: `payment-image` artifact and source files.
- Outputs: dependency consistency result, non-root image result, secret-scan result.
- Terminal results: success, failure, timeout, cancelled, skipped.
- Relevant telemetry: check duration, check results, workflow/job status.

## `staging`

- Trigger: automatically after successful `security`.
- Dependencies: `security`.
- Inputs: `payment-image` artifact, service version, staging environment configuration.
- Outputs: staging container, health-check result, request/metrics smoke-check result, staging logs.
- Terminal results: success, failure, timeout, cancelled, skipped.
- Relevant telemetry: `/health` status, request count, error count, error rate, latency metrics, container logs.

## `production`

- Trigger: automatically after successful `staging`.
- Dependencies: `staging`.
- Inputs: `payment-image` artifact, service version, production environment configuration.
- Outputs: production container, health-check result, request/metrics smoke-check result, production logs.
- Terminal results: success, failure, timeout, cancelled, skipped.
- Relevant telemetry: `/health` status, request count, error count, error rate, latency metrics, container logs.

## `rollback_production`

- Trigger: manual `workflow_dispatch` only.
- Dependencies: none in the normal workflow; it is not a successor of `production`.
- Inputs: `source_run_id` identifying a CI/CD run whose `payment-image` artifact should be restored.
- Outputs: rollback production container, rollback health-check result, rollback logs.
- Terminal results: success, failure, timeout, cancelled.
- Relevant telemetry: rollback duration, `/health` status, request metrics, container logs, source run ID.

## Execution limits

Every job has a ten-minute GitHub Actions timeout. Health checks allow up to thirty one-second attempts before failing. The workflow jobs are intentionally coarse-grained: ordinary Docker, test, deployment, and verification commands remain implementation steps within an entity.
