package harness;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import telemetry.Observation;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/** Local HTTP test for dispatch correlation, polling, and status normalization. */
public final class GitHubActionsWorkflowExecutorTest {
    public static void main(String[] args) throws Exception {
        AtomicReference<String> dispatchBody = new AtomicReference<>();
        AtomicInteger statusCalls = new AtomicInteger();
        HttpServer server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
        server.createContext("/repos/acme/payment/actions/workflows/entity-execution.yml/dispatches",
            exchange -> respond(exchange, 200, dispatchBody, "{\"workflow_run_id\":12345}"));
        server.createContext("/repos/acme/payment/actions/runs/12345", exchange -> {
            statusCalls.incrementAndGet();
            String body = statusCalls.get() == 1
                ? "{\"status\":\"in_progress\",\"conclusion\":null}"
                : "{\"status\":\"completed\",\"conclusion\":\"success\"}";
            respond(exchange, 200, null, body);
        });
        server.start();
        try {
            List<Observation> observations = new ArrayList<>();
            GitHubActionsWorkflowExecutor executor = new GitHubActionsWorkflowExecutor(
                new GitHubActionsWorkflowExecutor.Config(
                    URI.create("http://localhost:" + server.getAddress().getPort()),
                    "acme/payment", "entity-execution.yml", "test-token", "main",
                    Duration.ofMillis(5), Duration.ofSeconds(2)), observations::add);

            executor.runJob("test");

            require(dispatchBody.get().contains("\"entity\":\"test\""), "entity input dispatched");
            require(dispatchBody.get().contains("\"return_run_details\":true"), "run details requested");
            require(statusCalls.get() >= 2, "exact returned run was polled");
            require(observations.stream().anyMatch(o -> o.entity().equals("test")
                && o.property().equals("execution_status") && o.value().equals("success")),
                "success execution observation emitted");
            require(observations.stream().anyMatch(o -> o.entity().equals("test")
                && o.property().equals("duration")), "duration observation emitted");
            System.out.println("GitHubActionsWorkflowExecutorTest: PASS");
        } finally {
            server.stop(0);
        }
    }

    private static void respond(HttpExchange exchange, int status, AtomicReference<String> bodyCapture,
                                String body) throws IOException {
        if (bodyCapture != null) {
            bodyCapture.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
        }
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }

    private static void require(boolean condition, String description) {
        if (!condition) throw new AssertionError(description);
        System.out.println("PASS: " + description);
    }
}
