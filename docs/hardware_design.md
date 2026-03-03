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
    UART TX ─────┤ PA9  (USART1_TX) │──── → Raspberry Pi RX
    UART RX ─────┤ PA10 (USART1_RX) │──── ← Raspberry Pi TX
                  │ PA11             │
                  │ PA12             │
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

## Giao thức UART (115200 baud, 8N1)

### Frame dữ liệu cảm biến (gửi mỗi 100ms):
```
DATA:speed=<0-200>,rpm=<0-7000>,fuel=<0-100>,batt=<0-100>,gear=<P|D>\n
```

### Frame sự kiện nút nhấn (gửi khi có thay đổi):
```
BTN:<name>=<ON|OFF>\n
```

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

### UART kết nối Raspberry Pi
```
STM32 PA9  (TX) ──── Raspberry Pi RX (GPIO15)
STM32 PA10 (RX) ──── Raspberry Pi TX (GPIO14)
GND ──────────────── GND
```
- Baud: 115200, 8 data bits, No parity, 1 stop bit

## Danh sách linh kiện

| # | Linh kiện | Số lượng | Ghi chú |
|---|-----------|---------|---------|
| 1 | STM32F103C8T6 (Blue Pill) | 1 | MCU chính |
| 2 | Rotary Encoder KY-040 | 1 | Speed control |
| 3 | Biến trở 10kΩ | 2 | Fuel + Battery level |
| 4 | Nút nhấn 4 chân | 8 | Tell-tales + Media |
| 5 | Công tắc gạt (toggle switch) | 1 | Drive mode |
| 6 | USB-TTL (CP2102/CH340) | 1 | UART ↔ Raspberry Pi |
| 7 | Breadboard + dây jumper | - | Prototype |
| 8 | Nguồn 3.3V / USB | 1 | Cấp nguồn |

## Cấu trúc firmware

```
firmware/Core/
├── Inc/
│   ├── main.h
│   ├── gpio_handler.h      ← 8 nút + 1 switch, ánh xạ Tell-Tales
│   ├── encoder_handler.h   ← Speed encoder (TIM3)
│   ├── adc_handler.h       ← [MỚI] Fuel + Battery (ADC1)
│   └── uart_protocol.h     ← [MỚI] Protocol gửi data cho Qt app
├── Src/
│   ├── main.c              ← Main loop tích hợp tất cả module
│   ├── gpio_handler.c      ← Cập nhật: 8 buttons thay vì 6
│   ├── encoder_handler.c   ← Giữ nguyên
│   ├── adc_handler.c       ← [MỚI] Đọc ADC với lọc trung bình
│   └── uart_protocol.c     ← [MỚI] Giao thức UART có cấu trúc
```

## Cấu trúc Qt Software (phía nhận)

```
software/QtInstrumentCluster/
├── src/
│   ├── serialreceiver.h/cpp  ← [MỚI] Nhận UART, parse DATA/BTN frames
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

## Kiến trúc hệ thống: PC Host → Raspberry Pi

```
┌─────────────────────────────────────────────────────────┐
│  GIAI ĐOẠN 1: Phát triển trên PC Host                   │
│                                                         │
│  STM32 ──(UART)──→ USB-TTL ──(USB)──→ PC (COMx)        │
│                                        │                │
│                                  Qt Dashboard App       │
│                                  SerialReceiver          │
│                                  auto-detect: COMx      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  GIAI ĐOẠN 2: Deploy trên Raspberry Pi                   │
│                                                         │
│  STM32 ──(UART trực tiếp)──→ Pi /dev/ttyAMA0            │
│   PA9 TX ─────────────────→ GPIO15 RX                   │
│   PA10 RX ←────────────────── GPIO14 TX                 │
│   GND ──────────────────── GND                          │
│                                        │                │
│                                  Qt Dashboard App       │
│                                  SerialReceiver          │
│                                  auto-detect: ttyAMA0   │
│                                                         │
│  *** CODE KHÔNG THAY ĐỔI - chỉ khác platform ***       │
└─────────────────────────────────────────────────────────┘
```

### Khi chuyển sang Raspberry Pi, chỉ cần:

1. **Cross-compile Qt app** cho ARM (hoặc build trực tiếp trên Pi)
2. **Nối dây UART trực tiếp** (không cần USB-TTL):
   - STM32 PA9 (TX) → Pi GPIO15 (RX)
   - STM32 PA10 (RX) → Pi GPIO14 (TX)
   - GND → GND
3. **Bật UART trên Pi**: `sudo raspi-config` → Interface → Serial
4. **Chạy app**: `./QtInstrumentCluster` — SerialReceiver tự detect `/dev/ttyAMA0`
5. **KHÔNG cần sửa code** — `autoConnect()` tự tìm đúng port
