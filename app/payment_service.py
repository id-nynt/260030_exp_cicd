"""Minimal instrumented payment service for the CI/CD experiment."""

from __future__ import annotations

import os
import threading
import time
from typing import Any

from flask import Flask, Response, jsonify, render_template_string, request
from opentelemetry import metrics, trace
from opentelemetry.metrics import Observation
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.sdk.resources import DEPLOYMENT_ENVIRONMENT, SERVICE_NAME, SERVICE_VERSION, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest


UI = """
<!doctype html>
<title>Payment service</title>
<h1>Payment service</h1>
<p>Version: <code>{{ version }}</code> | Environment: <code>{{ environment }}</code></p>
<ul>
  <li><a href="/health">Health check</a></li>
  <li><a href="/pay">Pay demo</a></li>
  <li><a href="/metrics">OpenTelemetry metrics</a></li>
</ul>
<p>POST JSON to <code>/pay</code> to create a demo payment.</p>
"""


def _float_env(name: str, default: float = 0.0) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def _int_env(name: str, default: int = 0) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def create_app() -> Flask:
    version = os.getenv("SERVICE_VERSION", "dev")
    environment = os.getenv("DEPLOYMENT_ENVIRONMENT", "local")
    service_name = os.getenv("OTEL_SERVICE_NAME", "payment-service")
    resource = Resource.create({
        SERVICE_NAME: service_name,
        SERVICE_VERSION: version,
        DEPLOYMENT_ENVIRONMENT: environment,
    })

    meter_provider = MeterProvider(resource=resource, metric_readers=[PrometheusMetricReader()])
    metrics.set_meter_provider(meter_provider)
    meter = meter_provider.get_meter(service_name, version)
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
    trace.set_tracer_provider(tracer_provider)
    tracer = trace.get_tracer(service_name, version)

    labels = {"service_version": version, "deployment_environment": environment}
    request_count = meter.create_counter("payment_request_count", unit="{request}", description="Payment requests received")
    error_count = meter.create_counter("payment_error_count", unit="{error}", description="Payment requests rejected")
    latency = meter.create_histogram("payment_request_latency_ms", unit="ms", description="Payment request latency")
    state_lock = threading.Lock()
    total_payments = 0
    failed_payments = 0

    def error_rate_callback(_options):
        with state_lock:
            rate = failed_payments / total_payments if total_payments else 0.0
        return [Observation(rate, {**labels, "route": "/pay"})]

    meter.create_observable_gauge(
        "payment_error_rate", callbacks=[error_rate_callback], unit="1", description="Payment error rate"
    )

    app = Flask(__name__)
    app.config.update(
        SERVICE_VERSION=version,
        DEPLOYMENT_ENVIRONMENT=environment,
        FAILURE_MODE=os.getenv("FAILURE_MODE", "none").lower(),
        FORCE_ERROR_RATE=max(0.0, min(1.0, _float_env("FORCE_ERROR_RATE"))),
        EXTRA_LATENCY_MS=max(0, _int_env("EXTRA_LATENCY_MS")),
    )
    sequence_lock = threading.Lock()
    payment_sequence = 0

    FlaskInstrumentor().instrument_app(app)

    @app.before_request
    def start_request() -> None:
        request.environ["payment_started_at"] = time.perf_counter()

    @app.after_request
    def record_request(response: Response) -> Response:
        started = request.environ.get("payment_started_at")
        if started is not None:
            latency.record((time.perf_counter() - started) * 1000, {**labels, "route": request.path})
        return response

    def next_payment_number() -> int:
        nonlocal payment_sequence
        with sequence_lock:
            payment_sequence += 1
            return payment_sequence

    def should_fail(payment_number: int) -> bool:
        mode = app.config["FAILURE_MODE"]
        if mode in {"error", "errors", "high_error_rate"}:
            return True
        rate = app.config["FORCE_ERROR_RATE"]
        if rate <= 0:
            return False
        if rate >= 1:
            return True
        cycle_size = 10
        threshold = round(rate * cycle_size)
        return ((payment_number - 1) % cycle_size) < threshold

    def delay() -> None:
        extra_ms = app.config["EXTRA_LATENCY_MS"]
        if app.config["FAILURE_MODE"] in {"latency", "slow", "high_latency"} and extra_ms == 0:
            extra_ms = 1000
        if extra_ms:
            time.sleep(extra_ms / 1000)

    @app.get("/")
    def index() -> str:
        return render_template_string(UI, version=version, environment=environment)

    @app.get("/health")
    def health() -> tuple[Any, int]:
        delay()
        if app.config["FAILURE_MODE"] in {"unhealthy", "health_failure"}:
            return jsonify(status="unhealthy", version=version, environment=environment), 503
        return jsonify(status="healthy", version=version, environment=environment), 200

    @app.route("/pay", methods=["GET", "POST"])
    def pay() -> tuple[Any, int]:
        nonlocal total_payments, failed_payments
        number = next_payment_number()
        with state_lock:
            total_payments += 1
        request_count.add(1, {**labels, "route": "/pay"})
        delay()
        if should_fail(number):
            with state_lock:
                failed_payments += 1
            error_count.add(1, {**labels, "route": "/pay"})
            with tracer.start_as_current_span("payment.failure") as span:
                span.set_attribute("payment.sequence", number)
                span.set_attribute("payment.failure_mode", app.config["FAILURE_MODE"])
            return jsonify(status="error", error="injected failure", sequence=number), 500

        payload = request.get_json(silent=True) or {}
        with tracer.start_as_current_span("payment.process") as span:
            span.set_attribute("payment.sequence", number)
            span.set_attribute("payment.amount", float(payload.get("amount", 1.0)))
            span.set_attribute("service.version", version)
            span.set_attribute("deployment.environment", environment)
        return jsonify(status="accepted", payment_id=f"demo-{number}", sequence=number), 200

    @app.get("/metrics")
    def metrics_endpoint() -> Response:
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=_int_env("PORT", 8080))
