/**
 * @file    body_can.c
 * @brief   Body ECU CAN protocol receiver and status transmitter.
 */

#include "body_can.h"
#include "body_loads.h"

extern CAN_HandleTypeDef hcan;

Body_CAN_Debug_t g_body_can_dbg = {0};

static uint8_t s_can_ready = 0U;
static uint8_t s_status_counter = 0U;
static uint32_t s_last_status_tick = 0U;

static uint8_t Body_CAN_Transmit(uint16_t std_id, const uint8_t *payload, uint8_t dlc)
{
    CAN_TxHeaderTypeDef tx_header;
    uint32_t tx_mailbox;

    if (s_can_ready == 0U || payload == NULL || dlc > 8U) {
        return 0U;
    }

    g_body_can_dbg.can_esr = hcan.Instance->ESR;
    g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);

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

static void Body_CAN_ProcessFrame(const CAN_RxHeaderTypeDef *rx_header, const uint8_t data[8])
{
    uint8_t command_mask;

    if (rx_header == NULL || data == NULL) {
        return;
    }

    if (rx_header->IDE != CAN_ID_STD || rx_header->RTR != CAN_RTR_DATA) {
        g_body_can_dbg.rx_ignored++;
        return;
    }

    g_body_can_dbg.rx_count++;
    g_body_can_dbg.last_rx_id = rx_header->StdId;

    switch (rx_header->StdId) {
    case BODY_CAN_ID_BUTTON_STATE:
        if (rx_header->DLC >= 3U) {
            command_mask = data[0];
            Body_Loads_ApplyCommandMask(command_mask, HAL_GetTick());
            g_body_can_dbg.rx_snapshot++;
            g_body_can_dbg.last_command_mask = command_mask;
        }
        break;

    case BODY_CAN_ID_BUTTON_EVENT:
        if (rx_header->DLC >= 4U) {
            command_mask = data[3];
            Body_Loads_ApplyCommandMask(command_mask, HAL_GetTick());
            g_body_can_dbg.rx_event++;
            g_body_can_dbg.last_command_mask = command_mask;
        }
        break;

    default:
        g_body_can_dbg.rx_ignored++;
        break;
    }
}

static void Body_CAN_SendStatus(void)
{
    uint8_t data[8] = {0U};
    uint8_t flags = 0U;
    uint32_t hal_error;

    hal_error = HAL_CAN_GetError(&hcan);
    g_body_can_dbg.hal_error_code = hal_error;
    g_body_can_dbg.can_esr = hcan.Instance->ESR;
    g_body_can_dbg.rx_timeout = Body_Loads_IsRxTimedOut();
    g_body_can_dbg.can_error = (hal_error != HAL_CAN_ERROR_NONE) ? 1U : 0U;

    if (s_can_ready != 0U) {
        flags |= BODY_CAN_STATUS_FLAG_READY;
    }
    if (Body_Loads_IsRxTimedOut() != 0U) {
        flags |= BODY_CAN_STATUS_FLAG_TIMEOUT;
    }
    if (g_body_can_dbg.can_error != 0U) {
        flags |= BODY_CAN_STATUS_FLAG_CAN_ERROR;
    }

    data[0] = Body_Loads_GetCommandMask();
    data[1] = Body_Loads_GetOutputMask();
    data[2] = flags;
    data[3] = s_status_counter++;

    g_body_can_dbg.tx_status_attempt++;
    if (Body_CAN_Transmit(BODY_CAN_ID_STATUS, data, 8U) != 0U) {
        g_body_can_dbg.tx_status_ok++;
    } else {
        g_body_can_dbg.tx_status_fail++;
    }
}

void Body_CAN_Init(void)
{
    CAN_FilterTypeDef filter;

    s_can_ready = 0U;
    g_body_can_dbg.init_ok = 0U;
    g_body_can_dbg.filter_ok = 0U;
    g_body_can_dbg.notify_ok = 0U;

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

    if (HAL_CAN_ConfigFilter(&hcan, &filter) != HAL_OK) {
        g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);
        return;
    }
    g_body_can_dbg.filter_ok = 1U;

    if (HAL_CAN_Start(&hcan) != HAL_OK) {
        g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);
        return;
    }
    s_can_ready = 1U;
    g_body_can_dbg.init_ok = 1U;

    if (HAL_CAN_ActivateNotification(&hcan,
                                     CAN_IT_RX_FIFO0_MSG_PENDING |
                                     CAN_IT_BUSOFF |
                                     CAN_IT_ERROR |
                                     CAN_IT_LAST_ERROR_CODE) == HAL_OK) {
        g_body_can_dbg.notify_ok = 1U;
    } else {
        g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);
    }

    s_last_status_tick = HAL_GetTick();
}

void Body_CAN_Service(uint32_t now_ms)
{
    if ((now_ms - s_last_status_tick) >= BODY_CAN_STATUS_MS) {
        Body_CAN_SendStatus();
        s_last_status_tick = now_ms;
    }
}

uint8_t Body_CAN_IsReady(void)
{
    return s_can_ready;
}

void HAL_CAN_RxFifo0MsgPendingCallback(CAN_HandleTypeDef *hcan_arg)
{
    CAN_RxHeaderTypeDef rx_header;
    uint8_t data[8] = {0U};

    if (hcan_arg != &hcan) {
        return;
    }

    if (HAL_CAN_GetRxMessage(&hcan, CAN_RX_FIFO0, &rx_header, data) == HAL_OK) {
        Body_CAN_ProcessFrame(&rx_header, data);
    } else {
        g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);
    }
}

void HAL_CAN_ErrorCallback(CAN_HandleTypeDef *hcan_arg)
{
    if (hcan_arg == &hcan) {
        g_body_can_dbg.hal_error_code = HAL_CAN_GetError(&hcan);
        g_body_can_dbg.can_esr = hcan.Instance->ESR;
        g_body_can_dbg.can_error = 1U;
    }
}
