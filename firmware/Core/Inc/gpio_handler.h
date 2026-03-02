/**
 * @file    gpio_handler.h
 * @brief   GPIO Handler - Nút nhấn (EXTI interrupt) + Công tắc gạt (polling)
 * @note    PB1-PB6: 6 nút nhấn qua EXTI với debounce
 *          PA8, PA9: 2 công tắc gạt đọc polling
 */

#ifndef GPIO_HANDLER_H
#define GPIO_HANDLER_H

#include "stm32f1xx_hal.h"

/* ============ Cấu hình debounce ============ */
#define DEBOUNCE_DELAY_MS   50   /* Thời gian debounce (ms) */

/* ============ Struct trạng thái các nút/công tắc ============ */
typedef struct {
    /* Nút nhấn - toggle qua interrupt (0 = OFF, 1 = ON) */
    uint8_t left_signal;    /* Xi nhan trái   (PB1) */
    uint8_t right_signal;   /* Xi nhan phải   (PB2) */
    uint8_t headlight;      /* Đèn pha        (PB3) */
    uint8_t horn;           /* Còi            (PB4) */
    uint8_t door_open;      /* Cửa mở         (PB5) */
    uint8_t seatbelt;       /* Dây an toàn    (PB6) */
} VehicleButtons_t;

/* ============ Biến global ============ */
extern VehicleButtons_t g_buttons;
extern volatile uint8_t g_button_last_id_dbg;
extern volatile uint8_t g_button_last_state_dbg;
extern volatile uint8_t g_button_event_pending_dbg;

/* ============ API ============ */

/**
 * @brief  Khởi tạo GPIO handler, reset trạng thái buttons
 */
void GPIO_Handler_Init(void);
uint8_t GPIO_Handler_PopButtonEvent(uint8_t *button_id, uint8_t *button_state);

#endif /* GPIO_HANDLER_H */
