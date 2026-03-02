/**
 * @file    encoder_handler.h
 * @brief   Rotary Encoder Handler - Đọc KY-040 qua TIM3 Encoder Mode
 * @note    PA6 = TIM3_CH1 (CLK), PA7 = TIM3_CH2 (DT)
 *          Tốc độ tích lũy: xoay phải tăng, xoay trái giảm (0-200 km/h)
 *
 * @prerequisite  TIM3 phải được cấu hình Encoder Mode trong CubeMX:
 *                Combined Channels → Encoder Mode
 *                Counter Period = 65535
 *                Encoder Mode = TI1 and TI2
 */

#ifndef ENCODER_HANDLER_H
#define ENCODER_HANDLER_H

#include "stm32f1xx_hal.h"

/* ============ Giới hạn tốc độ ============ */
#define SPEED_MIN   0
#define SPEED_MAX   200   /* km/h */

/* ============ Giá trị giữa counter (đếm 2 chiều) ============ */
#define ENCODER_CENTER_VALUE   32767

/* ============ Struct dữ liệu encoder ============ */
typedef struct {
    int16_t  delta;         /* Số xung thay đổi kể từ lần đọc trước */
    uint16_t speed_kmh;     /* Tốc độ xe mô phỏng (0-200 km/h)     */
} EncoderData_t;

/* ============ Biến global ============ */
extern EncoderData_t g_encoder;
extern volatile int16_t g_encoder_last_count_dbg;
extern volatile uint16_t g_encoder_cnt_dbg;
extern volatile uint32_t g_encoder_update_count_dbg;

/* ============ Cần khai báo extern từ main.c (CubeMX generated) ============ */
extern TIM_HandleTypeDef htim3;

/* ============ API ============ */

/**
 * @brief  Khởi tạo encoder: start TIM3 encoder mode, reset counter
 */
void Encoder_Init(void);

/**
 * @brief  Cập nhật tốc độ từ encoder (gọi định kỳ trong main loop hoặc timer)
 * @note   Gọi mỗi 50-100ms để đọc delta xung và tích lũy tốc độ
 */
void Encoder_Update(void);

#endif /* ENCODER_HANDLER_H */
