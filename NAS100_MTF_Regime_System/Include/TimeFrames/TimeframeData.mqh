//+------------------------------------------------------------------+
//|                                            TimeframeData.mqh      |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "../RegimeDetection/RegimeDefinitions.mqh"
#include "../Utils/Logger.mqh"

// 타임프레임 데이터 구조체
struct STimeframeData {
   ENUM_TIMEFRAMES timeframe;     // 타임프레임
   MqlRates rates[];              // 가격 데이터 배열
   int bars_count;                // 저장된 봉 개수
   datetime last_update;          // 마지막 업데이트 시간
   SRegimeData regime_data;       // 이 타임프레임의 레짐 데이터
};

// 타임프레임 조합 구조체
struct STimeframeCombo {
   ENUM_TIMEFRAMES primary_tf;      // 주 타임프레임 (진입/청산용, 보통 M5)
   ENUM_TIMEFRAMES confirm_tf;      // 확인 타임프레임 (방향/패턴 확인용)
   ENUM_TIMEFRAMES filter_tf;       // 필터 타임프레임 (큰 그림/추세 확인용)
   double weights[3];               // 각 타임프레임 가중치 [주, 확인, 필터]
};