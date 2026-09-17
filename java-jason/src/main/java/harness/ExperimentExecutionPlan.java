package harness;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/** Configuration-only per-entity injection lookup used by experiment runs. */
public final class ExperimentExecutionPlan {
    public record Injection(String failureMode, String forceErrorRate,
                            String extraLatencyMs, String executionDelayMs) {
        static Injection none() { return new Injection("none", "0", "0", "0"); }
    }

    private final Properties properties = new Properties();
    private final Map<String, Integer> attempts = new HashMap<>();

    public ExperimentExecutionPlan() {
        String path = System.getenv("BDI_EXECUTION_PLAN");
        if (path != null && !path.isBlank()) {
            try (InputStream input = Files.newInputStream(Path.of(path))) {
                properties.load(input);
            } catch (IOException error) {
                throw new IllegalStateException("Unable to read BDI_EXECUTION_PLAN: " + path, error);
            }
        }
    }

    public synchronized Injection next(String entity) {
        int attempt = attempts.merge(entity, 1, Integer::sum);
        String prefix = entity + "." + attempt + ".";
        return new Injection(
            value(prefix + "failure_mode", value(entity + ".failure_mode", "none")),
            value(prefix + "force_error_rate", value(entity + ".force_error_rate", "0")),
            value(prefix + "extra_latency_ms", value(entity + ".extra_latency_ms", "0")),
            value(prefix + "execution_delay_ms", value(entity + ".execution_delay_ms", "0")));
    }

    private String value(String key, String fallback) {
        String value = properties.getProperty(key);
        return value == null || value.isBlank() ? fallback : value;
    }
}
