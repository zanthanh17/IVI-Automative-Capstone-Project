/**
 * @file    adc_handler.h
 * @brief   ADC Handler - Đọc mức nhiên liệu và pin qua biến trở
 * @note    Ánh xạ với Dashboard UI:
 *          PA0 (ADC1_CH0) → Fuel Level   → MainModel.fuelLevel (StatusBar)
 *          PA1 (ADC1_CH1) → Battery Level → MainModel.batteryLevel (StatusBar)
 *
 * @prerequisite  ADC1 cấu hình trong CubeMX:
 *                - Scan Conversion Mode: Enable
 *                - 2 channels: IN0 (PA0), IN1 (PA1)
 *                - Resolution: 12-bit (0-4095)
 *                - Sampling time: 239.5 cycles (cho tín hiệu biến trở)
 *
 * @hardware      Biến trở 10kΩ:
 *                - Chân 1 → GND
 *                - Chân 2 (wiper) → PA0 hoặc PA1
 *                - Chân 3 → 3.3V
 */

#ifndef ADC_HANDLER_H
#define ADC_HANDLER_H

#include "stm32f1xx_hal.h"

/* ============ Cấu hình ADC ============ */
#define ADC_MAX_VALUE       4095U    /* 12-bit ADC */
#define ADC_FILTER_SAMPLES  8U       /* Số mẫu lọc trung bình */

/* ============ Struct dữ liệu ADC ============ */
typedef struct {
    uint16_t fuel_raw;       /* Giá trị ADC thô kênh fuel (0-4095)       */
    uint16_t battery_raw;    /* Giá trị ADC thô kênh battery (0-4095)    */
    float    fuel_percent;   /* Mức nhiên liệu (0.0 - 1.0)              */
    float    battery_percent;/* Mức pin (0.0 - 1.0)                     */
} ADCData_t;

/* ============ Biến global ============ */
extern ADCData_t g_adc;

/* ============ Cần khai báo extern từ main.c (CubeMX generated) ============ */
extern ADC_HandleTypeDef hadc1;

/* ============ API ============ */

/**
 * @brief  Khởi tạo ADC handler, calibrate ADC
 */
void ADC_Handler_Init(void);

/**
 * @brief  Đọc và cập nhật giá trị fuel + battery (gọi định kỳ ~200ms)
 * @note   Sử dụng lọc trung bình để giảm nhiễu từ biến trở
 */
void ADC_Handler_Update(void);

#endif /* ADC_HANDLER_H */
