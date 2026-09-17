# Final demonstration results

Date: 2026-09-17

## Status

| Capability | Implemented | Actually tested | How I reproduce it |
|---|---:|---:|---|
| Pipeline/goal validation | Yes | Yes | `py tools\\test_model_transform.py` |
| Workflow model generation | Yes | Yes | `py tools\\model_transform.py` |
| Project BDI generation | Yes | Yes | `py tools\\model_transform.py` |
| Generic BDI reasoning | Yes | Yes, mock | `.\\run-demo.ps1 -Mode mock` |
| Visible telemetry monitor | Yes | Script added; live endpoints not tested | `.\\run-demo.ps1 -Mode real` after setup |
| Visible BDI monitor | Yes | Script added; real stream not tested | `.\\run-demo.ps1 -Mode real` after setup |
| GitHub entity dispatch | Yes | Unit/mock HTTP only | Real run required |
| Persistent staging deployment | Workflow commands exist | **No — BLOCKED** | Requires configured self-hosted runner or persistent VM |
| Persistent production deployment | Workflow commands exist | **No — BLOCKED** | Requires configured self-hosted runner or persistent VM |
| Browser-reachable deployment | Local Compose only | Not as GitHub deployment | Verify after persistent setup |
| GitHub execution status/duration | Adapter implemented | Unit test only | Real GitHub run required |
| Runtime telemetry to BDI | Adapter implemented | Mock/unit path only | Real persistent endpoints required |
| Unhealthy production recovery | Generic rule implemented | Deterministic mock recovery only | Real persistent failure + rollback required |
| Error-rate threshold recovery | Not implemented | No | Must be added after unhealthy path |
| Latency threshold recovery | Not implemented | No | Must be added after unhealthy path |
| Machine-readable logs | Yes | Mock logs tested | Real JSONL required |

## Tests completed in this pass

- `py tools/model_transform.py`: PASS.
- `py tools/test_model_transform.py`: 9 tests PASS.
- `java-jason/run_scenarios.ps1`: 8/8 PASS.
- Docker client is installed, but Docker engine access from this process failed
  with access denied.
- No real GitHub Actions workflow was dispatched.
- No real persistent deployment was executed.
- No real telemetry-to-BDI recovery was executed.

## Blocking point

The test order stopped before persistent deployment because the required
external setup is unavailable:

- no GitHub token configured;
- no repository/ref configured;
- no persistent staging/production host configured;
- no telemetry endpoint configured;
- no confirmed self-hosted runner;
- Docker engine inaccessible from the current process.

The final real experiment is therefore **BLOCKED**, not complete.

## Next action

Follow [USER_SETUP.md](USER_SETUP.md), configure the persistent runner and
endpoints, then execute [FINAL_DEMO_GUIDE.md](FINAL_DEMO_GUIDE.md) from STEP 3.
Only after STEP 6 produces a real GitHub rollback and persistent production
health restoration should the unhealthy demonstration be marked complete.

