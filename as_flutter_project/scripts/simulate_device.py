"""Send simulated ESP32 readings to the existing Smart Home API.

This tool is intentionally transport-only: it uses the same ingestion routes
and device API key as the ESP32 firmware, without changing the application,
database schema, or API contract.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from dotenv import load_dotenv


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
load_dotenv(PROJECT_DIR / "backend" / ".env")
load_dotenv(PROJECT_DIR / ".env", override=False)


def _post_json(url: str, payload: dict, api_key: str) -> dict:
    body = json.dumps(payload).encode("utf-8")
    request = Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-Device-API-Key": api_key,
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"API returned HTTP {error.code}: {detail}") from error
    except URLError as error:
        raise RuntimeError(f"Could not reach backend: {error.reason}") from error


def _energy_payload(sequence: int, spike: bool) -> dict:
    voltage = 255.0 if spike and sequence % 3 == 0 else 220.0 + (sequence % 4)
    current = 36.0 if spike and sequence % 3 == 0 else 2.0 + (sequence % 3) * 0.25
    power = round(voltage * current, 2)
    return {
        "voltage": voltage,
        "current": current,
        "power": power,
        "energy": round(0.01 * (sequence + 1), 4),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "channels": {"simulated": 1.0},
    }


def _sensor_payload(sequence: int, spike: bool) -> dict:
    temperature = 28.0 + (sequence % 5)
    if spike and sequence % 3 == 0:
        temperature = 65.0
    return {
        "readings": [
            {"sensor_type": "temperature", "value": temperature, "unit": "C"},
            {"sensor_type": "humidity", "value": 45.0 + (sequence % 6), "unit": "%"},
        ]
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend-url",
        default=os.getenv("BACKEND_URL", "http://localhost:8000"),
        help="Backend base URL (default: BACKEND_URL or localhost:8000)",
    )
    parser.add_argument(
        "--device-id",
        default=os.getenv("ENERGY_DEVICE_ID", ""),
        help="Registered Energy Monitor database ID (or ENERGY_DEVICE_ID)",
    )
    parser.add_argument(
        "--api-key",
        default=os.getenv("DEVICE_INGEST_API_KEY", ""),
        help="Device ingestion key (or DEVICE_INGEST_API_KEY)",
    )
    parser.add_argument("--count", type=int, default=1, help="Number of batches to send")
    parser.add_argument("--interval", type=float, default=5.0, help="Seconds between batches")
    parser.add_argument("--spike", action="store_true", help="Occasionally generate threshold-triggering values")
    args = parser.parse_args()

    if not args.device_id:
        parser.error("--device-id is required; register an Energy Monitor device first")
    if not args.api_key:
        parser.error("--api-key is required; set DEVICE_INGEST_API_KEY")
    if args.count < 1:
        parser.error("--count must be at least 1")

    base_url = args.backend_url.rstrip("/")
    for sequence in range(args.count):
        try:
            energy = _post_json(
                f"{base_url}/ingest/energy?device_id={args.device_id}",
                _energy_payload(sequence, args.spike),
                args.api_key,
            )
            sensors = _post_json(
                f"{base_url}/ingest/sensors?device_id={args.device_id}",
                _sensor_payload(sequence, args.spike),
                args.api_key,
            )
        except RuntimeError as error:
            print(f"Simulation failed: {error}", file=sys.stderr)
            return 1

        # Report only non-sensitive status; never print the API key or tokens.
        print(
            f"batch {sequence + 1}/{args.count}: "
            f"energy={energy.get('success', False)} "
            f"sensors={sensors.get('stored', 0)}"
        )
        if sequence + 1 < args.count:
            time.sleep(max(0.0, args.interval))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
