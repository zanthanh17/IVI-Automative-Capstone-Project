/**
 * @file    body_loads.h
 * @brief   Body ECU load output control.
 */

#ifndef BODY_LOADS_H
#define BODY_LOADS_H

#include "stm32f1xx_hal.h"

#define BODY_LOAD_ACTIVE_HIGH       1U
#define BODY_LOAD_BLINK_MS        500U
#define BODY_LOAD_RX_TIMEOUT_MS   500U

#define BODY_MASK_LEFT_SIGNAL     (1U << 0)
#define BODY_MASK_RIGHT_SIGNAL    (1U << 1)
#define BODY_MASK_BEAM            (1U << 2)
#define BODY_MASK_HIGH_BEAMS      (1U << 3)
#define BODY_MASK_PARKED          (1U << 4)
#define BODY_MASK_AIRBAG          (1U << 5)
#define BODY_MASK_HORN            (1U << 6)

#define BODY_LOAD_COMMAND_MASK    (BODY_MASK_LEFT_SIGNAL | BODY_MASK_RIGHT_SIGNAL | \
                                   BODY_MASK_BEAM | BODY_MASK_HIGH_BEAMS | BODY_MASK_HORN)

void Body_Loads_Init(void);
void Body_Loads_ApplyCommandMask(uint8_t command_mask, uint32_t now_ms);
void Body_Loads_Service(uint32_t now_ms);
void Body_Loads_ForceOff(void);

uint8_t Body_Loads_GetCommandMask(void);
uint8_t Body_Loads_GetOutputMask(void);
uint8_t Body_Loads_IsRxTimedOut(void);

#endif /* BODY_LOADS_H */
