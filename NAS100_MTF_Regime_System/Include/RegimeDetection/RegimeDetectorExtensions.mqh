//+------------------------------------------------------------------+
//|                                 RegimeDetectorExtensions.mqh     |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "RegimeDefinitions.mqh"
#include "RegimeDetector.mqh" 
#include "..\Utils\Logger.mqh"

// 전역 정적 핸들 선언
static int g_adx_handle = INVALID_HANDLE;
static int g_rsi_handle = INVALID_HANDLE;
static int g_ma_handle = INVALID_HANDLE;
static int g_atr_handle = INVALID_HANDLE;
static int g_bands_handle = INVALID_HANDLE;

// 지표 데이터 가져오기 (EA에서 사용)
bool GetIndicatorValues(CRegimeDetector* detector, ENUM_TIMEFRAMES tf, double &adx_value, double &rsi_value, 
                       double &ma_slope, double &atr_value, double &bb_width, double &volume_ratio)
{
    if(detector == NULL) return false;
    
    // RegimeDetector에서 지표 데이터 가져오기
    SIndicatorGroup indicators;
    if(!detector.GetIndicatorValues(tf, indicators)) {
        LogError("RegimeDetector에서 지표 데이터 가져오기 실패");
        return false;
    }
    
    // 개별 값 추출
    adx_value = indicators.trend_indicators[0];
    rsi_value = indicators.momentum_indicators[0];
    ma_slope = indicators.trend_indicators[2];
    atr_value = indicators.volatility_indicators[0];
    bb_width = indicators.volatility_indicators[2];
    volume_ratio = indicators.volume_indicators[0];
    
    // 값 검증
    if(adx_value < 0 || adx_value > 100) {
        LogWarning("ADX 값이 범위를 벗어남: " + DoubleToString(adx_value, 2));
        return false;
    }
    
    if(rsi_value < 0 || rsi_value > 100) {
        LogWarning("RSI 값이 범위를 벗어남: " + DoubleToString(rsi_value, 2));
        return false;
    }
    
    if(atr_value <= 0) {
        LogWarning("ATR 값이 0 이하: " + DoubleToString(atr_value, 8));
        return false;
    }
    
    return true;
}

// 히스테리시스 정보 가져오기 (기본 추정)
bool GetHysteresisInfo(ENUM_MARKET_REGIME prev_regime, ENUM_MARKET_REGIME current_regime, 
                       int hold_count, int hysteresis_bars, bool &hysteresis_applied)
{
   hysteresis_applied = (prev_regime != REGIME_UNKNOWN) && 
                       (prev_regime != current_regime) && 
                       (hold_count < hysteresis_bars);
   
   return true;
}

// 지표 핸들 해제 함수
void ReleaseIndicatorHandles()
{
   if(g_adx_handle != INVALID_HANDLE) {
      IndicatorRelease(g_adx_handle);
      g_adx_handle = INVALID_HANDLE;
   }
   
   if(g_rsi_handle != INVALID_HANDLE) {
      IndicatorRelease(g_rsi_handle);
      g_rsi_handle = INVALID_HANDLE;
   }
   
   if(g_ma_handle != INVALID_HANDLE) {
      IndicatorRelease(g_ma_handle);
      g_ma_handle = INVALID_HANDLE;
   }
   
   if(g_atr_handle != INVALID_HANDLE) {
      IndicatorRelease(g_atr_handle);
      g_atr_handle = INVALID_HANDLE;
   }
   
   if(g_bands_handle != INVALID_HANDLE) {
      IndicatorRelease(g_bands_handle);
      g_bands_handle = INVALID_HANDLE;
   }
}