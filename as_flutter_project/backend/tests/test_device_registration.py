import asyncio
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app import main


class _Result:
    def __init__(self, row=None):
        self.row = row

    def fetchone(self):
        return self.row


class _Connection:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.calls = []
        self.committed = False
        self.closed = False

    def execute(self, query, params=None):
        self.calls.append((query, params))
        return _Result(next(self.responses, None))

    def commit(self):
        self.committed = True

    def close(self):
        self.closed = True


class DeviceRegistrationTests(unittest.TestCase):
    def test_registration_persists_mqtt_id_and_returns_backend_id(self):
        row = {
            "id": 12,
            "name": "Sala",
            "type": "esp32",
            "status": "off",
            "is_online": False,
            "pin": 23,
            "topic": "home/device/sala",
            "mqtt_client_id": "sala",
            "location": "",
            "created_at": None,
            "last_seen": None,
        }
        connection = _Connection([None, row])
        payload = main.DeviceCreateRequest(
            name="Sala",
            type="esp32",
            pin=23,
            topic="home/device/sala",
            mqtt_client_id="sala",
        )

        with patch.object(main, "_create_db_connection", return_value=connection):
            response = asyncio.run(
                main.register_device(payload, SimpleNamespace(id=7))
            )

        insert_sql, insert_params = connection.calls[1]
        self.assertIn("mqtt_client_id", insert_sql)
        self.assertEqual(insert_params, (7, "Sala", "esp32", 23,
                                         "home/device/sala", "sala", ""))
        self.assertEqual(response["id"], 12)
        self.assertEqual(response["device_id"], "12")
        self.assertEqual(response["mqtt_client_id"], "sala")
        self.assertTrue(connection.committed)
        self.assertTrue(connection.closed)

    def test_registration_accepts_legacy_flutter_field_names(self):
        payload = main.DeviceCreateRequest(
            device_name="Sala",
            device_type="esp32",
            mqtt_client_id="sala",
            location="",
        )

        self.assertEqual(payload.name, "Sala")
        self.assertEqual(payload.type, "esp32")
        self.assertEqual(payload.mqtt_client_id, "sala")

    def test_registration_retries_update_the_existing_mqtt_device(self):
        row = {
            "id": 12,
            "name": "Sala",
            "type": "esp32",
            "status": "off",
            "is_online": False,
            "pin": 23,
            "topic": "home/device/sala",
            "mqtt_client_id": "sala",
            "location": "",
            "created_at": None,
            "last_seen": None,
        }
        connection = _Connection([{"id": 12}, row])
        payload = main.DeviceCreateRequest(
            name="Sala",
            type="esp32",
            pin=23,
            topic="home/device/sala",
            mqtt_client_id="sala",
        )

        with patch.object(main, "_create_db_connection", return_value=connection):
            response = asyncio.run(
                main.register_device(payload, SimpleNamespace(id=7))
            )

        update_sql, update_params = connection.calls[1]
        self.assertIn("UPDATE devices", update_sql)
        self.assertEqual(update_params[-2:], (12, 7))
        self.assertEqual(response["id"], 12)
        self.assertTrue(connection.committed)


class DeviceControlMqttTests(unittest.TestCase):
    def test_registered_sala_publishes_the_firmware_topic(self):
        select_and_log = _Connection([
            {
                "id": 12,
                "user_id": 7,
                "name": "Sala",
                "status": "off",
                "mqtt_client_id": "sala",
            },
            {"id": 41},
        ])
        update_log = _Connection([None])
        published = []

        with (
            patch.object(
                main,
                "_create_db_connection",
                side_effect=[select_and_log, update_log],
            ),
            patch.object(
                main,
                "_publish_mqtt_message",
                side_effect=lambda topic, message: published.append((topic, message)),
            ),
        ):
            response = main._execute_device_command(7, "12", "ON")

        self.assertEqual(published, [("home/device/sala/set", "ON")])
        self.assertTrue(response["mqtt_published"])
        self.assertEqual(response["topic"], "home/device/sala/set")


if __name__ == "__main__":
    unittest.main()
