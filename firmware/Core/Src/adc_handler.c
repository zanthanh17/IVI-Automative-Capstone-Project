/**
 * @file    adc_handler.c
 * @brief   ADC Handler implementation
 *          Đọc biến trở trên PA0 (Fuel) và PA1 (Battery) qua ADC1
 *          Sử dụng lọc trung bình 8 mẫu để giảm nhiễu
 */

#include "adc_handler.h"

/* ============ Biến global ============ */
ADCData_t g_adc = {0};

/* ============ Biến nội bộ - bộ lọc trung bình ============ */
static uint16_t fuel_samples[ADC_FILTER_SAMPLES] = {0};
static uint16_t battery_samples[ADC_FILTER_SAMPLES] = {0};
static uint8_t  sample_index = 0;

/* ============ Hàm nội bộ ============ */

/**
 * @brief  Đọc 1 kênh ADC bằng polling
 * @param  channel: ADC_CHANNEL_0 (fuel) hoặc ADC_CHANNEL_1 (battery)
 * @return Giá trị ADC 12-bit (0-4095), 0 nếu lỗi
 */
static uint16_t ADC_ReadChannel(uint32_t channel)
{
    ADC_ChannelConfTypeDef sConfig = {0};
    uint16_t value = 0;

    sConfig.Channel = channel;
    sConfig.Rank = ADC_REGULAR_RANK_1;
    sConfig.SamplingTime = ADC_SAMPLETIME_239CYCLES_5;

    if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK) {
        return 0;
    }

    HAL_ADC_Start(&hadc1);
    if (HAL_ADC_PollForConversion(&hadc1, 10) == HAL_OK) {
        value = (uint16_t)HAL_ADC_GetValue(&hadc1);
    }
    HAL_ADC_Stop(&hadc1);

    return value;
}

/**
 * @brief  Tính trung bình của mảng mẫu
 */
static uint16_t ADC_Average(const uint16_t *samples, uint8_t count)
{
    uint32_t sum = 0;
    for (uint8_t i = 0; i < count; i++) {
        sum += samples[i];
    }
    return (uint16_t)(sum / count);
}

/* ============ API ============ */

void ADC_Handler_Init(void)
{
    /* Calibrate ADC để tăng độ chính xác */
    HAL_ADCEx_Calibration_Start(&hadc1);

    /* Reset dữ liệu */
    g_adc.fuel_raw = 0;
    g_adc.battery_raw = 0;
    g_adc.fuel_percent = 0.0f;
    g_adc.battery_percent = 0.0f;

    sample_index = 0;

    /* Đọc trước ADC_FILTER_SAMPLES lần để khởi tạo bộ lọc */
    for (uint8_t i = 0; i < ADC_FILTER_SAMPLES; i++) {
        fuel_samples[i] = ADC_ReadChannel(ADC_CHANNEL_0);
        battery_samples[i] = ADC_ReadChannel(ADC_CHANNEL_1);
    }
}

void ADC_Handler_Update(void)
{
    /* Đọc mẫu mới vào bộ lọc vòng (ring buffer) */
    fuel_samples[sample_index] = ADC_ReadChannel(ADC_CHANNEL_0);
    battery_samples[sample_index] = ADC_ReadChannel(ADC_CHANNEL_1);
    sample_index = (sample_index + 1) % ADC_FILTER_SAMPLES;

    /* Tính trung bình */
    g_adc.fuel_raw = ADC_Average(fuel_samples, ADC_FILTER_SAMPLES);
    g_adc.battery_raw = ADC_Average(battery_samples, ADC_FILTER_SAMPLES);

    /* Chuyển đổi sang phần trăm (0.0 - 1.0) cho Dashboard UI */
    g_adc.fuel_percent = (float)g_adc.fuel_raw / (float)ADC_MAX_VALUE;
    g_adc.battery_percent = (float)g_adc.battery_raw / (float)ADC_MAX_VALUE;

    /* Clamp giá trị */
    if (g_adc.fuel_percent > 1.0f) g_adc.fuel_percent = 1.0f;
    if (g_adc.battery_percent > 1.0f) g_adc.battery_percent = 1.0f;
}
