//+------------------------------------------------------------------+
//|                                          RegimeDefinitions.mqh   |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// 시장 레짐 열거형
enum ENUM_MARKET_REGIME {
   REGIME_UNKNOWN = 0,                // 알 수 없음
   REGIME_STRONG_BULLISH = 1,         // 강한 상승 모멘텀
   REGIME_STRONG_BEARISH = 2,         // 강한 하락 모멘텀
   REGIME_CONSOLIDATION = 3,          // 통합 레인지
   REGIME_VOLATILITY_EXPANSION = 4,   // 변동성 확장
   REGIME_OVERNIGHT_DRIFT = 5,        // 오버나이트 드리프트
   REGIME_GAP_TRADING = 6,            // 갭 트레이딩 패턴
   REGIME_TECHNICAL_REVERSAL = 7      // 기술적 되돌림
};

// 세션 유형 열거형
enum ESessionType {
   SESSION_UNKNOWN = 0,  // 알 수 없음
   SESSION_ASIA,         // 아시아 세션
   SESSION_EUROPE,       // 유럽 세션
   SESSION_US            // 미국 세션
};

// 레짐 데이터 구조체
struct SRegimeData {
   ENUM_MARKET_REGIME dominant_regime;    // 지배적 레짐
   double regime_scores[8];               // 각 레짐별 점수 (인덱스는 ENUM_MARKET_REGIME와 일치)
   double confidence;                     // 신뢰도 (0.0 ~ 1.0)
};

// 지표 그룹 구조체
struct SIndicatorGroup {
   double trend_indicators[5];      // 추세 지표 값 배열
   double momentum_indicators[5];   // 모멘텀 지표 값 배열
   double volatility_indicators[5]; // 변동성 지표 값 배열
   double volume_indicators[5];     // 거래량 지표 값 배열
   double bb_width_values[5];       // 최근 5봉의 볼린저 밴드 폭
   double atr_values[5];             // 최근 5봉의 ATR 값

// N봉 데이터 저장 배열
   double ema_values[5];            // 최근 5봉의 EMA 값
   double rsi_values[5];            // 최근 5봉의 RSI 값
   double adx_values[5];            // 최근 5봉의 ADX 값
   double di_plus_values[5];        // 최근 5봉의 DI+ 값
   double di_minus_values[5];       // 최근 5봉의 DI- 값
   
};


// 세션 경계 시간 구조체
struct SSessionTimes {
   int asia_start_hour;      // 아시아 세션 시작 시간
   int asia_end_hour;        // 아시아 세션 종료 시간
   int europe_start_hour;    // 유럽 세션 시작 시간
   int europe_end_hour;      // 유럽 세션 종료 시간
   int us_start_hour;        // 미국 세션 시작 시간
   int us_end_hour;          // 미국 세션 종료 시간
};