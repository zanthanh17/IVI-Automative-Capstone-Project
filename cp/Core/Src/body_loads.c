/**
 * @file    body_loads.c
 * @brief   Body ECU load output control.
 */

#include "body_loads.h"
#include "main.h"

static uint8_t s_command_mask = 0U;
static uint8_t s_output_mask = 0U;
static uint8_t s_blink_on = 1U;
static uint8_t s_rx_seen = 0U;
static uint8_t s_rx_timeout = 1U;
static uint32_t s_last_command_tick = 0U;
static uint32_t s_last_blink_tick = 0U;

static void Body_Loads_WritePin(GPIO_TypeDef *port, uint16_t pin, uint8_t active)
{
#if BODY_LOAD_ACTIVE_HIGH
    HAL_GPIO_WritePin(port, pin, (active != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
#else
    HAL_GPIO_WritePin(port, pin, (active != 0U) ? GPIO_PIN_RESET : GPIO_PIN_SET);
#endif
}

static void Body_Loads_ApplyOutputs(uint8_t output_mask)
{
    Body_Loads_WritePin(BODY_LEFT_SIGNAL_GPIO_Port,
                        BODY_LEFT_SIGNAL_Pin,
                        (output_mask & BODY_MASK_LEFT_SIGNAL) != 0U);
    Body_Loads_WritePin(BODY_RIGHT_SIGNAL_GPIO_Port,
                        BODY_RIGHT_SIGNAL_Pin,
                        (output_mask & BODY_MASK_RIGHT_SIGNAL) != 0U);
    Body_Loads_WritePin(BODY_BEAM_GPIO_Port,
                        BODY_BEAM_Pin,
                        (output_mask & BODY_MASK_BEAM) != 0U);
    Body_Loads_WritePin(BODY_HIGH_BEAMS_GPIO_Port,
                        BODY_HIGH_BEAMS_Pin,
                        (output_mask & BODY_MASK_HIGH_BEAMS) != 0U);
    Body_Loads_WritePin(BODY_HORN_GPIO_Port,
                        BODY_HORN_Pin,
                        (output_mask & BODY_MASK_HORN) != 0U);
}

void Body_Loads_Init(void)
{
    s_command_mask = 0U;
    s_output_mask = 0U;
    s_blink_on = 1U;
    s_rx_seen = 0U;
    s_rx_timeout = 1U;
    s_last_command_tick = 0U;
    s_last_blink_tick = HAL_GetTick();
    Body_Loads_ApplyOutputs(0U);
}

void Body_Loads_ApplyCommandMask(uint8_t command_mask, uint32_t now_ms)
{
    s_command_mask = command_mask & BODY_LOAD_COMMAND_MASK;
    s_last_command_tick = now_ms;
    s_rx_seen = 1U;
    s_rx_timeout = 0U;
}

void Body_Loads_Service(uint32_t now_ms)
{
    uint8_t output_mask = 0U;

    if (s_rx_seen == 0U || (now_ms - s_last_command_tick) > BODY_LOAD_RX_TIMEOUT_MS) {
        s_rx_timeout = 1U;
        s_command_mask = 0U;
    } else {
        s_rx_timeout = 0U;
    }

    if ((now_ms - s_last_blink_tick) >= BODY_LOAD_BLINK_MS) {
        s_blink_on ^= 1U;
        s_last_blink_tick = now_ms;
    }

    if (s_blink_on != 0U) {
        output_mask |= s_command_mask & (BODY_MASK_LEFT_SIGNAL | BODY_MASK_RIGHT_SIGNAL);
    }
    output_mask |= s_command_mask & (BODY_MASK_BEAM | BODY_MASK_HIGH_BEAMS | BODY_MASK_HORN);

    s_output_mask = output_mask;
    Body_Loads_ApplyOutputs(s_output_mask);
}

void Body_Loads_ForceOff(void)
{
    s_command_mask = 0U;
    s_output_mask = 0U;
    s_rx_timeout = 1U;
    Body_Loads_ApplyOutputs(0U);
}

uint8_t Body_Loads_GetCommandMask(void)
{
    return s_command_mask;
}

uint8_t Body_Loads_GetOutputMask(void)
{
    return s_output_mask;
}

uint8_t Body_Loads_IsRxTimedOut(void)
{
    return s_rx_timeout;
}
