/**
 * @file    can_protocol.c
 * @brief   CAN protocol bridge from STM32 cluster ECU to Raspberry Pi Qt app.
 */

#include "can_protocol.h"

extern CAN_HandleTypeDef hcan;

static uint8_t s_can_ready = 0U;
static uint8_t s_telemetry_counter = 0U;
static uint8_t s_button_state_counter = 0U;
static uint8_t s_button_event_counter = 0U;

static uint8_t CAN_Protocol_ButtonMask(const VehicleButtons_t *buttons)
{
    uint8_t mask = 0U;

    if (buttons == NULL) {
        return 0U;
    }

    if (buttons->left_signal  != 0U) mask |= (1U << 0);
    if (buttons->right_signal != 0U) mask |= (1U << 1);
    if (buttons->beam         != 0U) mask |= (1U << 2);
    if (buttons->high_beams   != 0U) mask |= (1U << 3);
    if (buttons->parked       != 0U) mask |= (1U << 4);
    if (buttons->airbag       != 0U) mask |= (1U << 5);
    if (buttons->media_play   != 0U) mask |= (1U << 6);
    if (buttons->media_next   != 0U) mask |= (1U << 7);

    return mask;
}

static uint8_t CAN_Protocol_Transmit(uint16_t std_id, const uint8_t *payload, uint8_t dlc)
{
    CAN_TxHeaderTypeDef tx_header;
    uint32_t tx_mailbox;

    if (s_can_ready == 0U || payload == NULL || dlc > 8U) {
        return 0U;
    }

    if (HAL_CAN_GetTxMailboxesFreeLevel(&hcan) == 0U) {
        return 0U;
    }

    tx_header.StdId = std_id;
    tx_header.ExtId = 0U;
    tx_header.IDE = CAN_ID_STD;
    tx_header.RTR = CAN_RTR_DATA;
    tx_header.DLC = dlc;
    tx_header.TransmitGlobalTime = DISABLE;

    return (HAL_CAN_AddTxMessage(&hcan, &tx_header, (uint8_t *)payload, &tx_mailbox) == HAL_OK) ? 1U : 0U;
}

void CAN_Protocol_Init(void)
{
    CAN_FilterTypeDef filter;

    filter.FilterBank = 0U;
    filter.FilterMode = CAN_FILTERMODE_IDMASK;
    filter.FilterScale = CAN_FILTERSCALE_32BIT;
    filter.FilterIdHigh = 0x0000U;
    filter.FilterIdLow = 0x0000U;
    filter.FilterMaskIdHigh = 0x0000U;
    filter.FilterMaskIdLow = 0x0000U;
    filter.FilterFIFOAssignment = CAN_FILTER_FIFO0;
    filter.FilterActivation = ENABLE;
    filter.SlaveStartFilterBank = 14U;

    s_can_ready = 0U;

    if (HAL_CAN_ConfigFilter(&hcan, &filter) != HAL_OK) {
        return;
    }

    if (HAL_CAN_Start(&hcan) != HAL_OK) {
        return;
    }

    s_can_ready = 1U;
}

uint8_t CAN_Protocol_IsReady(void)
{
    return s_can_ready;
}

uint8_t CAN_Protocol_SendTelemetry(uint16_t speed_kmh,
                                   uint16_t rpm,
                                   uint8_t fuel_percent,
                                   uint8_t battery_percent,
                                   char gear)
{
    uint8_t data[8];

    if (fuel_percent > 100U) {
        fuel_percent = 100U;
    }
    if (battery_percent > 100U) {
        battery_percent = 100U;
    }

    if (gear != 'P' && gear != 'D' && gear != 'N' && gear != 'R') {
        gear = 'P';
    }

    data[0] = (uint8_t)((speed_kmh >> 8) & 0xFFU);
    data[1] = (uint8_t)(speed_kmh & 0xFFU);
    data[2] = (uint8_t)((rpm >> 8) & 0xFFU);
    data[3] = (uint8_t)(rpm & 0xFFU);
    data[4] = fuel_percent;
    data[5] = battery_percent;
    data[6] = (uint8_t)gear;
    data[7] = s_telemetry_counter++;

    return CAN_Protocol_Transmit(CAN_ID_VEHICLE_TELEMETRY, data, 8U);
}

uint8_t CAN_Protocol_SendButtonState(const VehicleButtons_t *buttons)
{
    uint8_t data[8] = {0U};

    if (buttons == NULL) {
        return 0U;
    }

    data[0] = CAN_Protocol_ButtonMask(buttons);
    data[1] = buttons->drive_mode;
    data[2] = s_button_state_counter++;

    return CAN_Protocol_Transmit(CAN_ID_BUTTON_STATE, data, 8U);
}

uint8_t CAN_Protocol_SendButtonEvent(uint8_t button_id,
                                     uint8_t button_state,
                                     const VehicleButtons_t *buttons)
{
    uint8_t data[8] = {0U};

    data[0] = button_id;
    data[1] = (button_state != 0U) ? 1U : 0U;
    data[2] = s_button_event_counter++;
    data[3] = CAN_Protocol_ButtonMask(buttons);
    data[4] = (buttons != NULL) ? buttons->drive_mode : 0U;

    return CAN_Protocol_Transmit(CAN_ID_BUTTON_EVENT, data, 8U);
}
