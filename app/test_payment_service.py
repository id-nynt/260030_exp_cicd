import os
import unittest

from payment_service import create_app


class PaymentServiceTests(unittest.TestCase):
    def setUp(self):
        self.original = {key: os.environ.get(key) for key in (
            "SERVICE_VERSION", "DEPLOYMENT_ENVIRONMENT", "FAILURE_MODE",
            "FORCE_ERROR_RATE", "EXTRA_LATENCY_MS",
        )}

    def tearDown(self):
        for key, value in self.original.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def client(self, **values):
        for key, value in values.items():
            os.environ[key] = str(value)
        return create_app().test_client()

    def test_healthy_service_and_metadata(self):
        client = self.client(SERVICE_VERSION="1.2.3", DEPLOYMENT_ENVIRONMENT="staging")
        self.assertEqual(client.get("/health").status_code, 200)
        body = client.get("/health").get_json()
        self.assertEqual(body["status"], "healthy")
        self.assertEqual(body["version"], "1.2.3")
        self.assertEqual(body["environment"], "staging")
        self.assertEqual(client.post("/pay", json={"amount": 10}).status_code, 200)

    def test_forced_errors_are_deterministic(self):
        client = self.client(FAILURE_MODE="error")
        self.assertEqual(client.post("/pay").status_code, 500)
        self.assertEqual(client.post("/pay").status_code, 500)

    def test_fractional_error_rate_uses_request_sequence(self):
        client = self.client(FORCE_ERROR_RATE="0.5")
        results = [client.post("/pay").status_code for _ in range(6)]
        self.assertEqual(results, [500, 500, 500, 500, 500, 200])

    def test_unhealthy_mode_fails_health(self):
        client = self.client(FAILURE_MODE="unhealthy")
        self.assertEqual(client.get("/health").status_code, 503)

    def test_metrics_endpoint_is_available(self):
        client = self.client()
        client.post("/pay")
        response = client.get("/metrics")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"payment_request_count", response.data)
        self.assertIn(b"payment_error_rate", response.data)


if __name__ == "__main__":
    unittest.main()
