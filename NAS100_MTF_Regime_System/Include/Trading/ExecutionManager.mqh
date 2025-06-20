//+------------------------------------------------------------------+
//|                                          ExecutionManager.mqh    |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "../RegimeDetection/RegimeDefinitions.mqh"
#include "../Trading/RiskManager.mqh"
#include "../Trading/StrategySelector.mqh"
#include "../Utils/SessionManager.mqh"
#include "../Utils/Logger.mqh"
#include <Trade\Trade.mqh>

// 주문 정보 구조체
struct SOrderInfo {
   ulong ticket;                   // 주문 티켓
   ENUM_ORDER_TYPE order_type;     // 주문 타입
   ENUM_POSITION_TYPE position_type; // 포지션 타입
   double entry_price;             // 진입가
   double sl_price;                // 손절가
   double tp_price;                // 익절가
   double lots;                    // 랏 사이즈
   datetime open_time;             // 오픈 시간
   string strategy_name;           // 전략 이름
   double target_risk;             // 목표 리스크
   bool has_trailing_stop;         // 트레일링 스탑 여부
   double trailing_distance;       // 트레일링 거리
   double partial_close_level;     // 부분 청산 레벨
   bool partial_closed;            // 부분 청산 완료 여부
};

// 주문 실행 결과 구조체
struct SExecutionResult {
   bool success;                   // 성공 여부
   ulong ticket;                   // 주문 티켓
   double executed_price;          // 실행 가격
   double slippage;                // 슬리피지
   string error_message;           // 오류 메시지
   uint error_code;                 // 오류 코드
   datetime execution_time;        // 실행 시간
};

// 포지션 요약 구조체
struct SPositionSummary {
   int total_positions;            // 총 포지션 수
   int buy_positions;              // 매수 포지션 수
   int sell_positions;             // 매도 포지션 수
   double total_lots;              // 총 랏 사이즈
   double total_profit;            // 총 수익
   double total_exposure;          // 총 노출
   double largest_position;        // 최대 포지션 크기
};

// 실행 통계 구조체
struct SExecutionStats {
   int total_orders;               // 총 주문 수
   int successful_orders;          // 성공한 주문 수
   int failed_orders;              // 실패한 주문 수
   double total_slippage;          // 총 슬리피지
   double avg_slippage;            // 평균 슬리피지
   double worst_slippage;          // 최악의 슬리피지
   int retry_count;                // 재시도 횟수
   datetime last_execution;        // 마지막 실행 시간
};

// ExecutionManager 클래스
class CExecutionManager {
private:
   // 의존성 포인터들
   CRiskManager* m_risk_manager;
   CSessionManager* m_session_manager;
   CStrategySelector* m_strategy_selector;
   
   // 거래 객체
   CTrade m_trade;
   
   // 기본 설정
   string m_symbol;
   ulong m_magic_number;
   int m_max_retries;
   int m_slippage_points;
   double m_max_spread_points;
   
   // 포지션 관리
   SOrderInfo m_active_positions[];
   int m_position_count;
   
   // 실행 통계
   SExecutionStats m_execution_stats;
   
   // 긴급 상태
   bool m_emergency_mode;
   datetime m_last_emergency_check;
   int m_emergency_check_interval;  // 초 단위
   
   // 트레일링 스탑 설정
   bool m_use_trailing_stop;
   double m_trailing_start_points;  // 트레일링 시작 거리
   double m_trailing_step_points;   // 트레일링 스텝
   datetime m_last_trailing_update;
   int m_trailing_update_interval;  // 초 단위
   
   // 부분 청산 설정
   bool m_use_partial_close;
   double m_partial_close_percent;  // 부분 청산 비율
   double m_partial_close_trigger;  // 부분 청산 트리거 (ATR 배수)
   
   // 내부 메서드들
   bool ValidateOrderParameters(double price, double sl, double tp, ENUM_ORDER_TYPE type);
   bool CheckSpreadCondition();
   bool IsMarketOpen();
   double NormalizePrice(double price);
   double NormalizeLots(double lots);
   SExecutionResult ExecuteMarketOrder(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment);
   bool AddPositionToArray(const SOrderInfo &order_info);
   bool RemovePositionFromArray(ulong ticket);
   bool UpdatePositionInArray(ulong ticket, const SOrderInfo &new_info);
   int FindPositionInArray(ulong ticket);
   void UpdateExecutionStats(bool success, double slippage);
   string GenerateOrderComment(const SEntrySignal &signal);
   bool HandleOrderError(int error_code, MqlTradeRequest &request);
   bool WaitForOrderExecution(ulong ticket, int timeout_ms);
   double CalculateSlippage(double requested_price, double executed_price);
   bool CheckPositionStillOpen(ulong ticket);
   void LogExecutionDetails(const SExecutionResult &result);
   
public:
   // 생성자 및 소멸자
   CExecutionManager(string symbol, ulong magic_number);
   ~CExecutionManager();
   
   // 초기화 및 설정
   bool Initialize(CRiskManager* risk_manager, CSessionManager* session_manager, 
                  CStrategySelector* strategy_selector);
   void SetExecutionParameters(int max_retries, int slippage_points, double max_spread_points);
   void SetTrailingStopParameters(bool use_trailing, double start_points, double step_points);
   void SetPartialCloseParameters(bool use_partial, double close_percent, double trigger_atr);
   void SetMagicNumber(ulong magic) { m_magic_number = magic; }
   
   // 주문 실행 (핵심 메서드)
   bool ExecuteSignal(const SEntrySignal &signal);
   SExecutionResult OpenPosition(ENUM_ORDER_TYPE type, double lots, double price, 
                                double sl, double tp, string comment);
   
   // 포지션 관리
   bool ClosePosition(ulong ticket, double lots = 0);
   bool CloseAllPositions();
   bool ModifyPosition(ulong ticket, double sl, double tp);
   bool PartialClosePosition(ulong ticket, double close_percent);
   
   // 트레일링 스탑 관리
   bool UpdateTrailingStops();
   bool SetTrailingStop(ulong ticket, double trail_distance);
   bool RemoveTrailingStop(ulong ticket);
   
   // 부분 청산 관리
   bool CheckAndExecutePartialClose();
   bool ExecutePartialClose(ulong ticket, double close_percent);
   
   // 긴급 관리
   bool EmergencyCloseAll();
   bool CheckAndHandleEmergency();
   void EnableEmergencyMode() { m_emergency_mode = true; }
   void DisableEmergencyMode() { m_emergency_mode = false; }
   bool IsEmergencyMode() const { return m_emergency_mode; }
   
   // 포지션 모니터링
   void UpdatePositions();
   SPositionSummary GetPositionSummary();
   double GetTotalExposure();
   int GetActivePositionCount() const { return m_position_count; }
   bool HasOpenPositions() const { return m_position_count > 0; }
   bool GetPositionInfo(ulong ticket, SOrderInfo &info);
   
   // 실행 통계
   SExecutionStats GetExecutionStats() const { return m_execution_stats; }
   void ResetExecutionStats();
   double GetAverageSlippage() const;
   double GetSuccessRate() const;
   
   // 유틸리티
   void LogCurrentStatus();
   bool SelfTest();
   string GetStatusReport();
};

//+------------------------------------------------------------------+
//| 생성자                                                           |
//+------------------------------------------------------------------+
CExecutionManager::CExecutionManager(string symbol, ulong magic_number) {
   m_symbol = symbol;
   m_magic_number = magic_number;
   
   // 의존성 초기화
   m_risk_manager = NULL;
   m_session_manager = NULL;
   m_strategy_selector = NULL;
   
   // 거래 객체 설정
   m_trade.SetExpertMagicNumber(m_magic_number);
   m_trade.SetDeviationInPoints(10);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   m_trade.SetAsyncMode(false);
   
   // 기본 파라미터
   m_max_retries = 3;
   m_slippage_points = 10;
   m_max_spread_points = 20;
   
   // 포지션 배열 초기화
   ArrayResize(m_active_positions, 0);
   m_position_count = 0;
   
   // 실행 통계 초기화
   ZeroMemory(m_execution_stats);
   
   // 긴급 모드
   m_emergency_mode = false;
   m_last_emergency_check = 0;
   m_emergency_check_interval = 5; // 5초마다 체크
   
   // 트레일링 스탑
   m_use_trailing_stop = true;
   m_trailing_start_points = 50;
   m_trailing_step_points = 10;
   m_last_trailing_update = 0;
   m_trailing_update_interval = 10; // 10초마다 업데이트
   
   // 부분 청산
   m_use_partial_close = true;
   m_partial_close_percent = 50;
   m_partial_close_trigger = 1.5; // 1.5 ATR
}

//+------------------------------------------------------------------+
//| 소멸자                                                           |
//+------------------------------------------------------------------+
CExecutionManager::~CExecutionManager() {
   // 로깅
   LogInfo("ExecutionManager 종료 - 실행 통계:");
   LogInfo("총 주문: " + IntegerToString(m_execution_stats.total_orders));
   LogInfo("성공률: " + DoubleToString(GetSuccessRate()*100, 1) + "%");
   LogInfo("평균 슬리피지: " + DoubleToString(GetAverageSlippage(), 1) + " points");
   
   // 포지션 배열 정리
   ArrayFree(m_active_positions);
}

//+------------------------------------------------------------------+
//| 초기화                                                           |
//+------------------------------------------------------------------+
bool CExecutionManager::Initialize(CRiskManager* risk_manager, CSessionManager* session_manager, 
                                 CStrategySelector* strategy_selector) {
   LogInfo("ExecutionManager::Initialize() 시작");
   
   // 의존성 설정
   m_risk_manager = risk_manager;
   m_session_manager = session_manager;
   m_strategy_selector = strategy_selector;
   
   // 포인터 검증
   if(m_risk_manager == NULL) {
       LogError("RiskManager 포인터가 NULL");
       return false;
   }
   
   if(m_session_manager == NULL) {
       LogError("SessionManager 포인터가 NULL");
       return false;
   }
   
   if(m_strategy_selector == NULL) {
       LogError("StrategySelector 포인터가 NULL");
       return false;
   }
   
   // 기존 포지션 로드
   UpdatePositions();
   
   LogInfo("ExecutionManager 초기화 완료");
   LogInfo("Magic Number: " + IntegerToString(m_magic_number));
   LogInfo("활성 포지션: " + IntegerToString(m_position_count));
   
   return true;
}

//+------------------------------------------------------------------+
//| 신호 실행 (핵심 메서드)                                          |
//+------------------------------------------------------------------+
bool CExecutionManager::ExecuteSignal(const SEntrySignal &signal) {
   // 1. 기본 검증
   if(!signal.has_signal || !signal.risk_validated) {
       LogWarning("ExecuteSignal: 유효하지 않은 신호");
       return false;
   }
   
   // 2. 긴급 모드 체크
   if(m_emergency_mode) {
       LogError("긴급 모드 활성화 중 - 새 포지션 오픈 불가");
       return false;
   }
   
   // 3. 시장 상태 확인
   if(!IsMarketOpen()) {
       LogError("시장이 닫혀있음");
       return false;
   }
   
   // 4. 스프레드 체크
   if(!CheckSpreadCondition()) {
       LogWarning("스프레드가 너무 넓음");
       return false;
   }
   
   // 5. RiskManager 최종 확인
   if(m_risk_manager != NULL) {
       if(!(*m_risk_manager).CanOpenNewPosition(signal.suggested_lot, 
                                                MathAbs(signal.suggested_price - signal.suggested_sl))) {
           LogError("RiskManager: 새 포지션 오픈 불가");
           return false;
       }
   }
   
   // 6. 주문 코멘트 생성
   string comment = GenerateOrderComment(signal);
   
   // 7. 주문 실행
   SExecutionResult result = ExecuteMarketOrder(signal.signal_type, signal.suggested_lot, 
                                               signal.suggested_sl, signal.suggested_tp, comment);
   
   // 8. 결과 처리
   if(result.success) {
       // 포지션 정보 저장
       SOrderInfo order_info;
       order_info.ticket = result.ticket;
       order_info.order_type = signal.signal_type;
       order_info.position_type = (signal.signal_type == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
       order_info.entry_price = result.executed_price;
       order_info.sl_price = signal.suggested_sl;
       order_info.tp_price = signal.suggested_tp;
       order_info.lots = signal.suggested_lot;
       order_info.open_time = result.execution_time;
       order_info.strategy_name = signal.signal_reason;
       order_info.target_risk = signal.calculated_risk;
       order_info.has_trailing_stop = m_use_trailing_stop;
       order_info.trailing_distance = m_trailing_start_points * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
       order_info.partial_close_level = m_partial_close_trigger;
       order_info.partial_closed = false;
       
       AddPositionToArray(order_info);
       
       LogInfo("주문 실행 성공: Ticket=" + IntegerToString(result.ticket) + 
              ", 가격=" + DoubleToString(result.executed_price, _Digits) +
              ", 슬리피지=" + DoubleToString(result.slippage, 1) + " points");
   } else {
       LogError("주문 실행 실패: " + result.error_message);
   }
   
   // 9. 실행 통계 업데이트
   UpdateExecutionStats(result.success, result.slippage);
   
   return result.success;
}

//+------------------------------------------------------------------+
//| 시장 주문 실행                                                   |
//+------------------------------------------------------------------+
SExecutionResult CExecutionManager::ExecuteMarketOrder(ENUM_ORDER_TYPE type, double lots, 
                                                     double sl, double tp, string comment) {
   SExecutionResult result;
   ZeroMemory(result);
   result.execution_time = TimeCurrent();
   
   // 가격 정규화
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   lots = NormalizeLots(lots);
   
   // 현재 가격 가져오기
   double price = (type == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(m_symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(m_symbol, SYMBOL_BID);
   
   // 주문 파라미터 검증
   if(!ValidateOrderParameters(price, sl, tp, type)) {
       result.success = false;
       result.error_message = "주문 파라미터 검증 실패";
       result.error_code = -1;
       return result;
   }
   
   // 재시도 루프
   int retries = 0;
   while(retries < m_max_retries) {
       // CTrade 객체로 주문 실행
       bool order_success = false;
       
       if(type == ORDER_TYPE_BUY) {
           order_success = m_trade.Buy(lots, m_symbol, price, sl, tp, comment);
       } else if(type == ORDER_TYPE_SELL) {
           order_success = m_trade.Sell(lots, m_symbol, price, sl, tp, comment);
       }
       
       if(order_success) {
           result.success = true;
           result.ticket = m_trade.ResultOrder();
           result.executed_price = m_trade.ResultPrice();
           result.slippage = CalculateSlippage(price, result.executed_price);
           
           // 주문 실행 확인 대기
           if(WaitForOrderExecution(result.ticket, 3000)) {
               LogExecutionDetails(result);
               return result;
           }
       }
       
       // 오류 처리
       uint error_code = m_trade.ResultRetcode();
       result.error_code = error_code;
       result.error_message = m_trade.ResultRetcodeDescription();
       
       // 재시도 가능한 오류인지 확인
       MqlTradeRequest dummy_request;
       if(!HandleOrderError(error_code, dummy_request)) {
           break; // 재시도 불가능한 오류
       }
       
       retries++;
       if(retries < m_max_retries) {
           Sleep(1000); // 1초 대기 후 재시도
           LogWarning("주문 재시도 " + IntegerToString(retries) + "/" + IntegerToString(m_max_retries));
       }
   }
   
   result.success = false;
   return result;
}

//+------------------------------------------------------------------+
//| 포지션 닫기                                                      |
//+------------------------------------------------------------------+
bool CExecutionManager::ClosePosition(ulong ticket, double lots) {
   if(!CheckPositionStillOpen(ticket)) {
       LogWarning("포지션이 이미 닫혀있음: " + IntegerToString(ticket));
       RemovePositionFromArray(ticket);
       return false;
   }
   
   // 부분 청산인 경우
   if(lots > 0 && lots < PositionGetDouble(POSITION_VOLUME)) {
       return PartialClosePosition(ticket, lots / PositionGetDouble(POSITION_VOLUME) * 100);
   }
   
   // 전체 청산
   bool close_success = m_trade.PositionClose(ticket, m_slippage_points);
   
   if(close_success) {
       RemovePositionFromArray(ticket);
       LogInfo("포지션 청산 성공: Ticket=" + IntegerToString(ticket));
       return true;
   }
   
   LogError("포지션 청산 실패: " + m_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| 모든 포지션 닫기                                                 |
//+------------------------------------------------------------------+
bool CExecutionManager::CloseAllPositions() {
   LogInfo("모든 포지션 청산 시작");
   
   int closed_count = 0;
   int failed_count = 0;
   
   // 배열을 역순으로 순회 (청산 중 배열 변경 대응)
   for(int i = m_position_count - 1; i >= 0; i--) {
       if(ClosePosition(m_active_positions[i].ticket)) {
           closed_count++;
       } else {
           failed_count++;
       }
   }
   
   LogInfo("포지션 청산 완료: 성공=" + IntegerToString(closed_count) + 
          ", 실패=" + IntegerToString(failed_count));
   
   return (failed_count == 0);
}

//+------------------------------------------------------------------+
//| 포지션 수정                                                      |
//+------------------------------------------------------------------+
bool CExecutionManager::ModifyPosition(ulong ticket, double sl, double tp) {
   if(!CheckPositionStillOpen(ticket)) {
       LogWarning("포지션이 존재하지 않음: " + IntegerToString(ticket));
       RemovePositionFromArray(ticket);
       return false;
   }
   
   // 가격 정규화
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   
   // 현재 포지션 정보
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   // 수정 파라미터 검증
   ENUM_ORDER_TYPE order_type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!ValidateOrderParameters(current_price, sl, tp, order_type)) {
       LogError("포지션 수정 파라미터 검증 실패");
       return false;
   }
   
   // 수정 실행
   bool modify_success = m_trade.PositionModify(ticket, sl, tp);
   
   if(modify_success) {
       // 배열 업데이트
       int pos_index = FindPositionInArray(ticket);
       if(pos_index >= 0) {
           m_active_positions[pos_index].sl_price = sl;
           m_active_positions[pos_index].tp_price = tp;
       }
       
       LogInfo("포지션 수정 성공: Ticket=" + IntegerToString(ticket) + 
              ", SL=" + DoubleToString(sl, _Digits) + 
              ", TP=" + DoubleToString(tp, _Digits));
       return true;
   }
   
   LogError("포지션 수정 실패: " + m_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| 부분 청산                                                        |
//+------------------------------------------------------------------+
bool CExecutionManager::PartialClosePosition(ulong ticket, double close_percent) {
   if(!CheckPositionStillOpen(ticket)) {
       LogWarning("포지션이 존재하지 않음: " + IntegerToString(ticket));
       RemovePositionFromArray(ticket);
       return false;
   }
   
   double current_lots = PositionGetDouble(POSITION_VOLUME);
   double close_lots = NormalizeLots(current_lots * close_percent / 100.0);
   
   if(close_lots <= 0) {
       LogError("부분 청산 랏 사이즈가 0 이하");
       return false;
   }
   
   // 최소 랏 확인
   double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   if(close_lots < min_lot) {
       close_lots = min_lot;
   }
   
   // 남은 랏이 최소 랏보다 작아지는 경우 전체 청산
   if(current_lots - close_lots < min_lot) {
       return ClosePosition(ticket);
   }
   
   // 부분 청산 실행
   bool partial_success = m_trade.PositionClosePartial(ticket, close_lots, m_slippage_points);
   
   if(partial_success) {
       // 배열 업데이트
       int pos_index = FindPositionInArray(ticket);
             if(pos_index >= 0) {
                 m_active_positions[pos_index].lots = current_lots - close_lots;
                 m_active_positions[pos_index].partial_closed = true;
              }
       
       LogInfo("부분 청산 성공: Ticket=" + IntegerToString(ticket) + 
              ", 청산=" + DoubleToString(close_lots, 2) + " lots (" + 
              DoubleToString(close_percent, 1) + "%)");
       return true;
   }
   
   LogError("부분 청산 실패: " + m_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| 트레일링 스탑 업데이트                                           |
//+------------------------------------------------------------------+
bool CExecutionManager::UpdateTrailingStops() {
   if(!m_use_trailing_stop) return true;
   
   // 업데이트 간격 체크
   datetime current_time = TimeCurrent();
   if(current_time - m_last_trailing_update < m_trailing_update_interval) {
       return true;
   }
   
   m_last_trailing_update = current_time;
   
   int updated_count = 0;
   
   for(int i = 0; i < m_position_count; i++) {
       if(!m_active_positions[i].has_trailing_stop) continue;
       
       ulong ticket = m_active_positions[i].ticket;
       
       if(!CheckPositionStillOpen(ticket)) {
           RemovePositionFromArray(ticket);
           i--;
           continue;
       }
       
       if(SetTrailingStop(ticket, m_active_positions[i].trailing_distance)) {
           updated_count++;
       }
   }
   
   if(updated_count > 0) {
       LogDebug("트레일링 스탑 업데이트: " + IntegerToString(updated_count) + " 포지션");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 트레일링 스탑 설정                                               |
//+------------------------------------------------------------------+
bool CExecutionManager::SetTrailingStop(ulong ticket, double trail_distance) {
   if(!PositionSelectByTicket(ticket)) return false;
   
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_tp = PositionGetDouble(POSITION_TP);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double new_sl = 0;
   bool need_update = false;
   
   if(pos_type == POSITION_TYPE_BUY) {
       // 현재 가격이 진입가 + 트레일 시작 거리 이상인 경우
       if(current_price > open_price + trail_distance) {
           new_sl = current_price - trail_distance;
           // 기존 SL보다 높은 경우만 업데이트
           if(new_sl > current_sl) {
               need_update = true;
           }
       }
   } else { // SELL
       if(current_price < open_price - trail_distance) {
           new_sl = current_price + trail_distance;
           // 기존 SL보다 낮은 경우만 업데이트 (또는 SL이 없는 경우)
           if(new_sl < current_sl || current_sl == 0) {
               need_update = true;
           }
       }
   }
   
   if(need_update) {
       return ModifyPosition(ticket, new_sl, current_tp);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 부분 청산 체크 및 실행                                           |
//+------------------------------------------------------------------+
bool CExecutionManager::CheckAndExecutePartialClose() {
   if(!m_use_partial_close) return true;
   
   int partial_count = 0;
   
   // ATR 지표 핸들 생성
   int atr_handle = iATR(m_symbol, PERIOD_CURRENT, 14);
   if(atr_handle == INVALID_HANDLE) {
       LogError("ATR 지표 생성 실패");
       return false;
   }
   
   // ATR 값 가져오기
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0) {
       LogError("ATR 데이터 복사 실패");
       IndicatorRelease(atr_handle);
       return false;
   }
   
   double atr = atr_buffer[0];
   IndicatorRelease(atr_handle);
   
   for(int i = 0; i < m_position_count; i++) {
       // 이미 부분 청산된 포지션은 건너뛰기
       if(m_active_positions[i].partial_closed) continue;
       
       ulong ticket = m_active_positions[i].ticket;
       
       if(!CheckPositionStillOpen(ticket)) {
           RemovePositionFromArray(ticket);
           i--;
           continue;
       }
       
       double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
       double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
       ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
       
       double trigger_distance = atr * m_active_positions[i].partial_close_level;
       
       bool should_partial_close = false;
       
       if(pos_type == POSITION_TYPE_BUY && current_price > open_price + trigger_distance) {
           should_partial_close = true;
       } else if(pos_type == POSITION_TYPE_SELL && current_price < open_price - trigger_distance) {
           should_partial_close = true;
       }
       
       if(should_partial_close) {
           if(ExecutePartialClose(ticket, m_partial_close_percent)) {
               partial_count++;
           }
       }
   }
   
   if(partial_count > 0) {
       LogInfo("부분 청산 실행: " + IntegerToString(partial_count) + " 포지션");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 부분 청산 실행                                                   |
//+------------------------------------------------------------------+
bool CExecutionManager::ExecutePartialClose(ulong ticket, double close_percent) {
   return PartialClosePosition(ticket, close_percent);
}

//+------------------------------------------------------------------+
//| 긴급 모든 포지션 청산                                            |
//+------------------------------------------------------------------+
bool CExecutionManager::EmergencyCloseAll() {
   LogError("긴급 청산 모드 활성화!");
   
   m_emergency_mode = true;
   
   // 모든 포지션 즉시 청산
   bool result = CloseAllPositions();
   
   if(result) {
       LogInfo("긴급 청산 완료");
   } else {
       LogError("긴급 청산 중 일부 실패");
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| 긴급 상황 체크 및 처리                                           |
//+------------------------------------------------------------------+
bool CExecutionManager::CheckAndHandleEmergency() {
   // 체크 간격 확인
   datetime current_time = TimeCurrent();
   if(current_time - m_last_emergency_check < m_emergency_check_interval) {
       return true;
   }
   
   m_last_emergency_check = current_time;
   
   // RiskManager에서 긴급 상황 확인
   if(m_risk_manager != NULL) {
       if((*m_risk_manager).IsEmergencyLevelReached()) {
           LogError("RiskManager: 긴급 레벨 도달!");
           return EmergencyCloseAll();
       }
       
       if((*m_risk_manager).ShouldStopTrading()) {
           LogWarning("RiskManager: 거래 중단 권고");
           m_emergency_mode = true;
           // 새 포지션은 막지만 기존 포지션은 유지
       }
       
       if((*m_risk_manager).ShouldReducePosition()) {
           double reduction_percent = (*m_risk_manager).GetRecommendedPositionReduction();
           LogWarning("RiskManager: 포지션 축소 권고 " + DoubleToString(reduction_percent*100, 0) + "%");
           
           // 모든 포지션 부분 청산
           for(int i = 0; i < m_position_count; i++) {
               PartialClosePosition(m_active_positions[i].ticket, reduction_percent * 100);
           }
       }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 포지션 업데이트                                                  |
//+------------------------------------------------------------------+
void CExecutionManager::UpdatePositions() {
   // 임시 배열
   SOrderInfo temp_positions[];
   int temp_count = 0;
   
   // 모든 포지션 순회
   int total = PositionsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionSelectByTicket(ticket)) {
         // Magic Number와 심볼 확인
         if(PositionGetInteger(POSITION_MAGIC) == (long)m_magic_number &&  // 타입 캐스팅
            PositionGetString(POSITION_SYMBOL) == m_symbol) {
            
            // 기존 배열에서 찾기
            int existing_index = FindPositionInArray(ticket);
            
            ArrayResize(temp_positions, temp_count + 1);
            
            if(existing_index >= 0) {
               // 기존 정보 복사 및 업데이트
               temp_positions[temp_count] = m_active_positions[existing_index];
               temp_positions[temp_count].lots = PositionGetDouble(POSITION_VOLUME);
            } else {
               // 새 포지션 추가
               ZeroMemory(temp_positions[temp_count]);
               
               temp_positions[temp_count].ticket = ticket;
               temp_positions[temp_count].position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               temp_positions[temp_count].order_type = (temp_positions[temp_count].position_type == POSITION_TYPE_BUY) ? 
                                                      ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               temp_positions[temp_count].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
               temp_positions[temp_count].sl_price = PositionGetDouble(POSITION_SL);
               temp_positions[temp_count].tp_price = PositionGetDouble(POSITION_TP);
               temp_positions[temp_count].lots = PositionGetDouble(POSITION_VOLUME);
               temp_positions[temp_count].open_time = (datetime)PositionGetInteger(POSITION_TIME);
               temp_positions[temp_count].strategy_name = PositionGetString(POSITION_COMMENT);
               temp_positions[temp_count].has_trailing_stop = m_use_trailing_stop;
               temp_positions[temp_count].trailing_distance = m_trailing_start_points * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
               temp_positions[temp_count].partial_close_level = m_partial_close_trigger;
               temp_positions[temp_count].partial_closed = false;
            }
            
            temp_count++;
         }
      }
   }
   
   // 배열 교체 - 수동 복사
   ArrayResize(m_active_positions, temp_count);
   for(int i = 0; i < temp_count; i++) {
      m_active_positions[i] = temp_positions[i];
   }
   m_position_count = temp_count;
}


//+------------------------------------------------------------------+
//| 포지션 요약 정보 가져오기                                        |
//+------------------------------------------------------------------+
SPositionSummary CExecutionManager::GetPositionSummary() {
   SPositionSummary summary;
   ZeroMemory(summary);
   
   for(int i = 0; i < m_position_count; i++) {
       ulong ticket = m_active_positions[i].ticket;
       
       if(PositionSelectByTicket(ticket)) {
           summary.total_positions++;
           
           if(m_active_positions[i].position_type == POSITION_TYPE_BUY) {
               summary.buy_positions++;
           } else {
               summary.sell_positions++;
           }
           
           double lots = PositionGetDouble(POSITION_VOLUME);
           summary.total_lots += lots;
           
           double profit = PositionGetDouble(POSITION_PROFIT);
           summary.total_profit += profit;
           
           double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
           double exposure = lots * SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE) * current_price;
           summary.total_exposure += exposure;
           
           if(lots > summary.largest_position) {
               summary.largest_position = lots;
           }
       }
   }
   
   return summary;
}

//+------------------------------------------------------------------+
//| 총 노출 계산                                                     |
//+------------------------------------------------------------------+
double CExecutionManager::GetTotalExposure() {
   double total_exposure = 0;
   
   for(int i = 0; i < m_position_count; i++) {
       if(PositionSelectByTicket(m_active_positions[i].ticket)) {
           double lots = PositionGetDouble(POSITION_VOLUME);
           double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
           double contract_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
           
           total_exposure += lots * contract_size * current_price;
       }
   }
   
   return total_exposure;
}

//+------------------------------------------------------------------+
//| 포지션 정보 가져오기                                             |
//+------------------------------------------------------------------+
bool CExecutionManager::GetPositionInfo(ulong ticket, SOrderInfo &info) {
   int pos_index = FindPositionInArray(ticket);
   
   if(pos_index >= 0) {
      info = m_active_positions[pos_index];
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 주문 파라미터 검증                                               |
//+------------------------------------------------------------------+
bool CExecutionManager::ValidateOrderParameters(double price, double sl, double tp, ENUM_ORDER_TYPE type) {
   // 1. RiskManager를 통한 검증
   if(m_risk_manager != NULL) {
       if(!(*m_risk_manager).ValidateStopLevels(price, sl, tp, type)) {
           LogError("RiskManager: SL/TP 레벨 검증 실패");
           return false;
       }
   }
   
   // 2. 추가 안전 마진 적용
   double min_distance = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double safety_margin = 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   // 3. 주문 타입별 검증
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) {
       if(sl > 0 && (price - sl) < (min_distance + spread + safety_margin)) {
           LogError("매수 SL 거리 부족: " + DoubleToString((price - sl)/SymbolInfoDouble(m_symbol, SYMBOL_POINT), 0) + " points");
           return false;
       }
       if(tp > 0 && (tp - price) < (min_distance + safety_margin)) {
           LogError("매수 TP 거리 부족: " + DoubleToString((tp - price)/SymbolInfoDouble(m_symbol, SYMBOL_POINT), 0) + " points");
           return false;
       }
   } else if(type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP) {
       if(sl > 0 && (sl - price) < (min_distance + spread + safety_margin)) {
           LogError("매도 SL 거리 부족: " + DoubleToString((sl - price)/SymbolInfoDouble(m_symbol, SYMBOL_POINT), 0) + " points");
           return false;
       }
       if(tp > 0 && (price - tp) < (min_distance + safety_margin)) {
           LogError("매도 TP 거리 부족: " + DoubleToString((price - tp)/SymbolInfoDouble(m_symbol, SYMBOL_POINT), 0) + " points");
           return false;
       }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 스프레드 조건 확인                                               |
//+------------------------------------------------------------------+
bool CExecutionManager::CheckSpreadCondition() {
   double current_spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double max_spread = m_max_spread_points * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   if(current_spread > max_spread) {
       LogWarning("스프레드가 너무 넓음: " + DoubleToString(current_spread/SymbolInfoDouble(m_symbol, SYMBOL_POINT), 0) + 
                 " > " + DoubleToString(m_max_spread_points, 0) + " points");
       return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 시장 오픈 확인                                                   |
//+------------------------------------------------------------------+
bool CExecutionManager::IsMarketOpen() {
   // 거래 허용 여부 확인
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
       LogError("터미널 거래 비활성화");
       return false;
   }
   
   // 심볼 거래 가능 여부
   if(!SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE)) {
       LogError("심볼 거래 비활성화: " + m_symbol);
       return false;
   }
   
   // ★ 요일 루프 – 하나라도 열려 있으면 OK
   datetime from,to;
   bool market_open=false;
   for(int d=SUNDAY; d<=SATURDAY && !market_open; ++d)
       market_open = SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)d,0,from,to);

   if(!market_open)
   {
       LogError("거래 세션 정보 없음(전 요일)");
       return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 가격 정규화                                                      |
//+------------------------------------------------------------------+
double CExecutionManager::NormalizePrice(double price) {
   double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   
   if(tick_size > 0) {
       return MathRound(price / tick_size) * tick_size;
   }
   
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| 랏 사이즈 정규화                                                 |
//+------------------------------------------------------------------+
double CExecutionManager::NormalizeLots(double lots) {
   const double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   const double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   const double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   if(lot_step>0)
   {
       // ★ MathFloor → overflow 방지
       lots = MathFloor(lots/lot_step)*lot_step;

       // 최소 lot 못 채우면 한 스텝 더 추가
       if(lots < min_lot) lots += lot_step;
   }

   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;

   return lots;
}
//+------------------------------------------------------------------+
//| 포지션 배열에 추가                                               |
//+------------------------------------------------------------------+
bool CExecutionManager::AddPositionToArray(const SOrderInfo &order_info) {
   ArrayResize(m_active_positions, m_position_count + 1);
   m_active_positions[m_position_count] = order_info;
   m_position_count++;
   
   return true;
}

//+------------------------------------------------------------------+
//| 포지션 배열에서 제거                                             |
//+------------------------------------------------------------------+
bool CExecutionManager::RemovePositionFromArray(ulong ticket) {
   for(int i = 0; i < m_position_count; i++) {
       if(m_active_positions[i].ticket == ticket) {
           // 배열 요소 이동
           for(int j = i; j < m_position_count - 1; j++) {
               m_active_positions[j] = m_active_positions[j + 1];
           }
           
           m_position_count--;
           ArrayResize(m_active_positions, m_position_count);
           
           return true;
       }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 포지션 배열에서 업데이트                                         |
//+------------------------------------------------------------------+
bool CExecutionManager::UpdatePositionInArray(ulong ticket, const SOrderInfo &new_info) {
   for(int i = 0; i < m_position_count; i++) {
       if(m_active_positions[i].ticket == ticket) {
           m_active_positions[i] = new_info;
           return true;
       }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 포지션 배열에서 찾기                                             |
//+------------------------------------------------------------------+
int CExecutionManager::FindPositionInArray(ulong ticket) {
   for(int i = 0; i < m_position_count; i++) {
      if(m_active_positions[i].ticket == ticket) {
         return i;  // 인덱스 반환
      }
   }
   
   return -1; // 찾지 못함
}


//+------------------------------------------------------------------+
//| 실행 통계 업데이트                                               |
//+------------------------------------------------------------------+
void CExecutionManager::UpdateExecutionStats(bool success, double slippage) {
   m_execution_stats.total_orders++;
   
   if(success) {
       m_execution_stats.successful_orders++;
   } else {
       m_execution_stats.failed_orders++;
   }
   
   if(slippage > 0) {
       m_execution_stats.total_slippage += slippage;
       
       if(slippage > m_execution_stats.worst_slippage) {
           m_execution_stats.worst_slippage = slippage;
       }
   }
   
   if(m_execution_stats.successful_orders > 0) {
       m_execution_stats.avg_slippage = m_execution_stats.total_slippage / m_execution_stats.successful_orders;
   }
   
   m_execution_stats.last_execution = TimeCurrent();
}

//+------------------------------------------------------------------+
//| 주문 코멘트 생성                                                 |
//+------------------------------------------------------------------+
string CExecutionManager::GenerateOrderComment(const SEntrySignal &signal) {
   string comment = "MTF|";
   
   // 전략 정보 추가
   if(m_strategy_selector != NULL) {
       ENUM_STRATEGY_TYPE strategy = (*m_strategy_selector).GetCurrentStrategy();
       comment += (*m_strategy_selector).GetStrategyName(strategy) + "|";
   }
   
   // 신호 이유 추가 (최대 20자로 제한)
   string reason = signal.signal_reason;
   if(StringLen(reason) > 20) {
       reason = StringSubstr(reason, 0, 20);
   }
   comment += reason;
   
   return comment;
}

//+------------------------------------------------------------------+
//| 주문 오류 처리                                                   |
//+------------------------------------------------------------------+
bool CExecutionManager::HandleOrderError(int error_code, MqlTradeRequest &request) {
   switch(error_code) {
       case TRADE_RETCODE_REQUOTE:
       case TRADE_RETCODE_PRICE_CHANGED:
       case TRADE_RETCODE_PRICE_OFF:
           LogWarning("가격 변경 - 재시도 필요");
           return true; // 재시도 가능
           
       case TRADE_RETCODE_NO_MONEY:
           LogError("증거금 부족");
           return false;
           
       case TRADE_RETCODE_INVALID_STOPS:
           LogError("Invalid stops - SL/TP 조정 필요");
           return false;
           
       case TRADE_RETCODE_MARKET_CLOSED:
           LogError("시장 마감");
           return false;
           
       case TRADE_RETCODE_TRADE_DISABLED:
           LogError("거래 비활성화");
           return false;
           
       default:
           LogError("주문 오류: " + IntegerToString(error_code));
           return false;
   }
}

//+------------------------------------------------------------------+
//| 주문 실행 대기                                                   |
//+------------------------------------------------------------------+
bool CExecutionManager::WaitForOrderExecution(ulong ticket, int timeout_ms) {
   int elapsed = 0;
   int check_interval = 100; // 100ms마다 체크
   
   while(elapsed < timeout_ms) {
       if(PositionSelectByTicket(ticket)) {
           return true;
       }
       
       Sleep(check_interval);
       elapsed += check_interval;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 슬리피지 계산                                                    |
//+------------------------------------------------------------------+
double CExecutionManager::CalculateSlippage(double requested_price, double executed_price) {
   double slippage_points = MathAbs(executed_price - requested_price) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   return slippage_points;
}

//+------------------------------------------------------------------+
//| 포지션이 여전히 열려있는지 확인                                  |
//+------------------------------------------------------------------+
bool CExecutionManager::CheckPositionStillOpen(ulong ticket) {
   return PositionSelectByTicket(ticket);
}

//+------------------------------------------------------------------+
//| 실행 세부사항 로깅                                               |
//+------------------------------------------------------------------+
void CExecutionManager::LogExecutionDetails(const SExecutionResult &result) {
   string log_msg = "주문 실행 세부사항: ";
   log_msg += "Ticket=" + IntegerToString(result.ticket) + ", ";
   log_msg += "가격=" + DoubleToString(result.executed_price, _Digits) + ", ";
   log_msg += "슬리피지=" + DoubleToString(result.slippage, 1) + " points, ";
   log_msg += "시간=" + TimeToString(result.execution_time, TIME_DATE|TIME_SECONDS);
   
   LogDebug(log_msg);
}

//+------------------------------------------------------------------+
//| 실행 파라미터 설정                                               |
//+------------------------------------------------------------------+
void CExecutionManager::SetExecutionParameters(int max_retries, int slippage_points, double max_spread_points) {
   m_max_retries = max_retries;
   m_slippage_points = slippage_points;
   m_max_spread_points = max_spread_points;
   
   // CTrade 객체에도 적용
   m_trade.SetDeviationInPoints(slippage_points);
}

//+------------------------------------------------------------------+
//| 트레일링 스탑 파라미터 설정                                      |
//+------------------------------------------------------------------+
void CExecutionManager::SetTrailingStopParameters(bool use_trailing, double start_points, double step_points) {
   m_use_trailing_stop = use_trailing;
   m_trailing_start_points = start_points;
   m_trailing_step_points = step_points;
}

//+------------------------------------------------------------------+
//| 부분 청산 파라미터 설정                                          |
//+------------------------------------------------------------------+
void CExecutionManager::SetPartialCloseParameters(bool use_partial, double close_percent, double trigger_atr) {
   m_use_partial_close = use_partial;
   m_partial_close_percent = close_percent;
   m_partial_close_trigger = trigger_atr;
}

//+------------------------------------------------------------------+
//| 트레일링 스탑 제거                                               |
//+------------------------------------------------------------------+
bool CExecutionManager::RemoveTrailingStop(ulong ticket) {
   int pos_index = FindPositionInArray(ticket);
   
   if(pos_index >= 0) {
      m_active_positions[pos_index].has_trailing_stop = false;
      LogInfo("트레일링 스탑 제거: Ticket=" + IntegerToString(ticket));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 실행 통계 리셋                                                   |
//+------------------------------------------------------------------+
void CExecutionManager::ResetExecutionStats() {
   ZeroMemory(m_execution_stats);
   LogInfo("실행 통계 리셋 완료");
}

//+------------------------------------------------------------------+
//| 평균 슬리피지 반환                                               |
//+------------------------------------------------------------------+
double CExecutionManager::GetAverageSlippage() const {
   if(m_execution_stats.successful_orders > 0) {
       return m_execution_stats.avg_slippage;
   }
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| 성공률 반환                                                      |
//+------------------------------------------------------------------+
double CExecutionManager::GetSuccessRate() const {
   if(m_execution_stats.total_orders > 0) {
       return (double)m_execution_stats.successful_orders / (double)m_execution_stats.total_orders;
   }
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| 현재 상태 로깅                                                   |
//+------------------------------------------------------------------+
void CExecutionManager::LogCurrentStatus() {
   LogInfo("=== ExecutionManager 현재 상태 ===");
   LogInfo("활성 포지션: " + IntegerToString(m_position_count));
   LogInfo("긴급 모드: " + (m_emergency_mode ? "활성" : "비활성"));
   LogInfo("총 주문: " + IntegerToString(m_execution_stats.total_orders));
   LogInfo("성공률: " + DoubleToString(GetSuccessRate()*100, 1) + "%");
   LogInfo("평균 슬리피지: " + DoubleToString(GetAverageSlippage(), 1) + " points");
   
   SPositionSummary summary = GetPositionSummary();
   LogInfo("매수 포지션: " + IntegerToString(summary.buy_positions));
   LogInfo("매도 포지션: " + IntegerToString(summary.sell_positions));
   LogInfo("총 랏: " + DoubleToString(summary.total_lots, 2));
   LogInfo("총 손익: " + DoubleToString(summary.total_profit, 2));
}

//+------------------------------------------------------------------+
//| 자체 테스트                                                      |
//+------------------------------------------------------------------+
bool CExecutionManager::SelfTest() {
   LogInfo("ExecutionManager 자체 테스트 시작...");
   
   bool all_passed = true;
   
   // 1. 의존성 검증
   if(m_risk_manager == NULL) {
       LogError("RiskManager 포인터가 NULL");
       all_passed = false;
   }
   
   if(m_session_manager == NULL) {
       LogError("SessionManager 포인터가 NULL");
       all_passed = false;
   }
   
   if(m_strategy_selector == NULL) {
       LogError("StrategySelector 포인터가 NULL");
       all_passed = false;
   }
   
   // 2. 시장 상태 확인
   if(!IsMarketOpen()) {
       LogWarning("시장이 닫혀있음 (정상일 수 있음)");
   }
   
   // 3. 심볼 정보 검증
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   
   if(point <= 0 || min_lot <= 0) {
       LogError("심볼 정보가 유효하지 않음");
       all_passed = false;
   }
   
   // 4. 가격 정규화 테스트
   double test_price = 100.12345;
   double normalized = NormalizePrice(test_price);
   if(normalized <= 0) {
       LogError("가격 정규화 실패");
       all_passed = false;
   }
   
// 5. 랏 정규화 테스트
   double test_lot = 0.37;
   double normalized_lot = NormalizeLots(test_lot);
   if(normalized_lot <= 0) {
       LogError("랏 정규화 실패");
       all_passed = false;
   }
   
   if(all_passed) {
       LogInfo("ExecutionManager 자체 테스트 통과");
   } else {
       LogError("ExecutionManager 자체 테스트 실패");
   }
   
   return all_passed;
}

//+------------------------------------------------------------------+
//| 상태 리포트 생성                                                 |
//+------------------------------------------------------------------+
string CExecutionManager::GetStatusReport() {
   string report = "=== ExecutionManager 상태 리포트 ===\n";
   report += "Symbol: " + m_symbol + "\n";
   report += "Magic Number: " + IntegerToString(m_magic_number) + "\n";
   report += "긴급 모드: " + (m_emergency_mode ? "활성" : "비활성") + "\n\n";
   
   // 포지션 정보
   report += "=== 포지션 정보 ===\n";
   report += "활성 포지션: " + IntegerToString(m_position_count) + "\n";
   
   SPositionSummary summary = GetPositionSummary();
   report += "매수 포지션: " + IntegerToString(summary.buy_positions) + "\n";
   report += "매도 포지션: " + IntegerToString(summary.sell_positions) + "\n";
   report += "총 랏: " + DoubleToString(summary.total_lots, 2) + "\n";
   report += "총 손익: $" + DoubleToString(summary.total_profit, 2) + "\n";
   report += "총 노출: $" + DoubleToString(summary.total_exposure, 2) + "\n";
   report += "최대 포지션: " + DoubleToString(summary.largest_position, 2) + " lots\n\n";
   
   // 실행 통계
   report += "=== 실행 통계 ===\n";
   report += "총 주문: " + IntegerToString(m_execution_stats.total_orders) + "\n";
   report += "성공: " + IntegerToString(m_execution_stats.successful_orders) + "\n";
   report += "실패: " + IntegerToString(m_execution_stats.failed_orders) + "\n";
   report += "성공률: " + DoubleToString(GetSuccessRate()*100, 1) + "%\n";
   report += "평균 슬리피지: " + DoubleToString(m_execution_stats.avg_slippage, 1) + " points\n";
   report += "최악 슬리피지: " + DoubleToString(m_execution_stats.worst_slippage, 1) + " points\n";
   report += "재시도 횟수: " + IntegerToString(m_execution_stats.retry_count) + "\n";
   
   if(m_execution_stats.last_execution > 0) {
       report += "마지막 실행: " + TimeToString(m_execution_stats.last_execution, TIME_DATE|TIME_SECONDS) + "\n";
   }
   
   // 설정 정보
   report += "\n=== 설정 정보 ===\n";
   report += "최대 재시도: " + IntegerToString(m_max_retries) + "\n";
   report += "슬리피지 허용: " + IntegerToString(m_slippage_points) + " points\n";
   report += "최대 스프레드: " + DoubleToString(m_max_spread_points, 0) + " points\n";
   report += "트레일링 스탑: " + (m_use_trailing_stop ? "활성" : "비활성") + "\n";
   
   if(m_use_trailing_stop) {
       report += "  - 시작 거리: " + DoubleToString(m_trailing_start_points, 0) + " points\n";
       report += "  - 스텝: " + DoubleToString(m_trailing_step_points, 0) + " points\n";
   }
   
   report += "부분 청산: " + (m_use_partial_close ? "활성" : "비활성") + "\n";
   
   if(m_use_partial_close) {
       report += "  - 청산 비율: " + DoubleToString(m_partial_close_percent, 0) + "%\n";
       report += "  - 트리거: " + DoubleToString(m_partial_close_trigger, 1) + " ATR\n";
   }
   
   // 개별 포지션 정보
   if(m_position_count > 0) {
       report += "\n=== 개별 포지션 ===\n";
       
       for(int i = 0; i < m_position_count; i++) {
           report += IntegerToString(i+1) + ". Ticket=" + IntegerToString(m_active_positions[i].ticket);
           report += ", " + (m_active_positions[i].position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
           report += ", " + DoubleToString(m_active_positions[i].lots, 2) + " lots";
           report += ", Entry=" + DoubleToString(m_active_positions[i].entry_price, _Digits);
           
           if(PositionSelectByTicket(m_active_positions[i].ticket)) {
               double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
               double profit = PositionGetDouble(POSITION_PROFIT);
               report += ", Current=" + DoubleToString(current_price, _Digits);
               report += ", P&L=$" + DoubleToString(profit, 2);
           }
           
           report += "\n";
       }
   }
   
   return report;
}

//+------------------------------------------------------------------+
//| 포지션 오픈 (공개 메서드)                                        |
//+------------------------------------------------------------------+
SExecutionResult CExecutionManager::OpenPosition(ENUM_ORDER_TYPE type, double lots, double price, 
                                               double sl, double tp, string comment) {
   // 내부 신호 구조체 생성
   SEntrySignal signal;
   ZeroMemory(signal);
   
   signal.has_signal = true;
   signal.signal_type = type;
   signal.suggested_price = price;
   signal.suggested_sl = sl;
   signal.suggested_tp = tp;
   signal.suggested_lot = lots;
   signal.signal_strength = 1.0;
   signal.signal_reason = comment;
   signal.signal_time = TimeCurrent();
   signal.calculated_risk = 0;
   signal.risk_reward_ratio = 0;
   signal.risk_validated = true;
   signal.risk_validation_message = "외부 주문";
   
   // 기본 검증
   if(!ValidateOrderParameters(price, sl, tp, type)) {
       SExecutionResult result;
       ZeroMemory(result);
       result.success = false;
       result.error_message = "주문 파라미터 검증 실패";
       result.error_code = -1;
       return result;
   }
   
   // 실행
   return ExecuteMarketOrder(type, lots, sl, tp, comment);
}

#endif // __EXECUTION_MANAGER_MQH__