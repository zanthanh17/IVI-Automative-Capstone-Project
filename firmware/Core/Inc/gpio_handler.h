/**
 * @file    gpio_handler.h
 * @brief   GPIO Handler - Nút nhấn (EXTI interrupt) + Công tắc gạt (polling)
 * @note    Thiết kế ánh xạ đầy đủ với Dashboard UI (Qt Instrument Cluster)
 *
 *          === Tell-Tales Indicators ===
 *          PB1: Xi nhan trái   (Turn Left)     → TellTalesModel.turnLeftActive
 *          PB2: Xi nhan phải   (Turn Right)    → TellTalesModel.turnRightActive
 *          PB3: Đèn chiếu gần (Beam)          → TellTalesModel.beamActive
 *          PB4: Đèn pha xa    (High Beams)    → TellTalesModel.highBeamsActive
 *          PB5: Đỗ xe/Phanh tay (Parked)      → TellTalesModel.parkedActive
 *          PB6: Cảnh báo Airbag               → TellTalesModel.airbagActive
 *
 *          === Media Player Controls ===
 *          PB7: Media Play/Pause              → MediaPlayerModel
 *          PB8: Media Next Track              → MediaPlayerModel
 *
 *          === Công tắc gạt (polling) ===
 *          PA8: Chế độ lái (Drive Mode)       → MainModel gear
 */

#ifndef GPIO_HANDLER_H
#define GPIO_HANDLER_H

#include "stm32f1xx_hal.h"

/* ============ Cấu hình debounce ============ */
#define DEBOUNCE_DELAY_MS   50   /* Thời gian debounce (ms) */

/* ============ Button ID definitions ============ */
#define BTN_ID_LEFT_SIGNAL    1   /* PB1 - Xi nhan trái        */
#define BTN_ID_RIGHT_SIGNAL   2   /* PB2 - Xi nhan phải        */
#define BTN_ID_BEAM           3   /* PB3 - Đèn chiếu gần      */
#define BTN_ID_HIGH_BEAMS     4   /* PB4 - Đèn pha xa         */
#define BTN_ID_PARKED         5   /* PB5 - Đỗ xe / Phanh tay  */
#define BTN_ID_AIRBAG         6   /* PB6 - Cảnh báo Airbag    */
#define BTN_ID_MEDIA_PLAY     7   /* PB7 - Media Play/Pause   */
#define BTN_ID_MEDIA_NEXT     8   /* PB8 - Media Next Track   */
#define BTN_ID_COUNT          9   /* Tổng số (index 1-8)       */

/* ============ Struct trạng thái các nút/công tắc ============ */
typedef struct {
    /* --- Tell-Tales: toggle qua interrupt (0 = OFF, 1 = ON) --- */
    uint8_t left_signal;    /* Xi nhan trái         (PB1) → turnLeftActive    */
    uint8_t right_signal;   /* Xi nhan phải         (PB2) → turnRightActive   */
    uint8_t beam;           /* Đèn chiếu gần       (PB3) → beamActive        */
    uint8_t high_beams;     /* Đèn pha xa          (PB4) → highBeamsActive   */
    uint8_t parked;         /* Đỗ xe / Phanh tay   (PB5) → parkedActive      */
    uint8_t airbag;         /* Cảnh báo Airbag     (PB6) → airbagActive      */

    /* --- Media Player Controls --- */
    uint8_t media_play;     /* Play/Pause           (PB7) → MediaPlayerModel  */
    uint8_t media_next;     /* Next Track           (PB8) → MediaPlayerModel  */

    /* --- Công tắc gạt (polling) --- */
    uint8_t drive_mode;     /* Chế độ lái           (PA8) → MainModel gear    */
} VehicleButtons_t;

/* ============ Biến global ============ */
extern VehicleButtons_t g_buttons;
extern volatile uint8_t g_button_last_id_dbg;
extern volatile uint8_t g_button_last_state_dbg;
extern volatile uint8_t g_button_event_pending_dbg;

/* ============ API ============ */

/**
 * @brief  Khởi tạo GPIO handler, reset trạng thái buttons
 */
void GPIO_Handler_Init(void);

/**
 * @brief  Pop một sự kiện nút nhấn (dùng trong main loop)
 * @param  button_id     [out] ID nút (BTN_ID_xxx)
 * @param  button_state  [out] Trạng thái (0=OFF, 1=ON)
 * @return 1 nếu có event, 0 nếu không
 */
uint8_t GPIO_Handler_PopButtonEvent(uint8_t *button_id, uint8_t *button_state);

/**
 * @brief  Đọc công tắc gạt PA8 (polling, gọi trong main loop)
 */
void GPIO_Handler_PollSwitches(void);

#endif /* GPIO_HANDLER_H */
