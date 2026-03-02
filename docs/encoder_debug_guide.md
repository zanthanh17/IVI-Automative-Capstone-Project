# Encoder Debug Guide (STM32F103 + TIM3)

## 1. Wiring
- `PA6` <- Encoder `A` / `CLK`
- `PA7` <- Encoder `B` / `DT`
- `3V3` -> Encoder `VCC`
- `GND` <-> Encoder `GND`
- Keep ST-Link on SWD (`PA13/PA14`, `NRST`, `GND`)

Notes:
- Use 3.3V logic.
- If encoder board has no pull-up, add 10k pull-up on `PA6`, `PA7`.

## 2. Debugger Watch (no UART required)
Run debug, then add these expressions:
- `g_encoder.delta`
- `g_encoder.speed_kmh`
- `g_encoder_cnt_dbg`
- `g_encoder_last_count_dbg`
- `g_encoder_update_count_dbg`
- `htim3.Instance->CNT`

Expected:
- Rotate CW: `delta > 0`, `CNT` increases, `speed_kmh` increases.
- Rotate CCW: `delta < 0`, `CNT` decreases, `speed_kmh` decreases.
- `speed_kmh` saturates in `[0..200]`.

## 3. Optional UART log
`main.c` has an optional logger:
- `ENCODER_UART_LOG_ENABLE` (default `0`)
- `ENCODER_UART_LOG_MS` (default `100`)

To enable text log:
1. Set `ENCODER_UART_LOG_ENABLE` to `1`.
2. Connect USB-UART:
- `PA9` (MCU TX) -> USB-UART RX
- `PA10` (MCU RX) <- USB-UART TX
- `GND` common
3. Open terminal `115200 8N1`.

Log format:
- `cnt=<...> delta=<...> speed=<...> updates=<...>`
