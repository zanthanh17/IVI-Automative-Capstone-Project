# Báo cáo CAN Bus STM32 - Body ECU - Raspberry Pi - Qt Instrument Cluster

## 1. Mục tiêu

Tài liệu này mô tả triển khai CAN bus trong hệ thống IVI Automotive sau khi bổ sung Body ECU trong project `cp/`. Bus CAN là đường truyền chính giữa STM32 đọc input, STM32 Body điều khiển tải và Raspberry Pi chạy giao diện Qt.

Mục tiêu tích hợp:

- Firmware STM32 gửi telemetry, trạng thái nút/switch và event điều khiển qua CAN.
- Body ECU nhận lệnh CAN để điều khiển xi nhan, đèn thường, đèn pha và còi.
- Qt Instrument Cluster đọc cùng bus CAN để cập nhật dashboard và theo dõi trạng thái Body.
- UART vẫn giữ làm kênh debug/fallback cho firmware nguồn input.

## 2. Kiến trúc hệ thống

```text
Nút / switch / encoder / ADC
        |
        v
STM32 firmware ECU
  CAN1 PA12/PA11
        |
        v
CANH/CANL 500 kbps
   |              |
   |              +--> STM32 Body ECU -> PA0..PA4 -> driver tải
   |
   +--> MCP2515 -> Raspberry Pi can0 -> QtInstrumentCluster
```

Thông số CAN chung:

| Hạng mục | Giá trị |
|---|---|
| Bitrate | 500 kbps |
| Frame | Standard ID 11-bit |
| Payload | 8 byte |
| STM32 CAN | bxCAN `PA11/PA12` |
| Qt access | Linux Raw SocketCAN |
| Pi interface | `can0` |

## 3. Phần cứng CAN

Mỗi STM32F103 có bxCAN controller nhưng cần transceiver ngoài để tạo tín hiệu vi sai. Kết nối cơ bản:

```text
STM32 PA12 CAN_TX -> Transceiver TXD/CTX
STM32 PA11 CAN_RX -> Transceiver RXD/CRX
STM32 GND         -> Transceiver GND -> GND bus chung
Transceiver CANH  -> CANH bus
Transceiver CANL  -> CANL bus
```

Raspberry Pi dùng MCP2515 qua SPI:

```text
MCP2515 CS  -> GPIO8 CE0
MCP2515 SO  -> GPIO9 MISO
MCP2515 SI  -> GPIO10 MOSI
MCP2515 SCK -> GPIO11 SCLK
MCP2515 INT -> GPIO25
```

Lưu ý kiểm tra vật lý:

- Hai đầu bus có điện trở 120 ohm; đo `CANH-CANL` khi tắt nguồn thường khoảng 60 ohm.
- Các node phải có GND chung.
- MCP2515 phải cấu hình đúng oscillator 8 MHz hoặc 16 MHz theo module thực tế.

## 4. Cấu hình phần mềm Raspberry Pi

Kích hoạt MCP2515 trong boot config:

```text
dtparam=spi=on
dtoverlay=mcp2515-can0,oscillator=8000000,interrupt=25,spimaxfrequency=10000000
```

Đưa interface CAN lên:

```bash
sudo ip link set can0 down
sudo ip link set can0 up type can bitrate 500000 restart-ms 100
ip -details -statistics link show can0
```

Quan sát bus:

```bash
candump -tz -x -e can0
```

Trạng thái tốt: `can state ERROR-ACTIVE`, RX/TX packet tăng, không tăng `bus-off` trong lúc chạy ổn định.

## 5. CAN frame map

### 5.1. `0x100` - Vehicle telemetry

Nguồn phát: firmware ECU. Node nhận chính: Qt. Body ECU bỏ qua frame này.

| Byte | Ý nghĩa |
|---|---|
| B0-B1 | Speed km/h, `uint16` big-endian |
| B2-B3 | RPM, `uint16` big-endian |
| B4 | Fuel percent `0..100` |
| B5 | Battery percent `0..100` |
| B6 | Gear ASCII `P/D/N/R` |
| B7 | Alive counter |

Ví dụ:

```text
100 [8] 00 C8 1B 58 21 27 50 FD
```

Giải mã: speed 200 km/h, rpm 7000, fuel 33%, battery 39%, gear `P`.

### 5.2. `0x101` - Control snapshot

Nguồn phát: firmware ECU mỗi 100 ms. Node nhận: Body ECU và Qt.

| Byte | Ý nghĩa |
|---|---|
| B0 | Command/button mask |
| B1 | Drive mode, `0=P`, `1=D` |
| B2 | Snapshot counter |
| B3-B7 | Reserved |

Command mask:

| Bit | Ý nghĩa |
|---|---|
| bit0 | Left signal |
| bit1 | Right signal |
| bit2 | Beam / đèn thường |
| bit3 | High beams / đèn pha |
| bit4 | Parked |
| bit5 | Airbag |
| bit6 | Horn / còi |
| bit7 | Reserved |

Ví dụ:

```text
101 [8] 45 00 12 00 00 00 00 00
```

`0x45 = bit0 + bit2 + bit6`: xi nhan trái, đèn thường và còi đang active.

### 5.3. `0x102` - Control event

Nguồn phát: firmware ECU khi có event nút. Node nhận: Body ECU và Qt.

| Byte | Ý nghĩa |
|---|---|
| B0 | Button ID |
| B1 | Button state, `0=OFF`, `1=ON` |
| B2 | Event counter |
| B3 | Command mask tại thời điểm event |
| B4 | Drive mode |
| B5-B7 | Reserved |

Button ID:

| ID | Tên |
|---|---|
| 1 | `left_signal` |
| 2 | `right_signal` |
| 5 | `parked` |
| 6 | `airbag` |
| 7 | `horn` |

Ví dụ nhấn còi:

```text
102 [8] 07 01 33 40 00 00 00 00
```

ID 7 state ON, command mask `0x40` nghĩa là còi đang active. Khi nhả còi, firmware gửi:

```text
102 [8] 07 00 34 00 00 00 00 00
```

### 5.4. `0x201` - Body status

Nguồn phát: Body ECU mỗi 200 ms. Node nhận: Qt/candump/debug.

| Byte | Ý nghĩa |
|---|---|
| B0 | Command mask hiện Body đang dùng |
| B1 | Physical output mask sau xử lý blink/fail-safe |
| B2 | Flags |
| B3 | Body alive counter |
| B4-B7 | Reserved |

Flags `B2`:

| Bit | Ý nghĩa |
|---|---|
| bit0 | CAN ready |
| bit1 | RX timeout, Body không nhận `0x101/0x102` quá 500 ms |
| bit2 | CAN error |

Ví dụ Body chạy bình thường:

```text
201 [8] 45 45 01 6A 00 00 00 00
```

Body đang nhận command `0x45`, output vật lý cũng `0x45`, CAN ready, chưa timeout.

Ví dụ khi mất firmware command quá 500 ms:

```text
201 [8] 00 00 03 6B 00 00 00 00
```

Flags `0x03 = CAN ready + RX timeout`; Body đã tắt toàn bộ tải.

## 6. Logic Body ECU

- Body nhận `0x101` để đồng bộ snapshot định kỳ.
- Body nhận `0x102` để phản ứng nhanh với event, đặc biệt còi ON/OFF.
- Xi nhan trái/phải blink 500 ms trong Body ECU.
- Đèn thường, đèn pha và còi bám trực tiếp command mask.
- Nếu không nhận `0x101/0x102` trong 500 ms, Body tắt toàn bộ output và báo timeout trong `0x201`.
- `PC13` trên Body nhấp nháy 500 ms để báo main loop còn chạy.

## 7. Kiểm thử

### 7.1. Kiểm tra bus

```bash
sudo ip link set can0 up type can bitrate 500000 restart-ms 100
ip -details -statistics link show can0
candump -tz -x -e can0
```

Kỳ vọng thấy `0x100`, `0x101`, `0x102` từ firmware và `0x201` từ Body.

### 7.2. Kiểm tra còi

Nhấn giữ PB9 trên firmware ECU:

```text
102 [8] 07 01 .. 40 00 00 00 00
101 [8] 40 ..
201 [8] 40 40 01 ..
```

Nhả PB9:

```text
102 [8] 07 00 .. 00 00 00 00 00
201 [8] 00 00 01 ..
```

Nếu `PA4` Body không đổi theo, kiểm tra driver tải, GND chung, transceiver và `0x201` flags.

### 7.3. Kiểm tra xi nhan

Gạt cần xi nhan để PB5 hoặc PB6 xuống LOW. `0x101` giữ bit0/bit1 active khi cần đang gạt, còn `0x201` byte B1 sẽ nhấp nháy theo chu kỳ Body 500 ms. Trả cần về neutral thì firmware gửi OFF và `0x101` clear bit tương ứng.

### 7.4. Kiểm tra fail-safe

Tắt firmware ECU hoặc tháo CAN của firmware. Sau tối đa 500 ms:

- `PA0..PA4` Body phải OFF.
- `0x201` flags có bit1 timeout.

## 8. Lỗi thường gặp

| Hiện tượng | Nguyên nhân thường gặp | Cách kiểm tra |
|---|---|---|
| Firmware báo ACK error/no mailbox | Không có node ACK, `can0` chưa lên, dây/termination sai | `ip -details link`, đo `CANH-CANL`, kiểm tra GND |
| Không thấy `0x201` | Body chưa init CAN hoặc không có nguồn/transceiver | Kiểm tra `PC13`, CAN RX0 IRQ, Body `g_body_can_dbg` |
| Còi bị giữ ON | PB9 chưa bắt rising edge hoặc relay active-low chưa đảo macro | Kiểm tra `0x102` release và `BODY_LOAD_ACTIVE_HIGH` |
| Qt vẫn điều khiển media khi nhấn PB9 | Parser cũ còn map ID7 thành `media_play` | Cập nhật `CanReceiver`/`SerialReceiver` |

## 9. Kết luận

CAN bus hiện không chỉ truyền telemetry lên dashboard mà còn là mạng điều khiển tải giữa các ECU. Firmware ECU phát command snapshot/event, Body ECU thực thi output và phát status `0x201`, Qt đọc cùng bus để hiển thị và debug. Cấu trúc này đúng hơn với mô hình nhiều ECU trong xe và tách rõ input ECU, body/load ECU và instrument cluster.
