"""I-CCMS IoT reefer pod simulator (Section 9.1).

    python sim.py --devices 3 --scenario scenarios/reefer_failure.yaml --broker mqtt://localhost:1883 \
                  --interval 60 --speedup 60 [--format binary] [--duration-min 90]

Each device publishes one packet per `--interval` simulated seconds to `iccms/telemetry/<username>`
(QoS 1), username `dev-001` …, password `<DEV-001>:<secret>` (matches the dev Mosquitto setup and
the seed). Simulated time runs `--speedup` times faster than real time; packet timestamps are wall
clock, so set `--speedup` equal to the server's TELEMETRY_TIME_SCALE for time-scaled pipeline tests.
"""

import argparse
import json
import math
import random
import struct
import sys
import time
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Optional
from urllib.parse import urlparse

BINARY_VERSION = 1
AMBIENT_C = 30.0


def encode_binary(r: Dict) -> bytes:
    """40-byte little-endian packet, see binary_format.md."""
    flags = (1 if r["r"] else 0) | (2 if r["do"] else 0)
    body = struct.pack(
        "<BBHIhHhhhHHhiiI",
        BINARY_VERSION,
        flags,
        round(r["b"] * 10),
        int(r["epoch"]),
        round(r["t"] * 100),
        round(r["h"] * 100),
        round(r["ax"] * 1000),
        round(r["ay"] * 1000),
        round(r["az"] * 1000),
        round(r["g"] * 100),
        round(r["e"] * 100),
        round(r["sp"] * 100),
        round(r["lat"] * 1e6),
        round(r["lng"] * 1e6),
        r["n"] & 0xFFFFFFFF,
    )
    assert len(body) == 36
    return body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


def encode_json(code: str, r: Dict) -> bytes:
    keys = ("t", "h", "ax", "ay", "az", "g", "e", "lat", "lng", "r", "sp", "do", "b", "n")
    out = {"d": code, "ts": r["ts"]}
    out.update({k: (int(r[k]) if k in ("r", "do") else r[k]) for k in keys})
    return json.dumps(out, separators=(",", ":")).encode()


@dataclass
class Phase:
    from_min: float
    reefer_on: bool = True
    drift_c_per_10min: float = 0.0
    door_open: bool = False
    ethylene_ppm_per_10min: float = 0.0
    humidity_pct: Optional[float] = None


@dataclass
class Scenario:
    name: str
    start: Dict[str, float]
    end: Dict[str, float]
    setpoint_c: float = 2.0
    initial_temp_c: float = 2.0
    humidity_pct: float = 90.0
    base_ethylene_ppm: float = 0.2
    phases: List[Phase] = field(default_factory=list)
    shocks: List[Dict[str, float]] = field(default_factory=list)  # [{at_min, g}]
    dropout: Optional[Dict[str, float]] = None  # {from_min, to_min}
    beacons: Optional[Dict] = None  # {site, beacons: [..], batch_tags: [..]}

    @staticmethod
    def load(path: str) -> "Scenario":
        import yaml

        raw = yaml.safe_load(open(path, encoding="utf-8"))
        raw["phases"] = [Phase(**p) for p in raw.get("phases", [{"from_min": 0}])]
        return Scenario(**raw)

    def phase_at(self, minute: float) -> Phase:
        current = self.phases[0]
        for p in self.phases:
            if p.from_min <= minute:
                current = p
        return current


class Device:
    def __init__(self, index: int, sc: Scenario, rng: random.Random):
        self.code = f"DEV-{index:03d}"
        self.username = self.code.lower()
        self.sc = sc
        self.rng = rng
        self.temp = sc.initial_temp_c + rng.uniform(-0.2, 0.2)
        self.ethylene = sc.base_ethylene_ppm
        self.battery = rng.uniform(70, 95)
        self.seq = 0
        # Spread trucks a little so they do not share coordinates.
        self.offset = (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02))

    def step(self, minute: float, dt_min: float, total_min: float) -> Dict:
        sc, p, rng = self.sc, self.sc.phase_at(minute), self.rng
        if p.reefer_on:
            self.temp += (sc.setpoint_c - self.temp) * min(1.0, 0.3 * dt_min)  # pull-down
        else:
            self.temp += (AMBIENT_C - self.temp) * min(1.0, 0.01 * dt_min)  # warm-up towards ambient
        self.temp += p.drift_c_per_10min * dt_min / 10.0 + rng.gauss(0, 0.05)
        if p.door_open:
            self.temp += 0.3 * dt_min
        self.ethylene = max(0.0, self.ethylene + p.ethylene_ppm_per_10min * dt_min / 10.0 + rng.gauss(0, 0.02))
        shock = max(0.05, abs(rng.gauss(0.2, 0.1)))
        for s in sc.shocks:
            if minute - dt_min < s["at_min"] <= minute:
                shock = s["g"]
        frac = min(1.0, minute / max(total_min, 1))
        lat = sc.start["lat"] + (sc.end["lat"] - sc.start["lat"]) * frac + self.offset[0]
        lng = sc.start["lng"] + (sc.end["lng"] - sc.start["lng"]) * frac + self.offset[1]
        self.battery = max(0.0, self.battery - 0.001 * dt_min)
        self.seq += 1
        now = datetime.now(timezone.utc)
        hum = p.humidity_pct if p.humidity_pct is not None else sc.humidity_pct
        return {
            "ts": now.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "epoch": now.timestamp(),
            "t": round(self.temp, 2),
            "h": round(min(100.0, max(0.0, hum + rng.gauss(0, 1))), 2),
            "ax": round(rng.gauss(0, 0.02), 3),
            "ay": round(rng.gauss(0, 0.02), 3),
            "az": round(0.98 + rng.gauss(0, 0.02), 3),
            "g": round(shock, 2),
            "e": round(self.ethylene, 2),
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "r": p.reefer_on,
            "sp": sc.setpoint_c,
            "do": p.door_open,
            "b": round(self.battery, 1),
            "n": self.seq,
        }


def connect(broker: str, username: str, password: str):
    import paho.mqtt.client as mqtt

    u = urlparse(broker)
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"sim-{username}", clean_session=True)
    client.username_pw_set(username, password)
    if u.scheme == "mqtts":
        client.tls_set()
    client.connect(u.hostname or "localhost", u.port or (8883 if u.scheme == "mqtts" else 1883), keepalive=60)
    client.loop_start()
    return client


def main() -> int:
    ap = argparse.ArgumentParser(description="I-CCMS reefer pod simulator")
    ap.add_argument("--devices", type=int, default=3)
    ap.add_argument("--start-index", type=int, default=1, help="first device number (DEV-001 = 1)")
    ap.add_argument("--scenario", required=True)
    ap.add_argument("--broker", default="mqtt://localhost:1883")
    ap.add_argument("--secret", default="dev-device-secret", help="SEED_DEVICE_SECRET")
    ap.add_argument("--interval", type=float, default=60, help="simulated seconds between packets")
    ap.add_argument("--speedup", type=float, default=1, help="simulated seconds per real second")
    ap.add_argument("--duration-min", type=float, default=60, help="simulated minutes to run")
    ap.add_argument("--format", choices=["json", "binary"], default="json")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dry-run", action="store_true", help="print packets instead of publishing")
    a = ap.parse_args()

    sc = Scenario.load(a.scenario)
    rng = random.Random(a.seed)
    devices = [Device(i, sc, random.Random(rng.random())) for i in range(a.start_index, a.start_index + a.devices)]
    clients = {} if a.dry_run else {d.code: connect(a.broker, d.username, f"{d.code}:{a.secret}") for d in devices}
    buffered: Dict[str, List[bytes]] = {d.code: [] for d in devices}
    sent = dropped_buffered = 0
    dt_min = a.interval / 60.0
    ticks = int(math.ceil(a.duration_min / dt_min))
    real_sleep = a.interval / a.speedup
    print(f"scenario={sc.name} devices={len(devices)} ticks={ticks} every {real_sleep:.2f}s real", file=sys.stderr)

    for k in range(1, ticks + 1):
        started = time.monotonic()
        minute = k * dt_min
        in_dropout = sc.dropout is not None and sc.dropout["from_min"] <= minute < sc.dropout["to_min"]
        for d in devices:
            r = d.step(minute, dt_min, a.duration_min)
            payload = encode_binary(r) if a.format == "binary" else encode_json(d.code, r)
            topic = f"iccms/telemetry/{d.username}"
            if a.dry_run:
                print(topic, payload.hex() if a.format == "binary" else payload.decode())
                continue
            if in_dropout:
                buffered[d.code].append(payload)  # network_dropout: keep with the original timestamp
                continue
            for old in buffered[d.code]:  # burst-send what was buffered
                clients[d.code].publish(topic, old, qos=1)
                sent += 1
                dropped_buffered += 1
            buffered[d.code].clear()
            clients[d.code].publish(topic, payload, qos=1)
            sent += 1
        if sc.beacons and not a.dry_run:
            b = sc.beacons
            tag = b["batch_tags"][k % len(b["batch_tags"])]
            beacon = b["beacons"][k % len(b["beacons"])]
            msg = json.dumps({"site": b["site"], "beacon": beacon, "tag": tag, "rssi": -40 - rng.randint(0, 40), "ts": datetime.now(timezone.utc).isoformat()})
            clients[devices[0].code].publish(f"iccms/beacons/{devices[0].username}", msg, qos=1)
        time.sleep(max(0.0, real_sleep - (time.monotonic() - started)))

    for c in clients.values():
        c.loop_stop()
        c.disconnect()
    print(json.dumps({"scenario": sc.name, "devices": len(devices), "sent": sent, "burstReplayed": dropped_buffered}), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
