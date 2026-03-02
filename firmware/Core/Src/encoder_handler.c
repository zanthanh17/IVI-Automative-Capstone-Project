/**
 * @file    encoder_handler.c
 * @brief   Rotary Encoder Handler implementation
 *          Đọc KY-040 qua TIM3 Encoder Mode, tích lũy tốc độ 0-200 km/h
 */

#include "encoder_handler.h"

/* ============ Biến global ============ */
EncoderData_t g_encoder = {0};
volatile int16_t g_encoder_last_count_dbg = ENCODER_CENTER_VALUE;
volatile uint16_t g_encoder_cnt_dbg = ENCODER_CENTER_VALUE;
volatile uint32_t g_encoder_update_count_dbg = 0;

/* ============ Biến nội bộ ============ */
static int16_t last_count = ENCODER_CENTER_VALUE;

/* ============ API ============ */

void Encoder_Init(void)
{
    /*
     * Bắt đầu TIM3 Encoder Mode trên cả 2 kênh
     * TIM3 đếm xung từ encoder A (PA6) và B (PA7)
     */
    HAL_TIM_Encoder_Start(&htim3, TIM_CHANNEL_ALL);

    /*
     * Set counter về giữa (32767) để có thể đếm cả 2 chiều:
     * - Xoay phải: counter tăng từ 32767 lên
     * - Xoay trái: counter giảm từ 32767 xuống
     */
    __HAL_TIM_SET_COUNTER(&htim3, ENCODER_CENTER_VALUE);
    last_count = ENCODER_CENTER_VALUE;
    g_encoder_last_count_dbg = last_count;
    g_encoder_cnt_dbg = (uint16_t)last_count;
    g_encoder_update_count_dbg = 0;

    /* Reset dữ liệu */
    g_encoder.delta = 0;
    g_encoder.speed_kmh = 0;
}

void Encoder_Update(void)
{
    /* Đọc giá trị counter hiện tại từ TIM3 */
    int16_t current = (int16_t)__HAL_TIM_GET_COUNTER(&htim3);
    g_encoder_cnt_dbg = (uint16_t)current;

    /* Tính delta (số xung thay đổi kể từ lần đọc trước) */
    g_encoder.delta = current - last_count;
    last_count = current;
    g_encoder_last_count_dbg = last_count;
    g_encoder_update_count_dbg++;

    /*
     * Tích lũy tốc độ:
     *   - Xoay phải (delta > 0) → tăng tốc
     *   - Xoay trái (delta < 0) → giảm tốc
     * Giới hạn trong khoảng 0-200 km/h
     */
    int16_t new_speed = (int16_t)g_encoder.speed_kmh + g_encoder.delta;

    if (new_speed < SPEED_MIN) {
        new_speed = SPEED_MIN;
    }
    if (new_speed > SPEED_MAX) {
        new_speed = SPEED_MAX;
    }

    g_encoder.speed_kmh = (uint16_t)new_speed;
}
