/**
 * @file    uart_protocol.h
 * @brief   UART Protocol - Giao thức truyền dữ liệu STM32 → Dashboard (Qt)
 * @note    Giao thức text-based, dễ debug qua terminal
 *
 *          Format gửi định kỳ (mỗi 100ms):
 *          "DATA:speed=<0-200>,rpm=<0-7000>,fuel=<0-100>,batt=<0-100>,gear=<P|D>\n"
 *
 *          Format sự kiện nút nhấn (khi có thay đổi):
 *          "BTN:<name>=<ON|OFF>\n"
 *
 *          Tên nút ánh xạ Dashboard:
 *          left_signal  → TellTalesModel.turnLeftActive
 *          right_signal → TellTalesModel.turnRightActive
 *          beam         → TellTalesModel.beamActive
 *          high_beams   → TellTalesModel.highBeamsActive
 *          parked       → TellTalesModel.parkedActive
 *          airbag       → TellTalesModel.airbagActive
 *          horn         -> Body ECU horn load
 */

#ifndef UART_PROTOCOL_H
#define UART_PROTOCOL_H

#include "stm32f1xx_hal.h"

/* ============ Cấu hình ============ */
#define UART_TX_BUFFER_SIZE   256U
#define UART_DATA_INTERVAL_MS 100U   /* Gửi DATA frame mỗi 100ms */

/* ============ Cần khai báo extern từ main.c ============ */
extern UART_HandleTypeDef huart1;

/* ============ API ============ */

/**
 * @brief  Khởi tạo protocol, gửi boot message
 */
void UART_Protocol_Init(void);

/**
 * @brief  Gửi frame dữ liệu cảm biến định kỳ
 * @param  speed_kmh     Tốc độ (0-200)
 * @param  rpm           Vòng tua (0-7000)
 * @param  fuel_percent  Mức nhiên liệu (0.0-1.0)
 * @param  batt_percent  Mức pin (0.0-1.0)
 * @param  gear          Gear character: 'P', 'D', 'R', 'N'
 */
void UART_Protocol_SendData(uint16_t speed_kmh, uint16_t rpm,
                             float fuel_percent, float batt_percent,
                             char gear);

/**
 * @brief  Gửi sự kiện nút nhấn
 * @param  button_id     ID nút (BTN_ID_xxx từ gpio_handler.h)
 * @param  button_state  Trạng thái (0=OFF, 1=ON)
 */
void UART_Protocol_SendButtonEvent(uint8_t button_id, uint8_t button_state);

#endif /* UART_PROTOCOL_H */
