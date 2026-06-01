# Thiết kế phần cứng IVI Automotive - STM32 CAN và Body ECU

## Tổng quan node

Hệ thống dùng chung một bus CAN 500 kbps giữa ba node chính:

| Node | Vai trò | Giao tiếp |
|---|---|---|
| `firmware/` STM32F103 | Đọc nút, switch, encoder, ADC và phát lệnh/trạng thái lên CAN | bxCAN `PA11/PA12` |
| `cp/` STM32F103 | Nhận lệnh CAN và điều khiển tải: xi nhan, đèn thường, đèn pha, còi | bxCAN `PA11/PA12` |
| Raspberry Pi / Qt | Chạy `QtInstrumentCluster`, đọc telemetry và trạng thái Body qua SocketCAN | MCP2515 `can0` |

Tất cả node dùng CAN standard 11-bit, DLC 8 byte, bitrate 500 kbps. STM32 chỉ xuất tín hiệu logic CAN nên mỗi board STM32 cần một transceiver như SN65HVD230 hoặc module TJA1050 tương thích mức 3.3 V/5 V theo phần cứng thực tế.

## Firmware ECU - input mapping

Nguồn đối chiếu: [`firmware/IVI Automative CP.ioc`](../firmware/IVI%20Automative%20CP.ioc).

| Chức năng | Pin STM32 | Cấu hình | Logic |
|---|---|---|---|
| Cần xi nhan trái | `PB5` | `GPIO_EXTI5` rising/falling, pull-up | Gạt trái = LOW/ON, trả neutral = HIGH/OFF |
| Cần xi nhan phải | `PB6` | `GPIO_EXTI6` rising/falling, pull-up | Gạt phải = LOW/ON, trả neutral = HIGH/OFF |
| Nút Parked / phanh tay | `PB7` | `GPIO_EXTI7`, pull-up | Nhấn = LOW, toggle state |
| Nút Airbag | `PB8` | `GPIO_EXTI8`, pull-up | Nhấn = LOW, toggle state |
| Nút còi | `PB9` | `GPIO_EXTI9` rising/falling, pull-up | Giữ = LOW/ON, nhả = HIGH/OFF |
| Switch đèn thường | `PA4` | `GPIO_Input`, pull-up | Gạt ON = LOW |
| Switch đèn pha | `PA5` | `GPIO_Input`, pull-up | Gạt ON = LOW |
| Encoder CLK/A | `PA6` | `TIM3_CH1` | Speed input |
| Encoder DT/B | `PA7` | `TIM3_CH2` | Speed input |
| UART debug TX/RX | `PA9/PA10` | `USART1` 115200 | Debug/fallback |
| CAN RX/TX | `PA11/PA12` | `CAN1_RX/TX` | SN65HVD230/TJA1050 |
| SWDIO/SWCLK | `PA13/PA14` | Serial Wire | ST-Link |

PB5/PB6 là tiếp điểm cần gạt xi nhan nên firmware bám theo mức chân: LOW là ON, HIGH là OFF. PB7/PB8 vẫn là nút toggle vì chúng đại diện trạng thái duy trì. PB9 là còi nên xử lý momentary: firmware gửi event ON khi nhấn và OFF khi nhả, đồng thời bit6 trong snapshot `0x101` phản ánh trạng thái hiện tại.

## Body ECU - output mapping

Nguồn đối chiếu: [`cp/cp.ioc`](../cp/cp.ioc).

| Tải | Pin STM32 Body | Cấu hình | Logic mặc định |
|---|---|---|---|
| Xi nhan trái | `PA0` | GPIO output push-pull | Active high |
| Xi nhan phải | `PA1` | GPIO output push-pull | Active high |
| Đèn thường | `PA2` | GPIO output push-pull | Active high |
| Đèn pha | `PA3` | GPIO output push-pull | Active high |
| Còi | `PA4` | GPIO output push-pull | Active high |
| CAN RX/TX | `PA11/PA12` | `CAN1_RX/TX` | SN65HVD230/TJA1050 |
| Heartbeat debug | `PC13` | GPIO output | LED onboard |
| SWDIO/SWCLK | `PA13/PA14` | Serial Wire | ST-Link |

Lưu ý an toàn: STM32 GPIO không được kéo tải trực tiếp. `PA0..PA4` phải đi qua transistor, MOSFET driver hoặc module relay có diode/biện pháp chống xung ngược phù hợp. Nếu relay module active-low, đổi `BODY_LOAD_ACTIVE_HIGH` trong [`cp/Core/Inc/body_loads.h`](../cp/Core/Inc/body_loads.h) từ `1U` sang `0U`.

## Đấu nút và switch firmware

```text
PB5/PB6  ───┬── [Tiếp điểm cần xi nhan] ── GND
PB7..PB9 ───┬── [Nút nhấn] ───────────── GND
            │
            └── Pull-up nội 3.3V

PA4/PA5  ───┬── [Switch] ── GND
            │
            └── Pull-up nội 3.3V
```

- Trạng thái nghỉ: HIGH.
- Nhấn/gạt ON: LOW.
- PB5/PB6 và PB9 cần bắt cả cạnh xuống/cạnh lên để OFF ngay khi trả cần hoặc nhả còi.

## Đấu tải Body ECU

```text
STM32 Body PA0 ── Driver ── Xi nhan trái
STM32 Body PA1 ── Driver ── Xi nhan phải
STM32 Body PA2 ── Driver ── Đèn thường
STM32 Body PA3 ── Driver ── Đèn pha
STM32 Body PA4 ── Driver ── Còi
```

Xi nhan trái/phải blink trong Body ECU với chu kỳ 500 ms. Đèn thường, đèn pha và còi bám trực tiếp theo command mask nhận từ CAN.

## Đấu CAN bus

Mỗi STM32 dùng `PA12` làm CAN TX và `PA11` làm CAN RX:

```text
STM32 PA12 (CAN_TX) ─── Transceiver TXD/CTX
STM32 PA11 (CAN_RX) ─── Transceiver RXD/CRX
STM32 3.3V/GND ──────── Transceiver VCC/GND

Transceiver CANH ────── CANH bus ────── MCP2515 CANH
Transceiver CANL ────── CANL bus ────── MCP2515 CANL
GND các node ────────── nối chung
```

- Hai đầu xa nhất của bus cần điện trở kết thúc 120 ohm giữa `CANH` và `CANL`.
- Khi tắt nguồn và đo giữa `CANH-CANL`, bus có hai điện trở kết thúc đúng thường khoảng 60 ohm.
- Không đảo `CANH/CANL`; đảo dây sẽ làm node không ACK frame.

## CAN command bitfield

Frame `0x101` byte `B0` và frame `0x102` byte `B3` dùng cùng bit layout:

| Bit | Nguồn firmware | Ý nghĩa Body/Qt |
|---|---|---|
| bit0 | `PB5` | Left signal |
| bit1 | `PB6` | Right signal |
| bit2 | `PA4` | Beam / đèn thường |
| bit3 | `PA5` | High beams / đèn pha |
| bit4 | `PB7` | Parked |
| bit5 | `PB8` | Airbag |
| bit6 | `PB9` | Horn / còi |
| bit7 | - | Reserved |

Frame `0x102` button event gửi cho các nút có event:

| Button ID | Pin | Tên |
|---|---|---|
| 1 | `PB5` | `left_signal` |
| 2 | `PB6` | `right_signal` |
| 5 | `PB7` | `parked` |
| 6 | `PB8` | `airbag` |
| 7 | `PB9` | `horn` |

`beam` và `high_beams` là switch trạng thái nên đi qua snapshot `0x101`; không cần event riêng.
