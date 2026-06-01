/**
 * @file    gpio_handler.h
 * @brief   GPIO Handler - can gat xi nhan, nut EXTI va cong tac den.
 *
 *          Mapping phan cung de dau tren Blue Pill:
 *          PB5: Left signal stalk/contact, LOW = ON
 *          PB6: Right signal stalk/contact, LOW = ON
 *          PB7: Parked button
 *          PB8: Airbag button
 *          PB9: Horn button
 *          PA4: Beam switch
 *          PA5: High beams switch
 */

#ifndef GPIO_HANDLER_H
#define GPIO_HANDLER_H

#include "stm32f1xx_hal.h"

#define DEBOUNCE_DELAY_MS   50U

/* CAN/UART button IDs. Beam/high-beams are switches, so they normally do not
 * generate button-event frames, but their IDs are kept for protocol bit order.
 */
#define BTN_ID_LEFT_SIGNAL    1U
#define BTN_ID_RIGHT_SIGNAL   2U
#define BTN_ID_BEAM           3U
#define BTN_ID_HIGH_BEAMS     4U
#define BTN_ID_PARKED         5U
#define BTN_ID_AIRBAG         6U
#define BTN_ID_HORN           7U
#define BTN_ID_COUNT          8U

typedef struct {
    uint8_t left_signal;    /* PB5 stalk/contact, LOW = ON, HIGH = OFF */
    uint8_t right_signal;   /* PB6 stalk/contact, LOW = ON, HIGH = OFF */
    uint8_t beam;           /* PA4 switch, LOW = ON */
    uint8_t high_beams;     /* PA5 switch, LOW = ON */
    uint8_t parked;         /* PB7 button, toggle by EXTI */
    uint8_t airbag;         /* PB8 button, toggle by EXTI */
    uint8_t horn;           /* PB9 button, momentary by EXTI rising/falling */
    uint8_t drive_mode;     /* Reserved/fallback gear state, fixed 0 when no drive switch */
} VehicleButtons_t;

extern VehicleButtons_t g_buttons;
extern volatile uint8_t g_button_last_id_dbg;
extern volatile uint8_t g_button_last_state_dbg;
extern volatile uint8_t g_button_event_pending_dbg;

void GPIO_Handler_Init(void);
uint8_t GPIO_Handler_PopButtonEvent(uint8_t *button_id, uint8_t *button_state);
void GPIO_Handler_PollSwitches(void);

#endif /* GPIO_HANDLER_H */
