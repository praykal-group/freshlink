# Binary telemetry packet (SYN-01)

Little-endian, **40 bytes**, sent on MQTT topic `iccms/telemetry/<mqtt username>` (QoS 1). JSON packets use the same topic; the server tells them apart by the first byte (`{` = JSON).

| Offset | Type | Field | Scale / meaning |
|-------:|------|-------|-----------------|
| 0 | u8 | version | `1` |
| 1 | u8 | flags | bit 0 = reefer on, bit 1 = door open |
| 2 | u16 | battery | % × 10 |
| 4 | u32 | epoch_s | Unix time of the reading (seconds, UTC) |
| 8 | i16 | temp | °C × 100 |
| 10 | u16 | humidity | % × 100 |
| 12 | i16 | ax | g × 1000 |
| 14 | i16 | ay | g × 1000 |
| 16 | i16 | az | g × 1000 |
| 18 | u16 | shock | peak g × 100 |
| 20 | u16 | ethylene | ppm × 100 |
| 22 | i16 | setpoint | °C × 100 |
| 24 | i32 | lat | degrees × 1e6 |
| 28 | i32 | lng | degrees × 1e6 |
| 32 | u32 | seq | packet sequence number per device (wraps at 2³²) |
| 36 | u32 | crc32 | IEEE CRC-32 (zlib) of bytes 0..35 |

The spec text lists fields that add up to 32 bytes for a 40-byte packet with a CRC over the first 36. The four missing bytes (offset 32) carry `seq`, which lets the server count lost packets and drop duplicates (D-89).

A packet with a wrong CRC, length or version is **dropped** and counted (`telemetry:dropped:<reason>` in Redis, worker log). JSON packets carry the same `seq` as `"n"`.

Example (Python): see `encode_binary()` in `sim.py`. Example (TypeScript): `encodeBinary()` in `server/src/modules/telemetry/packet.ts`.
