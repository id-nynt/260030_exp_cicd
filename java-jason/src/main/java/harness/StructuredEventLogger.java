package harness;

import telemetry.Observation;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.logging.Logger;

/** Small JSON-lines logger for evaluating cross-component transitions. */
public final class StructuredEventLogger {
    private static final Logger LOG = Logger.getLogger(StructuredEventLogger.class.getName());
    private final Path output;

    public StructuredEventLogger(Path output) {
        this.output = output;
    }

    public synchronized void event(String event, CorrelationContext context,
                                    Map<String, ?> fields) {
        Map<String, Object> all = new LinkedHashMap<>();
        all.put("timestamp", Instant.now().toString());
        all.put("event", event);
        if (context != null) {
            all.put("experiment_id", context.experimentId());
            all.put("release_id", context.releaseId());
            all.put("entity", context.entity());
            all.put("execution_id", context.executionId());
            all.put("github_run_id", context.githubRunId() == 0 ? null : context.githubRunId());
            all.put("deployment_environment", context.environment());
        }
        all.putAll(fields);
        String line = toJson(all);
        LOG.info(line);
        if (output != null) {
            try {
                Files.createDirectories(output.toAbsolutePath().getParent());
                Files.writeString(output, line + System.lineSeparator(), StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException error) {
                LOG.warning("structured_log_file_error=" + error.getMessage());
            }
        }
    }

    public void observation(Observation observation, CorrelationContext context, String belief) {
        event("observation_normalized", context, Map.of(
            "property", observation.property(), "value", observation.value(), "belief", belief));
    }

    private static String toJson(Map<String, ?> fields) {
        StringBuilder result = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<String, ?> field : fields.entrySet()) {
            if (!first) result.append(',');
            first = false;
            result.append('"').append(escape(field.getKey())).append("\":");
            Object value = field.getValue();
            if (value == null) result.append("null");
            else if (value instanceof Number || value instanceof Boolean) result.append(value);
            else result.append('"').append(escape(String.valueOf(value))).append('"');
        }
        return result.append('}').toString();
    }

    private static String escape(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r");
    }
}
