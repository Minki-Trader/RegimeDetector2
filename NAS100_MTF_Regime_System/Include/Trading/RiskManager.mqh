//+------------------------------------------------------------------+
//|                                            RiskManager.mqh       |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#ifndef __RISK_MANAGER_MQH__
#define __RISK_MANAGER_MQH__

#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "../RegimeDetection/RegimeDefinitions.mqh"
#include "../Utils/Logger.mqh"

// 리스크 계산 결과 구조체
struct SRiskCalculationResult {
   bool is_valid;                 // 계산 결과 유효성
   double suggested_lots;         // 제안 랏 사이즈
   double actual_risk_amount;     // 실제 리스크 금액
   double risk_percentage;        // 리스크 비율
   double margin_required;        // 필요 마진
   double margin_available;       // 사용 가능 마진
   string validation_message;     // 검증 메시지
};

// 포지션 리스크 정보 구조체
struct SPositionRisk {
   double total_exposure;         // 총 노출 금액
   double unrealized_pnl;         // 미실현 손익
   double used_margin;            // 사용 중인 마진
   double free_margin;            // 여유 마진
   double margin_level;           // 마진 레벨
   int total_positions;           // 총 포지션 수
   double largest_loss_potential; // 최대 잠재 손실
};

class CRiskManager {
private:
   string m_symbol;
   
   // 리스크 관리 설정
   double m_max_risk_per_trade;     // 거래당 최대 리스크 비율 (%)
   double m_max_total_risk;         // 총 최대 리스크 비율 (%)
   double m_max_daily_loss;         // 일일 최대 손실 한도
   double m_max_drawdown;           // 최대 드로다운 한도
   int m_max_positions;             // 최대 포지션 수
   double m_max_lot_size;           // 최대 랏 사이즈
   double m_emergency_close_level;  // 긴급 청산 레벨
   
   // Invalid Stops 방지를 위한 심볼 정보 캐싱
   double m_point;                  // 심볼 포인트
   int m_digits;                    // 소수점 자리수
   double m_tick_size;              // 틱 사이즈
   double m_tick_value;             // 틱 가치
   int m_stops_level;               // 최소 스탑 거리
   int m_freeze_level;              // 동결 거리
   double m_min_lot;                // 최소 랏
   double m_max_lot;                // 최대 랏
   double m_lot_step;               // 랏 스텝
   double m_contract_size;          // 계약 사이즈
   
   // 일일 통계 추적
   double m_daily_starting_balance; // 일일 시작 잔고
   double m_daily_pnl;              // 일일 손익
   double m_peak_balance;           // 최고 잔고
   datetime m_last_reset_date;      // 마지막 리셋 날짜
   
   // 내부 메서드들
   bool UpdateSymbolInfo();
   double NormalizePrice(double price);
   double NormalizeLots(double lots);
   double GetMinStopDistance();
   bool ValidateAndAdjustStops(double entry_price, double &sl_price, double &tp_price, ENUM_ORDER_TYPE order_type);
   bool CheckFreezeLevel(ENUM_ORDER_TYPE order_type, double order_price);
   bool IsMarketOpen();
   void UpdateDailyStats();
   bool CheckDailyLimits();
   double CalculatePointValue();
   SPositionRisk GetCurrentPositionRisk();
   
   inline double  ToPoints(double price_diff)      { return price_diff / m_point; }
   inline double  ToPrice (double points)          { return points * m_point; }
   inline double  ClampLots(double lots_raw)       { return NormalizeLots(lots_raw); }
   inline double  MaxLoss (double lots, double pts){ return lots * pts * CalculatePointValue(); }
   

public:
   // 생성자 및 소멸자
   CRiskManager(string symbol);
   ~CRiskManager();
   
   // 초기화 및 설정
   bool Initialize();
   void SetRiskParameters(double max_risk_per_trade, double max_total_risk, 
                         double max_daily_loss, int max_positions);
   void SetMaxLotSize(double max_lot) { m_max_lot_size = max_lot; }
   void SetEmergencyLevel(double level) { m_emergency_close_level = level; }
   
   // === StrategySelector 호환 메서드들 ===
   bool ValidateRisk(double lots, double sl_distance, double account_balance);
   double GetMaxAllowedLots();
   double GetMaxAllowedLots(double account_balance, double risk_percent = 2.0);
   SRiskCalculationResult CalculateOptimalPosition(double risk_amount, double entry_price, 
                                                  double sl_price, double account_balance);
   
   // === ExecutionManager 호환 메서드들 ===
   bool ValidateRiskBeforeOrder(double lots, double sl_distance);
   bool CheckMarginRequirement(ENUM_ORDER_TYPE order_type, double lots, double price);
   bool IsMaxPositionsReached();
   bool CanOpenNewPosition(double lots, double sl_distance);
   
   // 포지션 사이즈 계산 (핵심 메서드들)
   double CalculateSafePositionSize(double risk_amount, double entry_price, double sl_price);
   double CalculatePositionSizeByRiskPercent(double risk_percent, double entry_price, double sl_price);
   double CalculatePositionSizeByFixedAmount(double fixed_risk_usd, double entry_price, double sl_price);
   
   // SL/TP 계산 및 조정 (Invalid Stops 완전 방지)
   bool CalculateSafeStops(double entry_price, ENUM_ORDER_TYPE order_type,
                          double atr, double sl_multiplier, double tp_multiplier,
                          double &sl_price, double &tp_price);
   bool AdjustStopsForBroker(double entry_price, double &sl_price, double &tp_price, ENUM_ORDER_TYPE order_type);
   bool ValidateStopLevels(double entry_price, double sl_price, double tp_price, ENUM_ORDER_TYPE order_type);
   
   // 리스크 분석 및 모니터링
   SPositionRisk AnalyzeCurrentRisk();
   double GetCurrentRiskExposure();
   double GetAvailableRiskCapacity();
   bool IsRiskLimitExceeded();
   bool IsEmergencyLevelReached();
   
   // 일일 리스크 관리
   void ResetDailyStats();
   double GetDailyPnL();
   double GetDailyRiskUsed();
   bool IsDailyLimitReached();
   
   // 포지션 관리 지원
   bool ShouldReducePosition();
   double GetRecommendedPositionReduction();
   bool ShouldStopTrading();
   
   // 마진 관리
   double GetUsedMargin();
   double GetFreeMargin();
   double GetMarginLevel();
   bool HasSufficientMargin(double required_margin);
   
   // 유틸리티 메서드들
   double ConvertRiskToLots(double risk_usd, double sl_points);
   double ConvertLotsToRisk(double lots, double sl_points);
   double CalculateMaxLossForPosition(double lots, double sl_points);
   string GetRiskStatusReport();
   
   // 디버깅 및 모니터링
   void LogCurrentRiskStatus();
   bool SelfTest();  // 리스크 매니저 자체 테스트
};

//+------------------------------------------------------------------+
//| 생성자                                                           |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager(string symbol) {
   m_symbol = symbol;
   
   // 기본 리스크 설정
   m_max_risk_per_trade = 2.0;      // 거래당 2%
   m_max_total_risk = 10.0;         // 총 10%
   m_max_daily_loss = 5.0;          // 일일 5%
   m_max_drawdown = 15.0;           // 최대 드로다운 15%
   m_max_positions = 5;             // 최대 5개 포지션
   m_max_lot_size = 10.0;           // 최대 10랏
   m_emergency_close_level = 20.0;  // 마진레벨 20% 이하시 긴급청산
   
   // 통계 초기화
   m_daily_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_daily_pnl = 0.0;
   m_peak_balance = m_daily_starting_balance;
   m_last_reset_date = TimeCurrent();
   
   UpdateSymbolInfo();
}

//+------------------------------------------------------------------+
//| 소멸자                                                           |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager() {
   // 필요한 정리 작업
}

//+------------------------------------------------------------------+
//| 초기화                                                           |
//+------------------------------------------------------------------+
bool CRiskManager::Initialize() {
   LogInfo("RiskManager::Initialize() 시작");
   
   if(!UpdateSymbolInfo()) {
      LogError("심볼 정보 업데이트 실패");
      return false;
   }
   
   if(!IsMarketOpen()) {
      LogWarning("현재 시장이 닫혀있습니다");
   }
   
   UpdateDailyStats();
   
   LogInfo("RiskManager 초기화 완료");
   LogInfo("최대 거래당 리스크: " + DoubleToString(m_max_risk_per_trade, 1) + "%");
   LogInfo("최대 총 리스크: " + DoubleToString(m_max_total_risk, 1) + "%");
   
   return true;
}

//+------------------------------------------------------------------+
//| 심볼 정보 업데이트                                               |
//+------------------------------------------------------------------+
bool CRiskManager::UpdateSymbolInfo() {
   m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   m_tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   m_stops_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   m_freeze_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   m_min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   m_max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   m_lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   m_contract_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   bool valid = (m_point > 0 && m_tick_size > 0 && m_tick_value > 0);
   
   if(valid) {
      LogDebug("심볼 정보 업데이트 완료: " + m_symbol);
      LogDebug("포인트=" + DoubleToString(m_point, 8) + ", 틱크기=" + DoubleToString(m_tick_size, 8));
   } else {
      LogError("심볼 정보가 유효하지 않음: " + m_symbol);
   }
   
   return valid;
}

//+------------------------------------------------------------------+
//| StrategySelector 호환: 리스크 검증                               |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateRisk(double lots, double sl_distance, double account_balance) {
   if(lots <= 0 || sl_distance <= 0) return false;
   
   // 1. 랏 사이즈 기본 검증
   if(lots < m_min_lot || lots > m_max_lot_size) {
      LogWarning("랏 사이즈 범위 초과: " + DoubleToString(lots, 2));
      return false;
   }
   
   // 2. 리스크 금액 계산
   double risk_amount = CalculateMaxLossForPosition(lots, sl_distance / m_point);
   double risk_percent = (risk_amount / account_balance) * 100.0;
   
   // 3. 거래당 리스크 한도 검증
   if(risk_percent > m_max_risk_per_trade) {
      LogWarning("거래당 리스크 한도 초과: " + DoubleToString(risk_percent, 2) + 
                "% > " + DoubleToString(m_max_risk_per_trade, 2) + "%");
      return false;
   }
   
   // 4. 총 리스크 검증
   double current_risk = GetCurrentRiskExposure();
   double total_risk_percent = ((current_risk + risk_amount) / account_balance) * 100.0;
   
   if(total_risk_percent > m_max_total_risk) {
      LogWarning("총 리스크 한도 초과: " + DoubleToString(total_risk_percent, 2) + 
                "% > " + DoubleToString(m_max_total_risk, 2) + "%");
      return false;
   }
   
   // 5. 일일 한도 검증
   if(!CheckDailyLimits()) {
      LogWarning("일일 리스크 한도 도달");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 최대 허용 랏 계산                                                |
//+------------------------------------------------------------------+
double CRiskManager::GetMaxAllowedLots() {
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return GetMaxAllowedLots(account_balance, m_max_risk_per_trade);
}

double CRiskManager::GetMaxAllowedLots(double account_balance, double risk_percent) {
   if(account_balance <= 0 || risk_percent <= 0) return 0;
   
   double max_risk_amount = account_balance * (risk_percent / 100.0);
   
   // 기본 SL 거리 가정 (2 ATR, 여기서는 100포인트로 가정)
   double default_sl_points = 100.0;
   double point_value = CalculatePointValue();
   
   if(point_value <= 0) return 0;
   
   double max_lots = max_risk_amount / (default_sl_points * point_value);
   max_lots = NormalizeLots(max_lots);
   
   // 최대 랏 사이즈 제한 적용
   if(max_lots > m_max_lot_size) {
      max_lots = m_max_lot_size;
   }
   
   return max_lots;
}

//+------------------------------------------------------------------+
//| 안전한 포지션 사이즈 계산                                        |
//+------------------------------------------------------------------+
double CRiskManager::CalculateSafePositionSize(double risk_amount, double entry_price, double sl_price) {
   if(!UpdateSymbolInfo()) return 0;
   
   // SL 거리 계산
   double sl_distance = MathAbs(entry_price - sl_price);
   if(sl_distance <= 0) {
      LogError("SL 거리가 0 이하: " + DoubleToString(sl_distance, 8));
      return 0;
   }
   
   // 포인트 가치 계산
   double point_value = CalculatePointValue();
   if(point_value <= 0) {
      LogError("포인트 가치 계산 실패");
      return 0;
   }
   
   // 랏 사이즈 계산
   double sl_points = sl_distance / m_point;
   double lots = risk_amount / (sl_points * point_value);
   
   lots = ClampLots(lots);
   
   LogDebug("포지션 사이즈 계산: 리스크=" + DoubleToString(risk_amount, 2) + 
           ", SL거리=" + DoubleToString(sl_points, 0) + "pt" +
           ", 랏=" + DoubleToString(lots, 2));
   
   return lots;
}

//+------------------------------------------------------------------+
//| 안전한 SL/TP 계산 (Invalid Stops 완전 방지)                     |
//+------------------------------------------------------------------+
bool CRiskManager::CalculateSafeStops(double          entry_price,
                                      ENUM_ORDER_TYPE order_type,
                                      double          atr,             // ↔ points 또는 price
                                      double          sl_multiplier,
                                      double          tp_multiplier,
                                      double         &sl_price,
                                      double         &tp_price)
{
   /* ---------- 0. 선행 검증 ---------- */
   if(!UpdateSymbolInfo() || !IsMarketOpen())
      return false;

   /* ---------- 1. ATR 단위 보정 ----------
      ▸  대부분 브로커: 1 point = m_point (ex: 0.0001)
      ▸  atr 값이 ‘point’ 로 들어오면 0.0001~0.01 수준이므로
         m_point×50 보다 작다고 간주 → 가격-단위로 변환        */
   double atr_price = atr;                    // default: 이미 price-단위
   if(atr > 0 && atr < m_point * 50.0)        // 휴리스틱
      atr_price = atr * m_point;              // points → price

   /* ---------- 2. 기본 거리 계산 ---------- */
   double base_distance = atr_price * sl_multiplier;

   /* ---------- 3. 최소 StopLevel & Spread ---------- */
   double min_distance = GetMinStopDistance();   // 이미 price-단위
   if(base_distance < min_distance)
   {
      base_distance = min_distance;
      LogWarning(StringFormat("ATR 거리(%.*f) < 최소 StopLevel → %.1f pt로 조정",
                              _Digits, atr_price, min_distance/m_point));
   }

   /* ---------- 4. SL / TP 산출 ---------- */
   if(order_type==ORDER_TYPE_BUY  || order_type==ORDER_TYPE_BUY_LIMIT  || order_type==ORDER_TYPE_BUY_STOP)
   {
      sl_price = entry_price - base_distance;
      tp_price = entry_price + base_distance * tp_multiplier;
   }
   else if(order_type==ORDER_TYPE_SELL || order_type==ORDER_TYPE_SELL_LIMIT || order_type==ORDER_TYPE_SELL_STOP)
   {
      sl_price = entry_price + base_distance;
      tp_price = entry_price - base_distance * tp_multiplier;
   }
   else
   {
      LogError("지원하지 않는 주문 타입: " + EnumToString(order_type));
      return false;
   }

   /* ---------- 5. SL·TP 가격 정규화 ---------- */
   sl_price = NormalizePrice(sl_price);
   tp_price = NormalizePrice(tp_price);

   /* ---------- 6. 최종 검증 & Freeze-level ---------- */
   if(!ValidateAndAdjustStops(entry_price, sl_price, tp_price, order_type))
      return false;

   /* Freeze-level : 현재가-Entry / SL / TP 모두 확인 */
   bool ok = true;
   ok &= CheckFreezeLevel(order_type, entry_price);
   if(sl_price>0) ok &= CheckFreezeLevel(order_type, sl_price);
   if(tp_price>0) ok &= CheckFreezeLevel(order_type, tp_price);

   if(!ok)
   {
      LogError("Freeze-level 위반 : Entry/SL/TP 중 최소 한 지점이 너무 가까움");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| SL/TP 검증 및 조정                                               |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateAndAdjustStops(double entry_price, double &sl_price, double &tp_price, 
                                         ENUM_ORDER_TYPE order_type) {
   double min_distance = GetMinStopDistance();
   
   if(order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP) {
      // 매수 주문: SL은 진입가 아래, TP는 진입가 위
      if(sl_price > 0) {
         double sl_distance = entry_price - sl_price;
         if(sl_distance < min_distance) {
            sl_price = entry_price - min_distance;
            LogWarning("매수 SL 거리 조정: " + DoubleToString(min_distance/m_point, 0) + " 포인트");
         }
         sl_price = NormalizePrice(sl_price);
      }
      
      if(tp_price > 0) {
         double tp_distance = tp_price - entry_price;
         if(tp_distance < min_distance) {
            tp_price = entry_price + min_distance;
            LogWarning("매수 TP 거리 조정: " + DoubleToString(min_distance/m_point, 0) + " 포인트");
         }
         tp_price = NormalizePrice(tp_price);
      }
   }
   else if(order_type == ORDER_TYPE_SELL || order_type == ORDER_TYPE_SELL_LIMIT || order_type == ORDER_TYPE_SELL_STOP) {
      // 매도 주문: SL은 진입가 위, TP는 진입가 아래
      if(sl_price > 0) {
         double sl_distance = sl_price - entry_price;
         if(sl_distance < min_distance) {
            sl_price = entry_price + min_distance;
            LogWarning("매도 SL 거리 조정: " + DoubleToString(min_distance/m_point, 0) + " 포인트");
         }
         sl_price = NormalizePrice(sl_price);
      }
      
      if(tp_price > 0) {
         double tp_distance = entry_price - tp_price;
         if(tp_distance < min_distance) {
            tp_price = entry_price - min_distance;
            LogWarning("매도 TP 거리 조정: " + DoubleToString(min_distance/m_point, 0) + " 포인트");
         }
         tp_price = NormalizePrice(tp_price);
      }
   }
   
   // ─────────────── Fix ───────────────
   // SL·TP·진입가 모두 freeze-level 만족해야 통과
   bool ok = true;

   // ① 진입가
   ok &= CheckFreezeLevel(order_type, entry_price);

   // ② SL (0 이면 설정 안 한 것 → 검사 생략)
   if(sl_price > 0)
       ok &= CheckFreezeLevel(order_type, sl_price);

   // ③ TP (0 이면 검사 생략)
   if(tp_price > 0)
       ok &= CheckFreezeLevel(order_type, tp_price);

   if(!ok)
       LogError("FreezeLevel 위반: 진입/SL/TP 거리 중 하나가 부족");

   return ok;
}

//+------------------------------------------------------------------+
//| 최소 스탑 거리 계산                                              |
//+------------------------------------------------------------------+
double CRiskManager::GetMinStopDistance() {
   // ① 스프레드와 브로커 stop-level(포인트)을 “가격 거리”로 변환
   const double spread_price       = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * m_point;
   const double stop_level_price   = m_stops_level * m_point;

   // ② 둘 중 더 큰 값을 “기준 거리”로 사용
   double base_distance = MathMax(spread_price, stop_level_price);

   // ③ safety margin — 틱·포인트가 아니라 “가격” 으로 2틱만 추가
   //    (필요하면 외부 파라미터로 노출하여 심볼마다 조정 가능)
   const double safety_margin_price = 2 * m_tick_size;   // 2 tick ≈ 1 pip 대부분

   return base_distance + safety_margin_price;
}

//+------------------------------------------------------------------+
//| 가격 정규화                                                      |
//+------------------------------------------------------------------+
double CRiskManager::NormalizePrice(double price) {
   if(m_tick_size > 0) {
      return MathRound(price / m_tick_size) * m_tick_size;
   }
   return NormalizeDouble(price, m_digits);
}

//+------------------------------------------------------------------+
//| 랏 사이즈 정규화                                                 |
//+------------------------------------------------------------------+
double CRiskManager::NormalizeLots(double lots) {
    
    /* ① 스텝 크기 기준으로 항상 “버림” */
   if(m_lot_step > 0)
   {
      lots = MathFloor(lots / m_lot_step) * m_lot_step;

      /* ② 버림 결과가 0 이면 최소 step 만큼 보정
            (lot_step 자체가 최소 랏보다 작을 수 있기에 그 이후 제한은
             아래 기존 min/max 로직에서 최종 결정된다)           */
      if(lots <= 0.0)
         lots = m_lot_step;
   }
   
   // 최소/최대 랏 제한
   if(lots < m_min_lot) lots = m_min_lot;
   if(lots > m_max_lot) lots = m_max_lot;
   if(lots > m_max_lot_size) lots = m_max_lot_size;
   
   return lots;
}

//+------------------------------------------------------------------+
//| 동결 거리 검증                                                   |
//+------------------------------------------------------------------+
bool CRiskManager::CheckFreezeLevel(ENUM_ORDER_TYPE order_type,
                                    double order_price)   
{
   if(m_freeze_level == 0)            // 브로커가 freeze-level 0 이면 통과   
      return true;

   // ① 현재가 선택 : BUY-side = Ask, SELL-side = Bid
   double current_price =
      (order_type == ORDER_TYPE_BUY  || order_type == ORDER_TYPE_BUY_LIMIT  || order_type == ORDER_TYPE_BUY_STOP)
      ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
      : SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // ② 거리 계산
   double freeze_distance = m_freeze_level * m_point;
   double actual_distance = MathAbs(current_price - order_price);
    
   if(actual_distance < freeze_distance) {
      LogError("동결 거리 위반: " + DoubleToString(actual_distance/m_point, 0) + 
              " < " + DoubleToString(freeze_distance/m_point, 0) + " pt");
      return false;
   }
    
   return true;
}


//+------------------------------------------------------------------+
//| 시장 상태 검증                                                   |
//+------------------------------------------------------------------+
bool CRiskManager::IsMarketOpen()
{
   /* ────────── ① 요일·세션 루프로 ‘하나라도 열려 있으면 OK’ ────────── */
   bool has_trade_session = false;
   datetime from , to;

   for(int day = SUNDAY; day <= SATURDAY && !has_trade_session; ++day)
   {
      for(int sess = 0; sess < 7 && !has_trade_session; ++sess)
      {
         if(SymbolInfoSessionTrade(m_symbol, (ENUM_DAY_OF_WEEK)day, sess, from, to))
            has_trade_session = true;
      }
   }

   if(!has_trade_session)
      return false;                       // 심볼이 주 7일 모두 휴장이라면 false

   /* ────────── ② 브로커 trade-mode 가 ‘거래불가’ 면 닫힘 ────────── */
   long mode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
   bool enabled = (mode != SYMBOL_TRADE_MODE_DISABLED);

   return enabled;
}

//+------------------------------------------------------------------+
//| 포인트 가치 계산                                                 |
//+------------------------------------------------------------------+
double CRiskManager::CalculatePointValue()
{
   // ───── 기본 자료가 정상일 때 ─────
   if(m_tick_value  > 0 &&
      m_tick_size   > 0 &&
      m_point       > 0)
   {
         double pv =  m_tick_value / m_tick_size * m_point;   // ← 순서 수정
         LogDebug("포인트 가치(Tick 기반): "+DoubleToString(pv,8));
         return pv;
     }

     // ───── Fallback ① : 계약가치로 계산 ─────
     // 일반적으로 1 Point 움직일 때 손익 = 계약크기 × 1 Point
     if(m_contract_size > 0 && m_point > 0)
     {
         double pv =  m_contract_size * m_point;
         LogWarning("TickValue=0 → 계약크기 기반 point-value 사용: "+
                    DoubleToString(pv,8));
         return pv;
     }

     // ───── Fallback ② : 최후의 보루 (1 통화단위) ─────
     LogError("PointValue 계산 실패 – 기본값 1 적용");
     return 1.0;
}

//+------------------------------------------------------------------+
//| ExecutionManager 호환: 리스크 검증                               |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateRiskBeforeOrder(double lots, double sl_distance) {
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return ValidateRisk(lots, sl_distance, account_balance);
}

//+------------------------------------------------------------------+
//| 마진 요구사항 확인                                               |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMarginRequirement(ENUM_ORDER_TYPE order_type, double lots, double price) {
   double required_margin = 0;
   
   // 마진 계산
   if(!OrderCalcMargin(order_type, m_symbol, lots, price, required_margin)) {
      LogError("마진 계산 실패");
      return false;
   }
   
   double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   
   if(required_margin > free_margin) {
      LogError("마진 부족: 필요=" + DoubleToString(required_margin, 2) +
               ", 여유=" + DoubleToString(free_margin, 2));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 최대 포지션 수 도달 확인                                         |
//+------------------------------------------------------------------+
bool CRiskManager::IsMaxPositionsReached() {
   int current_positions = PositionsTotal();
   return (current_positions >= m_max_positions);
}

//+------------------------------------------------------------------+
//| 새 포지션 오픈 가능 여부                                         |
//+------------------------------------------------------------------+
bool CRiskManager::CanOpenNewPosition(double lots, double sl_distance) {
   // 1. 최대 포지션 수 확인
   if(IsMaxPositionsReached()) {
      LogWarning("최대 포지션 수 도달");
      return false;
   }
   
   // 2. 리스크 검증
   if(!ValidateRiskBeforeOrder(lots, sl_distance)) {
      return false;
   }
   
   // 3. 마진 확인 (대략적)
   double current_price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   if(!CheckMarginRequirement(ORDER_TYPE_BUY, lots, current_price)) {
      return false;
   }
   
   // 4. 일일 한도 확인
   if(!CheckDailyLimits()) {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 현재 리스크 노출 계산                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentRiskExposure() {
   double total_risk = 0;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == m_symbol) {
         double lots = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl_price = PositionGetDouble(POSITION_SL);
         
         if(sl_price > 0) {
            double sl_distance = MathAbs(open_price - sl_price);
            double position_risk = CalculateMaxLossForPosition(lots, sl_distance / m_point);
            total_risk += position_risk;
         }
      }
   }
   
   return total_risk;
}

//+------------------------------------------------------------------+
//| 포지션 최대 손실 계산                                            |
//+------------------------------------------------------------------+
double CRiskManager::CalculateMaxLossForPosition(double lots, double sl_points) {
   double point_value = CalculatePointValue();
   return lots * sl_points * point_value;
}

//+------------------------------------------------------------------+
//| 일일 통계 업데이트                                               |
//+------------------------------------------------------------------+
void CRiskManager::UpdateDailyStats() {
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   
   MqlDateTime last_dt;
   TimeToStruct(m_last_reset_date, last_dt);
   
   // 새로운 날이면 일일 통계 리셋
   if(dt.day != last_dt.day || dt.mon != last_dt.mon || dt.year != last_dt.year) {
    ResetDailyStats();
    LogInfo("새로운 거래일 시작 - 일일 통계 리셋");
    } else if(dt.day_of_week == 0 || dt.day_of_week == 6) {
        // 주말에는 리셋하지 않음
        LogDebug("주말 - 일일 통계 유지");
    }
   
   // 현재 손익 계산
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_daily_pnl = current_balance - m_daily_starting_balance;
   
   // 최고 잔고 업데이트
   if(current_balance > m_peak_balance) {
      m_peak_balance = current_balance;
   }
}

//+------------------------------------------------------------------+
//| 일일 통계 리셋                                                   |
//+------------------------------------------------------------------+
void CRiskManager::ResetDailyStats() {
   m_daily_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_daily_pnl = 0.0;
   m_last_reset_date = TimeCurrent();
   
   LogInfo("일일 통계 리셋 - 시작 잔고: " + DoubleToString(m_daily_starting_balance, 2));
}

//+------------------------------------------------------------------+
//| 일일 한도 확인                                                   |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDailyLimits() {
   UpdateDailyStats();
   
   // 일일 손실 한도 확인
   if(m_daily_pnl < 0) {
      double daily_loss_percent = (MathAbs(m_daily_pnl) / m_daily_starting_balance) * 100.0;
      if(daily_loss_percent >= m_max_daily_loss) {
         LogError("일일 손실 한도 도달: " + DoubleToString(daily_loss_percent, 2) + 
                 "% >= " + DoubleToString(m_max_daily_loss, 2) + "%");
         return false;
      }
   }
   
   // 드로다운 한도 확인
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown_percent = ((m_peak_balance - current_balance) / m_peak_balance) * 100.0;
   if(drawdown_percent >= m_max_drawdown) {
      LogError("최대 드로다운 도달: " + DoubleToString(drawdown_percent, 2) + 
              "% >= " + DoubleToString(m_max_drawdown, 2) + "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 일일 손익 반환                                                   |
//+------------------------------------------------------------------+
double CRiskManager::GetDailyPnL() {
   UpdateDailyStats();
   return m_daily_pnl;
}

//+------------------------------------------------------------------+
//| 일일 리스크 사용량 반환                                          |
//+------------------------------------------------------------------+
double CRiskManager::GetDailyRiskUsed() {
   double current_risk = GetCurrentRiskExposure();
   double daily_risk_percent = (current_risk / m_daily_starting_balance) * 100.0;
   return daily_risk_percent;
}

//+------------------------------------------------------------------+
//| 일일 한도 도달 여부                                              |
//+------------------------------------------------------------------+
bool CRiskManager::IsDailyLimitReached() {
   return !CheckDailyLimits();
}

//+------------------------------------------------------------------+
//| 현재 포지션 리스크 분석                                          |
//+------------------------------------------------------------------+
SPositionRisk CRiskManager::GetCurrentPositionRisk() {
   SPositionRisk risk;
   ZeroMemory(risk);
   
   risk.total_exposure = 0;
   risk.unrealized_pnl = 0;
   risk.total_positions = 0;
   risk.largest_loss_potential = 0;
   
   // 모든 포지션 순회
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == m_symbol) {
         double lots = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl_price = PositionGetDouble(POSITION_SL);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         // 총 노출 계산 (명목 가치)
         risk.total_exposure += lots * m_contract_size * current_price;
         
         // 미실현 손익 합계
         risk.unrealized_pnl += profit;
         
         // 포지션 수 카운트
         risk.total_positions++;
         
         // 최대 잠재 손실 계산
         if(sl_price > 0) {
            double sl_distance = MathAbs(open_price - sl_price);
            double potential_loss = CalculateMaxLossForPosition(lots, sl_distance / m_point);
            if(potential_loss > risk.largest_loss_potential) {
               risk.largest_loss_potential = potential_loss;
            }
         }
      }
   }
   
   // 마진 정보
   risk.used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
   risk.free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   risk.margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   return risk;
}

//+------------------------------------------------------------------+
//| 리스크 분석 (공개 메서드)                                        |
//+------------------------------------------------------------------+
SPositionRisk CRiskManager::AnalyzeCurrentRisk() {
   return GetCurrentPositionRisk();
}

//+------------------------------------------------------------------+
//| 사용 가능한 리스크 용량                                          |
//+------------------------------------------------------------------+
double CRiskManager::GetAvailableRiskCapacity() {
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double max_total_risk_amount = account_balance * (m_max_total_risk / 100.0);
   double current_risk = GetCurrentRiskExposure();
   
   return MathMax(0, max_total_risk_amount - current_risk);
}

//+------------------------------------------------------------------+
//| 리스크 한도 초과 여부                                            |
//+------------------------------------------------------------------+
bool CRiskManager::IsRiskLimitExceeded() {
   return !CheckDailyLimits() || GetAvailableRiskCapacity() <= 0;
}

//+------------------------------------------------------------------+
//| 긴급 레벨 도달 여부                                              |
//+------------------------------------------------------------------+
bool CRiskManager::IsEmergencyLevelReached() {
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   return (margin_level <= m_emergency_close_level && margin_level > 0);
}

//+------------------------------------------------------------------+
//| 포지션 축소 권장 여부                                            |
//+------------------------------------------------------------------+
bool CRiskManager::ShouldReducePosition() {
   // 포지션이 없으면 축소할 것도 없음!
   if(PositionsTotal() == 0) return false;
   
   // 1. 마진 레벨 확인
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_level <= 0 || margin_level > 10000) return false; // 비정상값 무시
   
   if(margin_level < m_emergency_close_level * 1.5) { // 1.5배 여유
      return true;
   }
   
   // 2. 일일 손실 확인
   UpdateDailyStats();
   if(m_daily_pnl < 0) {
      double loss_percent = (MathAbs(m_daily_pnl) / m_daily_starting_balance) * 100.0;
      if(loss_percent > m_max_daily_loss * 0.8) { // 80% 도달시
         return true;
      }
   }
   
   // 3. 총 리스크 확인
   double available_capacity = GetAvailableRiskCapacity();
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double capacity_percent = (available_capacity / account_balance) * 100.0;
   
   if(capacity_percent < 2.0) { // 2% 미만 남으면
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 권장 포지션 축소 비율                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetRecommendedPositionReduction() {
   if(!ShouldReducePosition()) return 0.0;
   
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   // 마진 레벨에 따른 축소 비율 결정
   if(margin_level < m_emergency_close_level) {
      return 1.0; // 100% 청산
   } else if(margin_level < m_emergency_close_level * 1.2) {
      return 0.75; // 75% 청산
   } else if(margin_level < m_emergency_close_level * 1.5) {
      return 0.5; // 50% 청산
   } else {
      return 0.25; // 25% 청산
   }
}

//+------------------------------------------------------------------+
//| 거래 중단 권장 여부                                              |
//+------------------------------------------------------------------+
bool CRiskManager::ShouldStopTrading() {
   return IsEmergencyLevelReached() || IsDailyLimitReached();
}

//+------------------------------------------------------------------+
//| 리스크를 랏으로 변환                                             |
//+------------------------------------------------------------------+
double CRiskManager::ConvertRiskToLots(double risk_usd, double sl_points) {
   if(sl_points <= 0) return 0;
   
   double point_value = CalculatePointValue();
   if(point_value <= 0) return 0;
   
   double lots = risk_usd / (sl_points * point_value);
   return NormalizeLots(lots);
}

//+------------------------------------------------------------------+
//| 랏을 리스크로 변환                                               |
//+------------------------------------------------------------------+
double CRiskManager::ConvertLotsToRisk(double lots, double sl_points) {
   return CalculateMaxLossForPosition(lots, sl_points);
}

//+------------------------------------------------------------------+
//| 마진 정보 메서드들                                               |
//+------------------------------------------------------------------+
double CRiskManager::GetUsedMargin() {
   return AccountInfoDouble(ACCOUNT_MARGIN);
}

double CRiskManager::GetFreeMargin() {
   return AccountInfoDouble(ACCOUNT_FREEMARGIN);
}

double CRiskManager::GetMarginLevel() {
   return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
}

bool CRiskManager::HasSufficientMargin(double required_margin) {
   return (GetFreeMargin() >= required_margin);
}

//+------------------------------------------------------------------+
//| 리스크 파라미터 설정                                             |
//+------------------------------------------------------------------+
void CRiskManager::SetRiskParameters(double max_risk_per_trade, double max_total_risk, 
                                     double max_daily_loss, int max_positions) {
   m_max_risk_per_trade = max_risk_per_trade;
   m_max_total_risk = max_total_risk;
   m_max_daily_loss = max_daily_loss;
   m_max_positions = max_positions;
   
   LogInfo("리스크 파라미터 업데이트:");
   LogInfo("- 거래당 최대 리스크: " + DoubleToString(m_max_risk_per_trade, 1) + "%");
   LogInfo("- 총 최대 리스크: " + DoubleToString(m_max_total_risk, 1) + "%");
   LogInfo("- 일일 최대 손실: " + DoubleToString(m_max_daily_loss, 1) + "%");
   LogInfo("- 최대 포지션 수: " + IntegerToString(m_max_positions));
}

//+------------------------------------------------------------------+
//| 리스크 상태 보고서                                               |
//+------------------------------------------------------------------+
string CRiskManager::GetRiskStatusReport() {
   UpdateDailyStats();
   SPositionRisk risk = GetCurrentPositionRisk();
   
   string report = "=== 리스크 상태 보고서 ===\n";
   report += "계정 잔고: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   report += "일일 손익: " + DoubleToString(m_daily_pnl, 2) + " (" + 
            DoubleToString((m_daily_pnl/m_daily_starting_balance)*100, 2) + "%)\n";
   report += "현재 포지션 수: " + IntegerToString(risk.total_positions) + "/" + IntegerToString(m_max_positions) + "\n";
   report += "총 노출: " + DoubleToString(risk.total_exposure, 2) + "\n";
   report += "미실현 손익: " + DoubleToString(risk.unrealized_pnl, 2) + "\n";
   report += "사용 마진: " + DoubleToString(risk.used_margin, 2) + "\n";
   report += "여유 마진: " + DoubleToString(risk.free_margin, 2) + "\n";
   report += "마진 레벨: " + DoubleToString(risk.margin_level, 2) + "%\n";
   report += "현재 리스크 노출: " + DoubleToString(GetCurrentRiskExposure(), 2) + "\n";
   report += "사용 가능 리스크: " + DoubleToString(GetAvailableRiskCapacity(), 2) + "\n";
   
   return report;
}

//+------------------------------------------------------------------+
//| 현재 리스크 상태 로깅                                            |
//+------------------------------------------------------------------+
void CRiskManager::LogCurrentRiskStatus() {
   string report = GetRiskStatusReport();
   LogInfo(report);
}

//+------------------------------------------------------------------+
//| 리스크 매니저 자체 테스트                                        |
//+------------------------------------------------------------------+
bool CRiskManager::SelfTest() {
   LogInfo("RiskManager 자체 테스트 시작...");
   
   bool all_passed = true;
   
   // 1. 심볼 정보 테스트
   if(!UpdateSymbolInfo()) {
      LogError("심볼 정보 업데이트 실패");
      all_passed = false;
   }
   
   // 2. 포인트 가치 계산 테스트
   double point_value = CalculatePointValue();
   if(point_value <= 0) {
      LogError("포인트 가치 계산 실패");
      all_passed = false;
   }
   
   // 3. 랏 정규화 테스트
   double test_lot = 0.37;
   double normalized_lot = NormalizeLots(test_lot);
   if(normalized_lot <= 0) {
      LogError("랏 정규화 실패");
      all_passed = false;
   }
   
   // 4. SL/TP 계산 테스트
   double current_price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double test_sl, test_tp;
   if(!CalculateSafeStops(current_price, ORDER_TYPE_BUY, 0.001, 2.0, 3.0, test_sl, test_tp)) {
      LogError("SL/TP 계산 실패");
      all_passed = false;
   }
   
   // 5. 리스크 계산 테스트
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double test_risk = CalculateMaxLossForPosition(1.0, 100.0);
   if(test_risk <= 0) {
      LogError("리스크 계산 실패");
      all_passed = false;
   }
   
   if(all_passed) {
      LogInfo("RiskManager 자체 테스트 통과");
   } else {
      LogError("RiskManager 자체 테스트 실패");
   }
   
   return all_passed;
}

//+------------------------------------------------------------------+
//| 최적 포지션 계산 (StrategySelector 호환)                         |
//+------------------------------------------------------------------+
SRiskCalculationResult CRiskManager::CalculateOptimalPosition(double risk_amount, double entry_price, 
                                                             double sl_price, double account_balance) {
   SRiskCalculationResult result;
   ZeroMemory(result);
   
   // 1. 기본 검증
   if(risk_amount <= 0 || entry_price <= 0 || sl_price <= 0 || account_balance <= 0) {
      result.is_valid = false;
      result.validation_message = "잘못된 입력 파라미터";
      return result;
   }
   
   // 2. 포지션 사이즈 계산
   result.suggested_lots = CalculateSafePositionSize(risk_amount, entry_price, sl_price);
   
   if(result.suggested_lots <= 0) {
      result.is_valid = false;
      result.validation_message = "포지션 사이즈 계산 실패";
      return result;
   }
   
   // 3. 실제 리스크 계산
   double sl_points = ToPoints(MathAbs(entry_price - sl_price));
   result.actual_risk_amount = CalculateMaxLossForPosition(result.suggested_lots, sl_points);
   result.risk_percentage = (result.actual_risk_amount / account_balance) * 100.0;
   
   // 4. 마진 계산
   if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, result.suggested_lots, entry_price, result.margin_required)) {
      result.margin_required = 0;
   }
   result.margin_available = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   
   // 5. 검증
   result.is_valid = ValidateRisk(result.suggested_lots, MathAbs(entry_price - sl_price), account_balance);
   
   if(result.is_valid) {
      result.validation_message = "검증 통과";
   } else {
      result.validation_message = "리스크 한도 초과 또는 제약 조건 위반";
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| 리스크 퍼센트 기반 포지션 사이즈 계산                            |
//+------------------------------------------------------------------+
double CRiskManager::CalculatePositionSizeByRiskPercent(double risk_percent, double entry_price, double sl_price) {
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (risk_percent / 100.0);
   return CalculateSafePositionSize(risk_amount, entry_price, sl_price);
}

//+------------------------------------------------------------------+
//| 고정 금액 기반 포지션 사이즈 계산                                |
//+------------------------------------------------------------------+
double CRiskManager::CalculatePositionSizeByFixedAmount(double fixed_risk_usd, double entry_price, double sl_price) {
   return CalculateSafePositionSize(fixed_risk_usd, entry_price, sl_price);
}

//+------------------------------------------------------------------+
//|  CRiskManager::ValidateStopLevels                                |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateStopLevels(double price,
                                      double sl,
                                      double tp,
                                      ENUM_ORDER_TYPE type)
{
   // 심볼 정보
   double point        = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   double min_distance = SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   double spread       = SymbolInfoInteger(m_symbol,SYMBOL_SPREAD)*point;
   double safety_margin= 5*point;                 // 여유 5포인트

   // 파라미터 검증
   if(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP)
   {
      if(sl>0 && (price-sl) < (min_distance+spread+safety_margin))
         return false;
      if(tp>0 && (tp-price) < (min_distance+safety_margin))
         return false;
   }
   else if(type==ORDER_TYPE_SELL || type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP)
   {
      if(sl>0 && (sl-price) < (min_distance+spread+safety_margin))
         return false;
      if(tp>0 && (price-tp) < (min_distance+safety_margin))
         return false;
   }
   return true;
}


#endif // __RISK_MANAGER_MQH__