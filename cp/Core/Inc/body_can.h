/**
 * @file    body_can.h
 * @brief   Body ECU CAN protocol receiver and status transmitter.
 */

#ifndef BODY_CAN_H
#define BODY_CAN_H

#include "stm32f1xx_hal.h"

#define BODY_CAN_ID_VEHICLE_TELEMETRY  0x100U
#define BODY_CAN_ID_BUTTON_STATE       0x101U
#define BODY_CAN_ID_BUTTON_EVENT       0x102U
#define BODY_CAN_ID_STATUS             0x201U

#define BODY_CAN_STATUS_MS             200U

#define BODY_CAN_STATUS_FLAG_READY      (1U << 0)
#define BODY_CAN_STATUS_FLAG_TIMEOUT    (1U << 1)
#define BODY_CAN_STATUS_FLAG_CAN_ERROR  (1U << 2)

typedef struct {
    volatile uint32_t init_ok;
    volatile uint32_t filter_ok;
    volatile uint32_t notify_ok;
    volatile uint32_t rx_count;
    volatile uint32_t rx_snapshot;
    volatile uint32_t rx_event;
    volatile uint32_t rx_ignored;
    volatile uint32_t tx_status_attempt;
    volatile uint32_t tx_status_ok;
    volatile uint32_t tx_status_fail;
    volatile uint32_t rx_timeout;
    volatile uint32_t can_error;
    volatile uint32_t hal_error_code;
    volatile uint32_t can_esr;
    volatile uint32_t last_rx_id;
    volatile uint32_t last_command_mask;
} Body_CAN_Debug_t;

extern Body_CAN_Debug_t g_body_can_dbg;

void Body_CAN_Init(void);
void Body_CAN_Service(uint32_t now_ms);
uint8_t Body_CAN_IsReady(void);

#endif /* BODY_CAN_H */
