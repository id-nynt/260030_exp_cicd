package harness;

import telemetry.Observation;

import java.time.Instant;
import java.util.List;

/** Dependency-free unit checks for the generic Java layer. */
public final class EnvironmentLayerTest {
    public static void main(String[] args) throws Exception {
        MockObservationProvider provider = new MockObservationProvider();
        MockWorkflowExecutor executor = new MockWorkflowExecutor(provider::publish);

        executor.runJob("test");

        require(executor.executedEntities().equals(List.of("test")), "mock executor received test");
        List<Observation> observations = provider.getObservations();
        require(observations.stream().anyMatch(o -> o.entity().equals("test")
            && o.property().equals("execution_status") && o.value().equals("success")),
            "mock execution observation arrived");
        require(new JasonBeliefAdapter().convert(
            new Observation("test", "execution_status", "success", Instant.now()))
            .equals("status(test,success)"), "observation converted to Jason belief");
        require(new JasonBeliefAdapter().convert(
            new Observation("test", "latency", 850, Instant.now()))
            .equals("metric(test,latency,850)"), "metric converted to Jason belief");
        System.out.println("EnvironmentLayerTest: PASS");
    }

    private static void require(boolean condition, String description) {
        if (!condition) throw new AssertionError(description);
        System.out.println("PASS: " + description);
    }
}
