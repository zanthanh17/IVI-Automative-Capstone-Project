/**
 * @file    gpio_handler.c
 * @brief   GPIO Handler implementation
 *          - 8 nút nhấn PB1-PB8: toggle qua EXTI interrupt + debounce riêng từng nút
 *          - 1 công tắc gạt PA8: polling trong main loop
 *
 *          Ánh xạ đầy đủ với Dashboard UI:
 *          PB1 → Turn Left        PB5 → Parked
 *          PB2 → Turn Right       PB6 → Airbag
 *          PB3 → Beam             PB7 → Media Play/Pause
 *          PB4 → High Beams       PB8 → Media Next
 *          PA8 → Drive Mode (polling)
 */

#include "gpio_handler.h"
#include <string.h>

/* ============ Biến global ============ */
VehicleButtons_t g_buttons = {0};
volatile uint8_t g_button_last_id_dbg = 0;
volatile uint8_t g_button_last_state_dbg = 0;
volatile uint8_t g_button_event_pending_dbg = 0;

/* ============ Biến debounce nội bộ ============ */
static uint32_t last_exti_tick[BTN_ID_COUNT] = {0};  /* Index 1-8 cho PB1-PB8 */

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

void GPIO_Handler_PollSwitches(void)
{
    /* PA8: Công tắc gạt chế độ lái (Drive Mode)
     * LOW = Drive (D), HIGH = Park (P) - vì cấu hình PULLUP
     */
    g_buttons.drive_mode = (HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_8) == GPIO_PIN_RESET) ? 1U : 0U;
}

/* ============ EXTI Callback (HAL weak override) ============ */

/**
 * @brief  Callback khi có EXTI interrupt từ nút nhấn PB1-PB8
 * @note   Mỗi nút có bộ đếm debounce riêng (50ms) để tránh rung
 *         Logic toggle: nhấn lần 1 = ON, nhấn lần 2 = OFF
 *         Ánh xạ trực tiếp với Tell-Tales trên Dashboard UI
 * @param  GPIO_Pin: Pin gây ra interrupt (GPIO_PIN_1 đến GPIO_PIN_8)
 */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    uint32_t now = HAL_GetTick();
    uint8_t idx;

    /* Xác định index debounce theo pin */
    switch (GPIO_Pin) {
        case GPIO_PIN_1: idx = BTN_ID_LEFT_SIGNAL;  break;  /* PB1 - Xi nhan trái   */
        case GPIO_PIN_2: idx = BTN_ID_RIGHT_SIGNAL; break;  /* PB2 - Xi nhan phải   */
        case GPIO_PIN_3: idx = BTN_ID_BEAM;         break;  /* PB3 - Đèn chiếu gần  */
        case GPIO_PIN_4: idx = BTN_ID_HIGH_BEAMS;   break;  /* PB4 - Đèn pha xa     */
        case GPIO_PIN_5: idx = BTN_ID_PARKED;       break;  /* PB5 - Đỗ xe          */
        case GPIO_PIN_6: idx = BTN_ID_AIRBAG;       break;  /* PB6 - Airbag         */
        case GPIO_PIN_7: idx = BTN_ID_MEDIA_PLAY;   break;  /* PB7 - Media Play     */
        case GPIO_PIN_8: idx = BTN_ID_MEDIA_NEXT;   break;  /* PB8 - Media Next     */
        default: return;  /* Pin không xử lý */
    }

    /* Debounce: bỏ qua nếu < 50ms kể từ lần nhấn trước của nút này */
    if (now - last_exti_tick[idx] < DEBOUNCE_DELAY_MS) return;
    last_exti_tick[idx] = now;

    /* Toggle trạng thái tương ứng */
    switch (idx) {
        case BTN_ID_LEFT_SIGNAL:  g_buttons.left_signal  ^= 1; break;
        case BTN_ID_RIGHT_SIGNAL: g_buttons.right_signal ^= 1; break;
        case BTN_ID_BEAM:         g_buttons.beam         ^= 1; break;
        case BTN_ID_HIGH_BEAMS:   g_buttons.high_beams   ^= 1; break;
        case BTN_ID_PARKED:       g_buttons.parked       ^= 1; break;
        case BTN_ID_AIRBAG:       g_buttons.airbag       ^= 1; break;
        case BTN_ID_MEDIA_PLAY:   g_buttons.media_play   ^= 1; break;
        case BTN_ID_MEDIA_NEXT:   g_buttons.media_next   ^= 1; break;
    }

    /* Cập nhật debug info */
    g_button_last_id_dbg = idx;
    switch (idx) {
        case BTN_ID_LEFT_SIGNAL:  g_button_last_state_dbg = g_buttons.left_signal;  break;
        case BTN_ID_RIGHT_SIGNAL: g_button_last_state_dbg = g_buttons.right_signal; break;
        case BTN_ID_BEAM:         g_button_last_state_dbg = g_buttons.beam;         break;
        case BTN_ID_HIGH_BEAMS:   g_button_last_state_dbg = g_buttons.high_beams;   break;
        case BTN_ID_PARKED:       g_button_last_state_dbg = g_buttons.parked;       break;
        case BTN_ID_AIRBAG:       g_button_last_state_dbg = g_buttons.airbag;       break;
        case BTN_ID_MEDIA_PLAY:   g_button_last_state_dbg = g_buttons.media_play;   break;
        case BTN_ID_MEDIA_NEXT:   g_button_last_state_dbg = g_buttons.media_next;   break;
        default: g_button_last_state_dbg = 0; break;
    }
    g_button_event_pending_dbg = 1U;
}
