//+------------------------------------------------------------------+
//|                                     MultiTimeframeManager.mqh     |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "..\RegimeDetection\RegimeDefinitions.mqh"
#include "TimeframeData.mqh"
#include "..\Utils\SessionManager.mqh"
#include "..\Utils\Logger.mqh"

// 다중 타임프레임 관리자 클래스
class CMultiTimeframeManager
{
private:
   string m_symbol;                     // 거래 심볼
   STimeframeData m_timeframe_data[];   // 타임프레임 데이터 배열
   STimeframeCombo m_current_combo;     // 현재 사용 중인 타임프레임 조합
   CSessionManager *m_session_manager;  // 세션 관리자에 대한 포인터
   
   int m_lookback_bars;                 // 가져올 봉 개수
   
   // 타임프레임 데이터 인덱스 찾기
   int FindTimeframeIndex(ENUM_TIMEFRAMES timeframe);

public:
   // 생성자 및 소멸자
   CMultiTimeframeManager(string symbol, CSessionManager *session_manager);
   ~CMultiTimeframeManager();
   
   // 데이터 초기화 및 업데이트
   bool Initialize();
   bool UpdateData();
   bool UpdateData(ENUM_TIMEFRAMES timeframe);
   
   // 타임프레임 조합 설정 및 최적화
   void SetTimeframeCombo(const STimeframeCombo &combo);
   void OptimizeTimeframeCombo(double volatility_level);
   STimeframeCombo GetCurrentTimeframeCombo() const;
   
   // 데이터 액세스
   bool GetTimeframeData(ENUM_TIMEFRAMES timeframe, STimeframeData &data);
   bool GetRates(ENUM_TIMEFRAMES timeframe, MqlRates &rates[], int &count);
   bool SetRegimeData(ENUM_TIMEFRAMES timeframe, const SRegimeData &regime_data);
};
   
// 생성자
CMultiTimeframeManager::CMultiTimeframeManager(string symbol, CSessionManager *session_manager) {
   m_symbol = symbol;
   m_session_manager = session_manager;
   m_lookback_bars = 300; // 기본값으로 300봉 데이터 유지
   
   // 기본 타임프레임 조합 설정
   m_current_combo.primary_tf = PERIOD_M5;
   m_current_combo.confirm_tf = PERIOD_M30;
   m_current_combo.filter_tf = PERIOD_H4;
   m_current_combo.weights[0] = 0.3;
   m_current_combo.weights[1] = 0.4;
   m_current_combo.weights[2] = 0.3;
}

// 소멸자
CMultiTimeframeManager::~CMultiTimeframeManager() {
   // 필요한 정리 작업이 있다면 여기에 구현
}

// 타임프레임 데이터 인덱스 찾기
int CMultiTimeframeManager::FindTimeframeIndex(ENUM_TIMEFRAMES timeframe) {
   for(int i = 0; i < ArraySize(m_timeframe_data); i++) {
      if(m_timeframe_data[i].timeframe == timeframe) {
         return i;
      }
   }
   
   return -1; // 찾지 못한 경우
}

// 데이터 초기화
bool CMultiTimeframeManager::Initialize() {
   // 기본 타임프레임 조합에 맞게 데이터 배열 초기화
   ArrayResize(m_timeframe_data, 3);
   
   // 주 타임프레임 (M5)
   m_timeframe_data[0].timeframe = m_current_combo.primary_tf;
   m_timeframe_data[0].bars_count = 0;
   m_timeframe_data[0].last_update = 0;
   
   // 확인 타임프레임 (기본 M30)
   m_timeframe_data[1].timeframe = m_current_combo.confirm_tf;
   m_timeframe_data[1].bars_count = 0;
   m_timeframe_data[1].last_update = 0;
   
   // 필터 타임프레임 (기본 H4)
   m_timeframe_data[2].timeframe = m_current_combo.filter_tf;
   m_timeframe_data[2].bars_count = 0;
   m_timeframe_data[2].last_update = 0;
   
   // 모든 타임프레임 데이터 초기 로드
   return UpdateData();
}

// 모든 타임프레임 데이터 업데이트
bool CMultiTimeframeManager::UpdateData() {
   bool success = true;
   
   // 세 가지 타임프레임 모두 업데이트
   for(int i = 0; i < ArraySize(m_timeframe_data); i++) {
      if(!UpdateData(m_timeframe_data[i].timeframe)) {
         LogError("MultiTimeframeManager: " + EnumToString(m_timeframe_data[i].timeframe) + " 데이터 업데이트 실패");
      }
   }
   
   return success;
}

// 특정 타임프레임 데이터 업데이트
bool CMultiTimeframeManager::UpdateData(ENUM_TIMEFRAMES timeframe) {
   int idx = FindTimeframeIndex(timeframe);
   
   // 타임프레임을 찾지 못한 경우
   if(idx == -1) {
      LogError("MultiTimeframeManager: 타임프레임 " + EnumToString(timeframe) + " 인덱스를 찾을 수 없음");
      return false;
   }
   
   // 데이터 가져오기
   MqlRates temp_rates[];
   ArraySetAsSeries(temp_rates, true);
   
   int copied = CopyRates(m_symbol, timeframe, 0, m_lookback_bars, temp_rates);
   
   if(copied <= 0) {
      int error = GetLastError();
      LogError("MultiTimeframeManager: 타임프레임 " + EnumToString(timeframe) + 
          " 데이터 복사 실패, 에러: " + IntegerToString(error) + ", 심볼: " + m_symbol);
      return false;
   }
   
   // 데이터 저장
   ArrayResize(m_timeframe_data[idx].rates, copied);
   ArrayCopy(m_timeframe_data[idx].rates, temp_rates);
   m_timeframe_data[idx].bars_count = copied;
   m_timeframe_data[idx].last_update = TimeCurrent();
   
   return true;
}

// 타임프레임 조합 설정
void CMultiTimeframeManager::SetTimeframeCombo(const STimeframeCombo &combo) {
   // 이전 타임프레임과 다른 경우만 처리
   if(m_current_combo.primary_tf != combo.primary_tf ||
      m_current_combo.confirm_tf != combo.confirm_tf ||
      m_current_combo.filter_tf != combo.filter_tf) {
      
      // 새 조합 저장
      m_current_combo = combo;
      
      // 타임프레임 데이터 배열 재구성
      ArrayResize(m_timeframe_data, 3);
      
      // 주 타임프레임
      m_timeframe_data[0].timeframe = combo.primary_tf;
      m_timeframe_data[0].bars_count = 0;
      m_timeframe_data[0].last_update = 0;
      
      // 확인 타임프레임
      m_timeframe_data[1].timeframe = combo.confirm_tf;
      m_timeframe_data[1].bars_count = 0;
      m_timeframe_data[1].last_update = 0;
      
      // 필터 타임프레임
      m_timeframe_data[2].timeframe = combo.filter_tf;
      m_timeframe_data[2].bars_count = 0;
      m_timeframe_data[2].last_update = 0;
      
      // 데이터 다시 로드
      UpdateData();
   } else {
      // 가중치만 업데이트
      for(int i = 0; i < 3; i++) {
         m_current_combo.weights[i] = combo.weights[i];
      }
   }
}

// 현재 세션과 변동성에 따라 타임프레임 조합 최적화
void CMultiTimeframeManager::OptimizeTimeframeCombo(double volatility_level) {
   // 세션 관리자로부터 최적 조합 가져오기
   if(m_session_manager != NULL) {
      STimeframeCombo optimal_combo = m_session_manager.GetOptimalTimeframeCombo(volatility_level);
      SetTimeframeCombo(optimal_combo);
   }
}

// 현재 타임프레임 조합 반환
STimeframeCombo CMultiTimeframeManager::GetCurrentTimeframeCombo() const {
   return m_current_combo;
}

// 타임프레임 데이터 가져오기
bool CMultiTimeframeManager::GetTimeframeData(ENUM_TIMEFRAMES timeframe, STimeframeData &data) {
   int idx = FindTimeframeIndex(timeframe);
   
   // 타임프레임을 찾지 못한 경우
   if(idx == -1) return false;
   
   // 데이터 복사
   data = m_timeframe_data[idx];
   
   return true;
}

// 가격 데이터 가져오기
bool CMultiTimeframeManager::GetRates(ENUM_TIMEFRAMES timeframe, MqlRates &rates[], int &count) {
   int idx = FindTimeframeIndex(timeframe);
   
   // 타임프레임을 찾지 못한 경우
   if(idx == -1) {
      count = 0;
      return false;
   }
   
   // 배열 크기 조정 및 데이터 복사
   count = m_timeframe_data[idx].bars_count;
   ArrayResize(rates, count);
   ArrayCopy(rates, m_timeframe_data[idx].rates);
   
   return true;
}

// 파일 끝부분, 마지막 메서드(GetRates) 다음에 추가
bool CMultiTimeframeManager::SetRegimeData(ENUM_TIMEFRAMES timeframe, const SRegimeData &regime_data) {
    int idx = FindTimeframeIndex(timeframe);
    
    // 타임프레임을 찾지 못한 경우
    if(idx == -1) return false;
    
    // 레짐 데이터 업데이트
    m_timeframe_data[idx].regime_data = regime_data;
    
    return true;
}