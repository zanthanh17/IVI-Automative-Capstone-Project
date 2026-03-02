/**
 * @file    gpio_handler.c
 * @brief   GPIO Handler implementation
 *          - 6 nút nhấn PB1-PB6: toggle qua EXTI interrupt + debounce riêng từng nút
 *          - 2 công tắc gạt PA8, PA9: polling trong main loop
 */

#include "gpio_handler.h"
#include <string.h>

/* ============ Biến global ============ */
VehicleButtons_t g_buttons = {0};
volatile uint8_t g_button_last_id_dbg = 0;
volatile uint8_t g_button_last_state_dbg = 0;
volatile uint8_t g_button_event_pending_dbg = 0;

/* ============ Biến debounce nội bộ ============ */
static uint32_t last_exti_tick[7] = {0};  /* Index 1-6 cho PB1-PB6 */

/* ============ API ============ */

void GPIO_Handler_Init(void)
{
    /* GPIO pins đã được cấu hình bởi MX_GPIO_Init() (CubeMX generated) */
    /* Reset trạng thái tất cả nút nhấn */
    memset(&g_buttons, 0, sizeof(VehicleButtons_t));
    memset(last_exti_tick, 0, sizeof(last_exti_tick));
    g_button_last_id_dbg = 0;
    g_button_last_state_dbg = 0;
    g_button_event_pending_dbg = 0;
}

uint8_t GPIO_Handler_PopButtonEvent(uint8_t *button_id, uint8_t *button_state)
{
    if (g_button_event_pending_dbg == 0U) {
        return 0U;
    }

    if (button_id != NULL) {
        *button_id = g_button_last_id_dbg;
    }
    if (button_state != NULL) {
        *button_state = g_button_last_state_dbg;
    }

    g_button_event_pending_dbg = 0U;
    return 1U;
}

/* ============ EXTI Callback (HAL weak override) ============ */

/**
 * @brief  Callback khi có EXTI interrupt từ nút nhấn PB1-PB6
 * @note   Mỗi nút có bộ đếm debounce riêng (50ms) để tránh rung
 *         Logic toggle: nhấn lần 1 = ON, nhấn lần 2 = OFF
 * @param  GPIO_Pin: Pin gây ra interrupt (GPIO_PIN_1 đến GPIO_PIN_6)
 */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    uint32_t now = HAL_GetTick();
    uint8_t idx;

    /* Xác định index debounce theo pin */
    switch (GPIO_Pin) {
        case GPIO_PIN_1: idx = 1; break;  /* PB1 - Xi nhan trái  */
        case GPIO_PIN_2: idx = 2; break;  /* PB2 - Xi nhan phải  */
        case GPIO_PIN_3: idx = 3; break;  /* PB3 - Đèn pha       */
        case GPIO_PIN_4: idx = 4; break;  /* PB4 - Còi           */
        case GPIO_PIN_5: idx = 5; break;  /* PB5 - Cửa mở        */
        case GPIO_PIN_6: idx = 6; break;  /* PB6 - Dây an toàn   */
        default: return;  /* Pin không xử lý */
    }

    /* Debounce: bỏ qua nếu < 50ms kể từ lần nhấn trước của nút này */
    if (now - last_exti_tick[idx] < DEBOUNCE_DELAY_MS) return;
    last_exti_tick[idx] = now;

    /* Toggle trạng thái tương ứng */
    switch (idx) {
        case 1: g_buttons.left_signal  ^= 1; break;
        case 2: g_buttons.right_signal ^= 1; break;
        case 3: g_buttons.headlight    ^= 1; break;
        case 4: g_buttons.horn         ^= 1; break;
        case 5: g_buttons.door_open    ^= 1; break;
        case 6: g_buttons.seatbelt     ^= 1; break;
    }

    g_button_last_id_dbg = idx;
    switch (idx) {
        case 1: g_button_last_state_dbg = g_buttons.left_signal; break;
        case 2: g_button_last_state_dbg = g_buttons.right_signal; break;
        case 3: g_button_last_state_dbg = g_buttons.headlight; break;
        case 4: g_button_last_state_dbg = g_buttons.horn; break;
        case 5: g_button_last_state_dbg = g_buttons.door_open; break;
        case 6: g_button_last_state_dbg = g_buttons.seatbelt; break;
        default: g_button_last_state_dbg = 0; break;
    }
    g_button_event_pending_dbg = 1U;
}
