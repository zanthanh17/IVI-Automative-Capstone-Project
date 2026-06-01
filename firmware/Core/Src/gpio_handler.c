/**
 * @file    gpio_handler.c
 * @brief   GPIO Handler implementation.
 *
 *          - PB5/PB6: can gat xi nhan, EXTI rising/falling, LOW = ON.
 *          - PB7/PB8: toggle qua EXTI falling edge + debounce. PB9: horn momentary.
 *          - 2 cong tac PA4/PA5: polling, LOW = ON do dung pull-up noi.
 */

#include "gpio_handler.h"
#include <string.h>

VehicleButtons_t g_buttons = {0};
volatile uint8_t g_button_last_id_dbg = 0U;
volatile uint8_t g_button_last_state_dbg = 0U;
volatile uint8_t g_button_event_pending_dbg = 0U;

static uint32_t last_exti_tick[BTN_ID_COUNT] = {0U};

void GPIO_Handler_Init(void)
{
    memset(&g_buttons, 0, sizeof(VehicleButtons_t));
    memset(last_exti_tick, 0, sizeof(last_exti_tick));
    g_button_last_id_dbg = 0U;
    g_button_last_state_dbg = 0U;
    g_button_event_pending_dbg = 0U;

    g_buttons.left_signal = (HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_5) == GPIO_PIN_RESET) ? 1U : 0U;
    g_buttons.right_signal = (HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_6) == GPIO_PIN_RESET) ? 1U : 0U;
    if (g_buttons.left_signal != 0U) {
        g_buttons.right_signal = 0U;
    }
    g_buttons.horn = (HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_9) == GPIO_PIN_RESET) ? 1U : 0U;
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
    g_buttons.beam = (HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_4) == GPIO_PIN_RESET) ? 1U : 0U;
    g_buttons.high_beams = (HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_5) == GPIO_PIN_RESET) ? 1U : 0U;

    /* Khong con drive switch trong pinout moi. Giu P/fallback de frame cu on dinh. */
    g_buttons.drive_mode = 0U;
}

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    uint32_t now = HAL_GetTick();
    uint8_t idx;

    switch (GPIO_Pin) {
        case GPIO_PIN_5: idx = BTN_ID_LEFT_SIGNAL;  break;  /* PB5 */
        case GPIO_PIN_6: idx = BTN_ID_RIGHT_SIGNAL; break;  /* PB6 */
        case GPIO_PIN_7: idx = BTN_ID_PARKED;       break;  /* PB7 */
        case GPIO_PIN_8: idx = BTN_ID_AIRBAG;       break;  /* PB8 */
        case GPIO_PIN_9: idx = BTN_ID_HORN;         break;  /* PB9 */
        default: return;
    }

    if ((idx == BTN_ID_LEFT_SIGNAL) || (idx == BTN_ID_RIGHT_SIGNAL) || (idx == BTN_ID_HORN)) {
        uint8_t input_state = (HAL_GPIO_ReadPin(GPIOB, GPIO_Pin) == GPIO_PIN_RESET) ? 1U : 0U;
        uint8_t current_state;

        switch (idx) {
            case BTN_ID_LEFT_SIGNAL:  current_state = g_buttons.left_signal;  break;
            case BTN_ID_RIGHT_SIGNAL: current_state = g_buttons.right_signal; break;
            case BTN_ID_HORN:         current_state = g_buttons.horn;         break;
            default:                  current_state = 0U;                    break;
        }

        if (current_state == input_state) {
            return;
        }

        /* Never debounce away OFF, otherwise a quick return to neutral could leave a load ON. */
        if (input_state != 0U && last_exti_tick[idx] != 0U &&
            (now - last_exti_tick[idx]) < DEBOUNCE_DELAY_MS) {
            return;
        }
        last_exti_tick[idx] = now;

        switch (idx) {
            case BTN_ID_LEFT_SIGNAL:
                g_buttons.left_signal = input_state;
                if (input_state != 0U) {
                    g_buttons.right_signal = 0U;
                }
                break;
            case BTN_ID_RIGHT_SIGNAL:
                g_buttons.right_signal = input_state;
                if (input_state != 0U) {
                    g_buttons.left_signal = 0U;
                }
                break;
            case BTN_ID_HORN:
                g_buttons.horn = input_state;
                break;
            default:
                break;
        }

        g_button_last_id_dbg = idx;
        g_button_last_state_dbg = input_state;
        g_button_event_pending_dbg = 1U;
        return;
    }

    if ((now - last_exti_tick[idx]) < DEBOUNCE_DELAY_MS) {
        return;
    }
    last_exti_tick[idx] = now;

    switch (idx) {
        case BTN_ID_PARKED:       g_buttons.parked       ^= 1U; break;
        case BTN_ID_AIRBAG:       g_buttons.airbag       ^= 1U; break;
        default: return;
    }

    g_button_last_id_dbg = idx;
    switch (idx) {
        case BTN_ID_PARKED:       g_button_last_state_dbg = g_buttons.parked;       break;
        case BTN_ID_AIRBAG:       g_button_last_state_dbg = g_buttons.airbag;       break;
        default:                  g_button_last_state_dbg = 0U;                    break;
    }
    g_button_event_pending_dbg = 1U;
}
