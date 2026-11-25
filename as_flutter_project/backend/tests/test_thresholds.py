import unittest
from unittest.mock import patch

from app import main


class _FakeResult:
    def __init__(self, row):
        self._row = row

    def fetchone(self):
        return self._row


class _FakeConnection:
    def __init__(self, rows):
        self._rows = iter(rows)
        self.calls = []

    def execute(self, query, params=None):
        self.calls.append((query, params))
        try:
            row = next(self._rows)
        except StopIteration:
            row = None
        return _FakeResult(row)


def _configured_preferences():
    return {
        'voltage_min': 210.0,
        'voltage_max': 240.0,
        'amperage_max': 15.0,
        'sensor_thresholds_configured': True,
    }


class ThresholdEvaluationTests(unittest.TestCase):
    def test_disabled_thresholds_do_not_create_alerts(self):
        connection = _FakeConnection([
            {
                **_configured_preferences(),
                'sensor_thresholds_configured': False,
            }
        ])

        result = main._evaluate_sensor_thresholds(
            connection, 7, 'device-1', 'voltage', 300.0
        )

        self.assertIsNone(result)
        self.assertEqual(len(connection.calls), 1)

    @patch('app.main._insert_alert_notification')
    @patch('app.main._insert_alert')
    def test_voltage_violation_creates_one_alert_and_notification(
        self, insert_alert, insert_notification
    ):
        connection = _FakeConnection([_configured_preferences(), None])
        insert_alert.return_value = {
            'id': 41,
            'title': 'Voltage above limit',
            'message': 'Voltage 250 V exceeds the maximum 240 V.',
            'severity': 'high',
        }

        result = main._evaluate_sensor_thresholds(
            connection, 7, 'device-1', 'volts', 250.0
        )

        self.assertEqual(result['metadata']['severity'], 'high')
        insert_alert.assert_called_once_with(
            connection,
            7,
            title='Voltage above limit',
            message='Voltage 250 V exceeds the maximum 240 V.',
            severity='high',
            source='sensor',
            device_id='device-1',
            metadata={'sensor_type': 'volts', 'value': 250.0},
        )
        insert_notification.assert_called_once_with(
            connection, 7, insert_alert.return_value
        )

    @patch('app.main._insert_alert_notification')
    @patch('app.main._insert_alert')
    def test_existing_open_alert_prevents_duplicate_alert(
        self, insert_alert, insert_notification
    ):
        connection = _FakeConnection([
            _configured_preferences(),
            {'id': 41},
        ])

        result = main._evaluate_sensor_thresholds(
            connection, 7, 'device-1', 'current', 20.0
        )

        self.assertIsNone(result)
        insert_alert.assert_not_called()
        insert_notification.assert_not_called()

    def test_normal_reading_resolves_matching_open_alerts(self):
        connection = _FakeConnection([_configured_preferences(), None])

        result = main._evaluate_sensor_thresholds(
            connection, 7, 'device-1', 'current_a', 10.0
        )

        self.assertIsNone(result)
        self.assertEqual(len(connection.calls), 2)
        query, params = connection.calls[1]
        self.assertIn('UPDATE alerts SET resolved = TRUE, is_read = TRUE', query)
        self.assertEqual(params, (7, 'device-1', 'current_a'))


if __name__ == '__main__':
    unittest.main()
