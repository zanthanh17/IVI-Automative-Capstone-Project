# Thiết kế phần cứng IVI Automotive - Ánh xạ Dashboard UI

## Tổng quan

Firmware STM32F103C8T6 được thiết kế lại để ánh xạ **đầy đủ** các tính năng hiển thị
trên Dashboard UI (Qt Instrument Cluster).

## Sơ đồ chân STM32F103C8T6

```
                    STM32F103C8T6
                  ┌──────────────────┐
                  │                  │
    Fuel (pot) ───┤ PA0  (ADC1_IN0)  │
   Batt (pot) ───┤ PA1  (ADC1_IN1)  │
                  │ PA2              │
                  │ PA3              │
                  │ PA4              │
                  │ PA5              │
   Encoder CLK ──┤ PA6  (TIM3_CH1)  │
   Encoder DT  ──┤ PA7  (TIM3_CH2)  │
  Drive Switch ──┤ PA8  (GPIO IN)   │
  UART Debug TX ─┤ PA9  (USART1_TX) │──── → Debug UART RX
  UART Debug RX ─┤ PA10 (USART1_RX) │──── ← Debug UART TX
    CAN RX  ─────┤ PA11 (CAN1_RX)   │──── ← SN65HVD230 CRX/RXD
    CAN TX  ─────┤ PA12 (CAN1_TX)   │──── → SN65HVD230 CTX/TXD
    SWD IO ──────┤ PA13 (SWDIO)     │
    SWD CLK ─────┤ PA14 (SWCLK)     │
                  │ PA15             │
                  │                  │
                  │ PB0              │
  Turn Left  ────┤ PB1  (EXTI1)     │──── Nút nhấn + Pull-up
  Turn Right ────┤ PB2  (EXTI2)     │──── Nút nhấn + Pull-up
  Beam       ────┤ PB3  (EXTI3)     │──── Nút nhấn + Pull-up (JTAG disabled)
  High Beams ────┤ PB4  (EXTI4)     │──── Nút nhấn + Pull-up (JTAG disabled)
  Parked     ────┤ PB5  (EXTI5)     │──── Nút nhấn + Pull-up
  Airbag     ────┤ PB6  (EXTI6)     │──── Nút nhấn + Pull-up
  Media Play ────┤ PB7  (EXTI7)     │──── Nút nhấn + Pull-up
  Media Next ────┤ PB8  (EXTI8)     │──── Nút nhấn + Pull-up
                  │                  │
                  └──────────────────┘
```

## Bảng ánh xạ phần cứng ↔ Dashboard UI

### 1. Gauges (Đồng hồ tốc độ & vòng tua)

| Phần cứng | Pin | Dashboard Property | Hiển thị |
|-----------|-----|-------------------|----------|
| Rotary Encoder KY-040 | PA6 (CLK), PA7 (DT) | `MainModel.speed` | Gauge trái: 0-200 km/h |
| Tính từ speed (speed×35) | - | `MainModel.rpm` | Gauge phải: 0-7000 RPM |
| Suy ra từ speed | - | Gear (P/D) | Chữ "P" hoặc "D" trên gauge phải |

### 2. Tell-Tales Indicators (Đèn cảnh báo trên cùng)

| Phần cứng | Pin | Dashboard Property | Icon |
|-----------|-----|--------------------|------|
| Nút nhấn + EXTI | PB1 | `TellTalesModel.turnLeftActive` | ← (xanh, nhấp nháy) |
| Nút nhấn + EXTI | PB2 | `TellTalesModel.turnRightActive` | → (xanh, nhấp nháy) |
| Nút nhấn + EXTI | PB3 | `TellTalesModel.beamActive` | Đèn chiếu gần (xanh) |
| Nút nhấn + EXTI | PB4 | `TellTalesModel.highBeamsActive` | Đèn pha xa (xanh dương) |
| Nút nhấn + EXTI | PB5 | `TellTalesModel.parkedActive` | Phanh tay/Đỗ xe (đỏ) |
| Nút nhấn + EXTI | PB6 | `TellTalesModel.airbagActive` | Túi khí (đỏ) |

### 3. Status Bar (Thanh trạng thái dưới cùng)

| Phần cứng | Pin | Dashboard Property | Hiển thị |
|-----------|-----|-------------------|----------|
| Biến trở 10kΩ → ADC | PA0 (ADC1_CH0) | `MainModel.fuelLevel` | Thanh nhiên liệu (0-100%) |
| Biến trở 10kΩ → ADC | PA1 (ADC1_CH1) | `MainModel.batteryLevel` | Thanh pin (0-100%) |
| Tính từ encoder | - | `MainModel.odo` | ODO km |
| Tính từ odo | - | `MainModel.range` | Range km |

### 4. Media Player (Khu vực giữa)

| Phần cứng | Pin | Dashboard Action | Chức năng |
|-----------|-----|-----------------|-----------|
| Nút nhấn + EXTI | PB7 | Play/Pause | Phát/Dừng nhạc |
| Nút nhấn + EXTI | PB8 | Next Track | Chuyển bài tiếp theo |

### 5. Công tắc gạt (Polling)

| Phần cứng | Pin | Dashboard Property | Chức năng |
|-----------|-----|-------------------|-----------|
| Công tắc gạt | PA8 | Drive Mode / Gear | Chế độ lái (P ↔ D) |

## Giao thức CAN Bus (500 kbps, Standard ID)

### Frame `0x100` - `VEHICLE_TELEMETRY` (gửi mỗi 100ms)

| Byte | Nội dung |
|---|---|
| 0-1 | Speed km/h, uint16 big-endian |
| 2-3 | RPM, uint16 big-endian |
| 4 | Fuel %, 0-100 |
| 5 | Battery %, 0-100 |
| 6 | Gear ASCII: `P`, `D`, `N`, `R` |
| 7 | Alive counter |

### Frame `0x101` - `BUTTON_STATE` (snapshot mỗi 100ms)

| Byte | Nội dung |
|---|---|
| 0 | Bitfield: bit0 left, bit1 right, bit2 beam, bit3 high beams, bit4 parked, bit5 airbag, bit6 media play, bit7 media next |
| 1 | Drive mode: `0=P`, `1=D` |
| 2 | Alive counter |
| 3-7 | Reserved |

### Frame `0x102` - `BUTTON_EVENT` (gửi ngay khi nhấn nút)

| Byte | Nội dung |
|---|---|
| 0 | Button ID: 1..8 |
| 1 | Button state: `0=OFF`, `1=ON` |
| 2 | Event counter |
| 3 | Button bitfield snapshot |
| 4 | Drive mode snapshot |
| 5-7 | Reserved |

Tên nút: `left_signal`, `right_signal`, `beam`, `high_beams`, `parked`, `airbag`, `media_play`, `media_next`

## Sơ đồ kết nối phần cứng

### Nút nhấn (x8)
```
3.3V ──┬── [Internal Pull-up]
       │
PBx ───┤
       │
       └── [Button] ── GND
```
- Trạng thái nghỉ: HIGH (pull-up)
- Nhấn nút: LOW → EXTI Falling Edge → Toggle state

### Biến trở (x2, cho Fuel & Battery)
```
3.3V ──── [Pot pin 3]
           │
PA0/PA1 ── [Pot wiper (pin 2)]
           │
GND ───── [Pot pin 1]
```
- ADC 12-bit: 0V → 0 (empty), 3.3V → 4095 (full)
- Lọc trung bình 8 mẫu để giảm nhiễu

### Rotary Encoder KY-040 (cho Speed)
```
3.3V ──── VCC
GND ───── GND
PA6 ───── CLK (A)
PA7 ───── DT  (B)
          SW  (không dùng)
```
- TIM3 Encoder Mode, đếm 2 chiều
- Xoay phải: tăng tốc, xoay trái: giảm tốc

### CAN kết nối Raspberry Pi 4 qua MCP2515
```
STM32 PA12 (CAN_TX) ─── SN65HVD230 CTX/TXD
STM32 PA11 (CAN_RX) ─── SN65HVD230 CRX/RXD
STM32 3.3V ──────────── SN65HVD230 3V3
STM32 GND ───────────── SN65HVD230 GND

SN65HVD230 CANH ─────── MCP2515 CANH
SN65HVD230 CANL ─────── MCP2515 CANL

Raspberry Pi GPIO8  CE0  ─── MCP2515 CS
Raspberry Pi GPIO9  MISO ─── MCP2515 SO
Raspberry Pi GPIO10 MOSI ─── MCP2515 SI
Raspberry Pi GPIO11 SCLK ─── MCP2515 SCK
Raspberry Pi GPIO25      ─── MCP2515 INT
Raspberry Pi 3.3V/5V     ─── MCP2515 VCC (theo module)
Raspberry Pi GND         ─── MCP2515 GND
```
- CAN bitrate: 500 kbps
- MCP2515 oscillator: 8 MHz
- Linux interface: `can0`
- UART PA9/PA10 vẫn có thể giữ làm debug/fallback, không còn là đường dữ liệu chính.

## Danh sách linh kiện

| # | Linh kiện | Số lượng | Ghi chú |
|---|-----------|---------|---------|
| 1 | STM32F103C8T6 (Blue Pill) | 1 | MCU chính |
| 2 | Rotary Encoder KY-040 | 1 | Speed control |
| 3 | Biến trở 10kΩ | 2 | Fuel + Battery level |
| 4 | Nút nhấn 4 chân | 8 | Tell-tales + Media |
| 5 | Công tắc gạt (toggle switch) | 1 | Drive mode |
| 6 | SN65HVD230 CAN transceiver | 1 | STM32 CAN_TX/RX ↔ CANH/CANL |
| 7 | MCP2515 CAN module | 1 | Raspberry Pi SPI ↔ CANH/CANL |
| 8 | Breadboard + dây jumper | - | Prototype |
| 9 | Nguồn 3.3V / USB | 1 | Cấp nguồn |

## Cấu trúc firmware

```
firmware/Core/
├── Inc/
│   ├── main.h
│   ├── gpio_handler.h      ← 8 nút + 1 switch, ánh xạ Tell-Tales
│   ├── encoder_handler.h   ← Speed encoder (TIM3)
│   ├── adc_handler.h       ← [MỚI] Fuel + Battery (ADC1)
│   ├── can_protocol.h      ← [MỚI] CAN frames gửi data cho Qt app
│   └── uart_protocol.h     ← Debug/fallback UART
├── Src/
│   ├── main.c              ← Main loop tích hợp tất cả module
│   ├── gpio_handler.c      ← Cập nhật: 8 buttons thay vì 6
│   ├── encoder_handler.c   ← Giữ nguyên
│   ├── adc_handler.c       ← [MỚI] Đọc ADC với lọc trung bình
│   ├── can_protocol.c      ← [MỚI] Giao thức CAN 0x100/0x101/0x102
│   └── uart_protocol.c     ← Debug/fallback UART
```

## Cấu trúc Qt Software (phía nhận)

```
software/QtInstrumentCluster/
├── src/
│   ├── canreceiver.h/cpp     ← [MỚI] Nhận Raw SocketCAN can0, parse 0x100/0x101/0x102
│   ├── serialreceiver.h/cpp  ← UART fallback/debug
│   ├── mainmodel.h/cpp       ← Cập nhật: thêm fuelLevel, batteryLevel, gearText
│   └── ...
├── models/
│   ├── MainModel.qml         ← Cập nhật: modelUpdated() nhận fuel/batt/gear
│   └── ...
├── view/
│   ├── NormalMode.qml         ← Cập nhật: gear hiển thị từ gearShiftText
│   └── ...
├── main.cpp                   ← Cập nhật: khởi tạo SerialReceiver
└── main.qml                   ← Cập nhật: Connections{} binding HW → QML models
```

## Kiến trúc hệ thống CAN: STM32 → Raspberry Pi → Qt

```
┌─────────────────────────────────────────────────────────┐
│  GIAI ĐOẠN 1: Phát triển trên PC Host                   │
│                                                         │
│  STM32 ──(CAN)──→ USB/CAN hoặc vcan0 test frame        │
│                                        │                │
│                                  Qt Dashboard App       │
│                                  CanReceiver            │
│                                  IVI_CAN_IFACE=vcan0    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  GIAI ĐOẠN 2: Deploy trên Raspberry Pi                   │
│                                                         │
│  STM32 PA12/PA11 ─→ SN65HVD230 ─→ CANH/CANL             │
│  CANH/CANL ─→ MCP2515 ─→ SPI Raspberry Pi 4             │
│  Linux SocketCAN: can0, 500 kbps                         │
│                                        │                │
│                                  Qt Dashboard App       │
│                                  CanReceiver            │
│                                  UART fallback optional │
│                                                         │
│  *** Qt ưu tiên CAN, UART chỉ dùng debug/fallback ***   │
└─────────────────────────────────────────────────────────┘
```

### Khi chuyển sang Raspberry Pi, chỉ cần:

1. **Cross-compile Qt app** cho ARM (hoặc build trực tiếp trên Pi)
2. **Nối dây CAN + SPI** theo sơ đồ SN65HVD230/MCP2515 ở trên.
3. **Cấu hình MCP2515 SocketCAN**:
   - `./scripts/pi/setup_socketcan_mcp2515.sh`
   - reboot Raspberry Pi
4. **Kiểm tra CAN**:
   - `ip -details link show can0`
   - `candump can0`
5. **Chạy app**: `./scripts/pi/run_pi_qt5.sh` — `CanReceiver` mở `can0` mặc định.
