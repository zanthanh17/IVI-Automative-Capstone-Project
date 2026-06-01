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

/* ============ Debug counters (xem qua ST-LINK Variable Viewer) ============ */
typedef struct {
    volatile uint32_t init_ok;           /* 1 = CAN_Start OK, 0 = failed       */
    volatile uint32_t filter_ok;         /* 1 = Filter config OK               */
    volatile uint32_t tx_attempt;        /* Số lần gọi Transmit                */
    volatile uint32_t tx_success;        /* Số frame gửi thành công            */
    volatile uint32_t tx_fail_not_ready; /* Fail: CAN chưa init                */
    volatile uint32_t tx_fail_no_mbox;   /* Fail: hết mailbox (bus lỗi/no ACK) */
    volatile uint32_t tx_fail_hal;       /* Fail: HAL_CAN_AddTxMessage lỗi     */
    volatile uint32_t hal_error_code;    /* HAL error code cuối cùng           */
    volatile uint32_t can_esr;           /* CAN Error Status Register snapshot */
} CAN_Debug_t;

extern CAN_Debug_t g_can_dbg;

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
