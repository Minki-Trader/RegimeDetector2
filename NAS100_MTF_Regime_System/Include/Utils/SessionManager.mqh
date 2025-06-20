//+------------------------------------------------------------------+
//|                                            SessionManager.mqh     |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// 포함 파일
#include "../RegimeDetection/RegimeDefinitions.mqh"
#include "../TimeFrames/TimeframeData.mqh"
#include "../Utils/Logger.mqh" 

// 세션 관리자 클래스
class CSessionManager
{
private:
   SSessionTimes m_session_times;    // 세션 시간 정보
   ESessionType m_current_session;   // 현재 세션
   datetime m_last_session_change;   // 마지막 세션 변경 시간
   bool m_is_session_transition;     // 세션 전환 여부
   
   // 서버 시간 오프셋 (GMT 기준)
   int m_server_hour_offset;

public:
   // 생성자
   CSessionManager()
   {
      // 기본 세션 시간 설정 (GMT 기준)
      m_session_times.asia_start_hour = 0;    // 00:00 GMT
      m_session_times.asia_end_hour = 8;      // 08:00 GMT
      m_session_times.europe_start_hour = 8;  // 08:00 GMT
      m_session_times.europe_end_hour = 16;   // 16:00 GMT
      m_session_times.us_start_hour = 14;     // 14:00 GMT (겹치는 부분 있음)
      m_session_times.us_end_hour = 24;       // 24:00 GMT
      
      m_current_session = SESSION_UNKNOWN;
      m_last_session_change = 0;
      m_is_session_transition = false;
      
      // 서버 시간 오프셋 계산
      CalculateServerTimeOffset();
   }
   
   // 서버 시간 오프셋 계산
   void CalculateServerTimeOffset()
   {
      datetime server_time = TimeCurrent();
      datetime gmt_time = TimeGMT();
      
      MqlDateTime server_dt, gmt_dt;
      TimeToStruct(server_time, server_dt);
      TimeToStruct(gmt_time, gmt_dt);
      
      // 간단한 시간 차이 계산 (정확한 구현은 더 복잡할 수 있음)
      m_server_hour_offset = server_dt.hour - gmt_dt.hour;
      
      // 오프셋이 큰 경우 조정 (날짜 변경선 고려)
      if(m_server_hour_offset > 12) m_server_hour_offset -= 24;
      if(m_server_hour_offset < -12) m_server_hour_offset += 24;
   }
   
   // 세션 시간 설정
   void SetSessionTimes(int asia_start, int asia_end, int europe_start, int europe_end, int us_start, int us_end)
   {
      m_session_times.asia_start_hour = asia_start;
      m_session_times.asia_end_hour = asia_end;
      m_session_times.europe_start_hour = europe_start;
      m_session_times.europe_end_hour = europe_end;
      m_session_times.us_start_hour = us_start;
      m_session_times.us_end_hour = us_end;
   }
   
   // 현재 세션 업데이트
   bool Update()
   {
      datetime current_time = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(current_time, dt);
      
      // GMT 기준 시간 계산
      int gmt_hour = (dt.hour - m_server_hour_offset + 24) % 24;
      
      // 이전 세션 저장
      ESessionType prev_session = m_current_session;
      
      // 현재 세션 결정
      if(gmt_hour >= m_session_times.asia_start_hour && 
         gmt_hour < m_session_times.asia_end_hour) {
         m_current_session = SESSION_ASIA;
      }
      else if(gmt_hour >= m_session_times.europe_start_hour && 
              gmt_hour < m_session_times.europe_end_hour) {
         m_current_session = SESSION_EUROPE;
      }
      else if(gmt_hour >= m_session_times.us_start_hour && 
              gmt_hour < m_session_times.us_end_hour) {
         m_current_session = SESSION_US;
      }
      else {
         // 세션 경계에 있지 않은 경우 (주말 또는 장 마감)
         m_current_session = SESSION_UNKNOWN;
      }
      
      // 세션 전환 여부 확인
      m_is_session_transition = (prev_session != m_current_session);
      
      // 세션이 변경된 경우 시간 기록
      if(m_is_session_transition) {
         m_last_session_change = current_time;
      }
      
      return true;
   }
   
   // 현재 세션 반환
   ESessionType GetCurrentSession() const
   {
      return m_current_session;
   }
   
   // 세션 전환 여부 확인
   bool IsSessionTransition() const
   {
      return m_is_session_transition;
   }
   
   // 세션 경과 시간 (분)
   int GetMinutesSinceSessionStart() const
   {
      datetime current_time = TimeCurrent();
      return (int)((current_time - m_last_session_change) / 60);
   }
   
   // 세션별 변동성 계수 반환 (세션별 특성 활용)
   double GetSessionVolatilityFactor() const
   {
      switch(m_current_session) {
         case SESSION_ASIA: return 0.7;     // 낮은 변동성
         case SESSION_EUROPE: return 1.0;   // 중간 변동성
         case SESSION_US: return 1.3;       // 높은 변동성
         default: return 0.5;               // 알 수 없음
      }
   }
   
   // 세션별 권장 타임프레임 가중치 배열 반환
   bool GetRecommendedTimeframeWeights(double &weights[])
   {
      // weights 배열은 [M5, M30, H4] 순서로 가중치 저장
      if(ArraySize(weights) < 3) {
         ArrayResize(weights, 3);
      }
      
      switch(m_current_session) {
         case SESSION_ASIA:
            // 아시아 세션: M5 및 M30 강조
            weights[0] = 0.4; // M5
            weights[1] = 0.4; // M30
            weights[2] = 0.2; // H4
            break;
            
         case SESSION_US:
            // 미국 세션: H4 강조
            weights[0] = 0.2; // M5
            weights[1] = 0.3; // M30
            weights[2] = 0.5; // H4
            break;
            
         default: // 유럽 세션 & 기타
            weights[0] = 0.3; // M5
            weights[1] = 0.4; // M30
            weights[2] = 0.3; // H4
      }
      
      return true;
   }
   
   // 최적 타임프레임 조합 반환
   STimeframeCombo GetOptimalTimeframeCombo(double volatility_level)
   {
      STimeframeCombo combo;
      
      // 기본값 설정
      combo.primary_tf = PERIOD_M5;     // M5는 항상 기본 진입/청산용
      
      // 세션과 변동성에 따른 타임프레임 조합 결정
      switch(m_current_session) {
         case SESSION_ASIA:
            if(volatility_level < 0.8) {  // 저변동 아시아 세션
               combo.confirm_tf = PERIOD_M15;
               combo.filter_tf = PERIOD_H1;
               combo.weights[0] = 0.3;    // M5
               combo.weights[1] = 0.4;    // M15
               combo.weights[2] = 0.3;    // H1
            } else {  // 고변동 아시아 세션 (뉴스 등으로 인한)
               combo.confirm_tf = PERIOD_M30;
               combo.filter_tf = PERIOD_H4;
               combo.weights[0] = 0.4;    // M5
               combo.weights[1] = 0.4;    // M30
               combo.weights[2] = 0.2;    // H4
            }
            break;
            
         case SESSION_EUROPE:
            // 유럽 세션: 중간 변동성 → 균형 잡힌 타임프레임 간격
            combo.confirm_tf = PERIOD_M30;
            combo.filter_tf = PERIOD_H4;
            combo.weights[0] = 0.3;    // M5
            combo.weights[1] = 0.4;    // M30
            combo.weights[2] = 0.3;    // H4
            break;
            
         case SESSION_US:
            if(volatility_level > 1.5) {  // 매우 높은 변동성 미국 세션
               combo.confirm_tf = PERIOD_M15;
               combo.filter_tf = PERIOD_H1;
               combo.weights[0] = 0.3;    // M5
               combo.weights[1] = 0.4;    // M15
               combo.weights[2] = 0.3;    // H1
            } else {  // 일반적인 미국 세션
               combo.confirm_tf = PERIOD_M30;
               combo.filter_tf = PERIOD_H4;
               combo.weights[0] = 0.2;    // M5
               combo.weights[1] = 0.3;    // M30
               combo.weights[2] = 0.5;    // H4
            }
            break;
            
         default:  // 알 수 없는 세션이나 주말
            combo.confirm_tf = PERIOD_M30;
            combo.filter_tf = PERIOD_H4;
            combo.weights[0] = 0.3;
            combo.weights[1] = 0.4;
            combo.weights[2] = 0.3;
      }
      
      return combo;
   }
};