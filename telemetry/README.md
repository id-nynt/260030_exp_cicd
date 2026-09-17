# Telemetry and observation adapter

This layer is independent of the Jason agent and does not create or update BDI beliefs. It converts application telemetry into a stable observation stream that a future Java BDI environment can consume.

## Layers

1. **Raw telemetry**: `/health` JSON and `/metrics` Prometheus text emitted by the instrumented payment service.
2. **Normalized observations**: `telemetry.Observation` JSON Lines emitted by `TelemetryAdapter`.
3. **BDI beliefs**: deliberately not implemented. A later Java/Jason integration can translate the normalized observations into beliefs.

Example normalized output:

```json
{"entity":"production","property":"error_rate","value":0.08,"timestamp":"2026-09-17T10:00:00Z"}
{"entity":"production","property":"latency","value":850.0,"timestamp":"2026-09-17T10:00:00Z"}
{"entity":"production","property":"health","value":"unhealthy","timestamp":"2026-09-17T10:00:00Z"}
```

## Telemetry source and collection

- Health source: `GET /health`.
- Metrics source: `GET /metrics`, backed by the demo application's OpenTelemetry Prometheus exporter.
- Collection mechanism: Java `java.net.http.HttpClient` polling; no OpenTelemetry-specific class crosses the adapter boundary.
- Default request timeout: five seconds.
- Intended update interval: one poll every five seconds when embedded in a controller. The CLI performs one poll so it is easy to test independently.
- Staleness threshold: fifteen seconds since the last successful poll.

## Normalization

| Raw source | Normalized observation |
|---|---|
| `/health` HTTP 200 with `status=healthy` | `health=healthy` |
| `/health` HTTP 503 | `health=unhealthy` |
| `payment_error_rate` | `error_rate=<number>` |
| `payment_error_count_total / payment_request_count_total` | fallback `error_rate=<number>` |
| `payment_request_latency_ms_milliseconds_sum / _count` for `/pay` | `latency=<average milliseconds>` |
| execution-result input | `execution_status=<status>` and `duration=<milliseconds>` |

Execution observations are accepted separately because CI/CD execution status and duration are workflow facts, not application runtime telemetry:

```powershell
java -cp telemetry/out telemetry.TelemetryAdapter `
  --entity production `
  --health-url http://localhost:8082/health `
  --metrics-url http://localhost:8082/metrics `
  --execution success,420
```

## Unavailable and stale data

- If health cannot be fetched, emit `health=unknown`.
- If metrics cannot be fetched, omit error-rate and latency values; do not convert missing data to zero.
- If at least one source is available, emit `data_status=fresh`.
- If all sources fail before the stale threshold, emit `data_status=unavailable`.
- If all sources fail beyond the stale threshold, emit `data_status=stale`.

This prevents the BDI layer from treating missing telemetry as a healthy zero value.

## Standalone demo

With Docker running and the demo application available:

```powershell
powershell -ExecutionPolicy Bypass -File .\telemetry\demo.ps1
```

The demo compiles the adapter, changes staging through healthy, high-latency, high-error-rate, and unhealthy-health modes, prints normalized observations for each state, and restores staging to healthy. It does not start the BDI agent.
