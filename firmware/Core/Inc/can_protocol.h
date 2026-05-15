/**
 * @file    can_protocol.h
 * @brief   CAN protocol bridge from STM32 cluster ECU to Raspberry Pi Qt app.
 */

#ifndef CAN_PROTOCOL_H
#define CAN_PROTOCOL_H

#include "gpio_handler.h"
#include "stm32f1xx_hal.h"

#define CAN_ID_VEHICLE_TELEMETRY  0x100U
#define CAN_ID_BUTTON_STATE       0x101U
#define CAN_ID_BUTTON_EVENT       0x102U

void CAN_Protocol_Init(void);
uint8_t CAN_Protocol_IsReady(void);

uint8_t CAN_Protocol_SendTelemetry(uint16_t speed_kmh,
                                   uint16_t rpm,
                                   uint8_t fuel_percent,
                                   uint8_t battery_percent,
                                   char gear);

uint8_t CAN_Protocol_SendButtonState(const VehicleButtons_t *buttons);

uint8_t CAN_Protocol_SendButtonEvent(uint8_t button_id,
                                     uint8_t button_state,
                                     const VehicleButtons_t *buttons);

#endif /* CAN_PROTOCOL_H */
