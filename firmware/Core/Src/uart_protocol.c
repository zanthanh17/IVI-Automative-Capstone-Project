/**
 * @file    uart_protocol.c
 * @brief   UART Protocol implementation
 *          Giao thức truyền dữ liệu có cấu trúc từ STM32 → Dashboard Qt
 */

#include "uart_protocol.h"
#include "gpio_handler.h"
#include <stdio.h>
#include <string.h>

/* ============ Bảng tên nút ============ */
static const char *ButtonName(uint8_t id)
{
    switch (id) {
        case BTN_ID_LEFT_SIGNAL:  return "left_signal";
        case BTN_ID_RIGHT_SIGNAL: return "right_signal";
        case BTN_ID_BEAM:         return "beam";
        case BTN_ID_HIGH_BEAMS:   return "high_beams";
        case BTN_ID_PARKED:       return "parked";
        case BTN_ID_AIRBAG:       return "airbag";
        case BTN_ID_MEDIA_PLAY:   return "media_play";
        case BTN_ID_MEDIA_NEXT:   return "media_next";
        default:                  return "unknown";
    }
}

/* ============ API ============ */

void UART_Protocol_Init(void)
{
    const char *boot_msg = "\r\n=== IVI Automotive CP v2.0 ===\r\n"
                           "Protocol: DATA:<key>=<val>,...\\n | BTN:<name>=<state>\\n\r\n";
    HAL_UART_Transmit(&huart1, (uint8_t *)boot_msg, strlen(boot_msg), 100);
}

void UART_Protocol_SendData(uint16_t speed_kmh, uint16_t rpm,
                             float fuel_percent, float batt_percent,
                             char gear)
{
    char buf[UART_TX_BUFFER_SIZE];

    /* Chuyển float → int phần trăm (0-100) để truyền nhẹ hơn */
    uint8_t fuel_pct = (uint8_t)(fuel_percent * 100.0f);
    uint8_t batt_pct = (uint8_t)(batt_percent * 100.0f);

    int n = snprintf(buf, sizeof(buf),
        "DATA:speed=%u,rpm=%u,fuel=%u,batt=%u,gear=%c\n",
        (unsigned)speed_kmh,
        (unsigned)rpm,
        (unsigned)fuel_pct,
        (unsigned)batt_pct,
        gear
    );

    if (n > 0) {
        HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 30);
    }
}

void UART_Protocol_SendButtonEvent(uint8_t button_id, uint8_t button_state)
{
    char buf[64];

    int n = snprintf(buf, sizeof(buf),
        "BTN:%s=%s\n",
        ButtonName(button_id),
        (button_state != 0U) ? "ON" : "OFF"
    );

    if (n > 0) {
        HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 30);
    }
}
