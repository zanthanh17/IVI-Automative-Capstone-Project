# IVI Automotive Capstone Project

Repo này gồm ba phần chính của hệ thống IVI/Instrument Cluster:

- `firmware/`: STM32F103 input ECU đọc nút, switch, encoder, ADC và phát CAN `0x100`, `0x101`, `0x102`.
- `cp/`: STM32F103 Body ECU nhận lệnh CAN, điều khiển xi nhan trái/phải, đèn thường, đèn pha và còi, đồng thời phát status `0x201`.
- `software/QtInstrumentCluster/`: ứng dụng Qt/QML chạy trên Raspberry Pi, đọc CAN qua SocketCAN `can0` và cập nhật dashboard.

CAN bus dùng standard 11-bit, DLC 8 byte, bitrate 500 kbps. Raspberry Pi dùng MCP2515/SocketCAN; STM32 dùng bxCAN `PA11/PA12` qua transceiver SN65HVD230/TJA1050-compatible.

## CAN frame chính

| ID | Nguồn | Nội dung |
|---|---|---|
| `0x100` | `firmware/` | Telemetry: speed, rpm, fuel, battery, gear |
| `0x101` | `firmware/` | Control snapshot: xi nhan, đèn, parked, airbag, horn |
| `0x102` | `firmware/` | Control event, ID `7` là `horn` |
| `0x201` | `cp/` | Body status: command mask, output mask, ready/timeout/error flags |

Xem chi tiết trong [`docs/can_bus_report.md`](docs/can_bus_report.md) và [`docs/hardware_design.md`](docs/hardware_design.md).

## Kiểm thử nhanh CAN trên Raspberry Pi

```bash
sudo ip link set can0 down
sudo ip link set can0 up type can bitrate 500000 restart-ms 100
candump -tz -x -e can0
```

Kỳ vọng thấy `0x100/0x101/0x102` từ firmware và `0x201` từ Body ECU.
