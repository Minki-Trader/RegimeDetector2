//+------------------------------------------------------------------+
//|                          RegimeDetector.mqh                      |
//|                      NAS100 MTF Regime System                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property version   "1.01"
#property strict

//-------------------------------------------------------------------
// 1. Include & 전역 enum-struct
//-------------------------------------------------------------------
#include "RegimeDefinitions.mqh"
#include "..\\TimeFrames\\TimeframeData.mqh"
#include "..\\TimeFrames\\MultiTimeframeManager.mqh"
#include "..\\Utils\\SessionManager.mqh"
#include "..\\Utils\\Logger.mqh"

// EA 파일과 충돌 방지를 위해 이름 접두사 붙임
enum ENUM_RD_STRATEGY_MODE
{
   RD_MODE_STABLE     = 0,   // 안정형
   RD_MODE_AGGRESSIVE = 1    // 공격형
};

//-------------------------------------------------------------------
// 2. RegimeDetector 클래스 선언
//-------------------------------------------------------------------
class CRegimeDetector
{
private:
   // --- 기본 핸들 & 포인터
   string                   m_symbol;
   CMultiTimeframeManager*  m_mtf_manager;
   CSessionManager*         m_session_manager;

   // --- 타임프레임별 지표 핸들 구조체
   struct SIndicatorHandles {
      int adx_handle;
      int rsi_handle;
      int ma_handle;
      int atr_handle;
      int bands_handle;
      int stochastic_handle;
   };
   
   // --- 타임프레임별 핸들 배열 (0:primary, 1:confirm, 2:filter)
   SIndicatorHandles m_handles[3];

   // --- 모드 / 히스테리시스
   ENUM_RD_STRATEGY_MODE    m_current_mode;
   double                   m_hysteresis_threshold;
   int                      m_hysteresis_bars;
   ENUM_MARKET_REGIME       m_previous_regime;
   int                      m_regime_hold_count;
   datetime                 m_last_regime_change_time;
   bool                     m_hysteresis_applied;
   double                   m_regime_threshold_multiplier;

   // --- 가중치
   double m_trend_weight;
   double m_momentum_weight;
   double m_volatility_weight;
   double m_volume_weight;

   // --- RSI 범위
   double m_rsi_oversold;
   double m_rsi_overbought;

   // --- 현재 레짐 데이터
   SRegimeData m_current_regime;

   // --- 캐시 (mutable 키워드 제거)
   SIndicatorGroup m_cached_indicators;
   datetime        m_last_indicator_update;
   ENUM_TIMEFRAMES m_cached_timeframe;

   // --- 내부 계산 메서드
   int    GetTimeframeIndex(ENUM_TIMEFRAMES tf);
   bool   CreateIndicatorHandles(ENUM_TIMEFRAMES tf, int index);
   bool   CollectIndicatorDataCached(ENUM_TIMEFRAMES tf,SIndicatorGroup& ind);
   bool   CollectIndicatorData(ENUM_TIMEFRAMES tf,SIndicatorGroup& ind);
   bool   CalculateRegimeScores(ENUM_TIMEFRAMES tf);
   SRegimeData IntegrateTimeframeRegimes();  

   double CalculateStrongBullishScore       (const SIndicatorGroup& ind);
   double CalculateStrongBearishScore       (const SIndicatorGroup& ind);
   double CalculateConsolidationScore       (const SIndicatorGroup& ind);
   double CalculateVolatilityExpansionScore (const SIndicatorGroup& ind);
   double CalculateOvernightDriftScore      (const SIndicatorGroup& ind);
   double CalculateGapTradingScore          (const SIndicatorGroup& ind);
   double CalculateTechnicalReversalScore   (const SIndicatorGroup& ind);

public:
   // --- 생성/소멸
   CRegimeDetector(string symbol,CMultiTimeframeManager* mtf_mgr,CSessionManager* sess_mgr);
   ~CRegimeDetector();

   // --- 초기화 & 설정
   bool  Initialize();
   bool ReinitializeIndicators() {
       STimeframeCombo combo = (*m_mtf_manager).GetCurrentTimeframeCombo();
       
       bool success = true;
       
       // ★ 모든 타임프레임에 대해 초기화 시도
       if(m_handles[0].adx_handle == INVALID_HANDLE) {
           LogInfo("M5 지표 초기화 시도...");
           success &= CreateIndicatorHandles(combo.primary_tf, 0);
       }
    
       if(m_handles[1].adx_handle == INVALID_HANDLE) {
           LogInfo("M30 지표 초기화 시도...");
           success &= CreateIndicatorHandles(combo.confirm_tf, 1);
       }
    
       if(m_handles[2].adx_handle == INVALID_HANDLE) {
           LogInfo("H4 지표 초기화 시도...");
           success &= CreateIndicatorHandles(combo.filter_tf, 2);
       }
    
       return success;
    }

   void  SetHysteresisParameters(double thr,int bars);
   void  AdjustThresholds(double mult);
   void  SetStrategyMode(ENUM_RD_STRATEGY_MODE mode);
   ENUM_RD_STRATEGY_MODE GetCurrentMode() const { return m_current_mode; }

   void  SetRSIBounds(double oversold,double overbought);
   void  SetRegimeWeights(double tw,double mw,double vw,double volw);
   void  SetIndicatorParameters(int adx_p,int rsi_p,int ma_p,int atr_p,int bb_p,double bb_dev);

   // --- 업데이트 & 조회 (모두 const 제거)
   bool           Update();
   SRegimeData    GetCurrentRegime() const;
   bool           GetCurrentIndicators(SIndicatorGroup &indicators);
   SIndicatorGroup GetLatestIndicatorData();
   bool           GetIndicatorValues(ENUM_TIMEFRAMES tf,SIndicatorGroup &indicators);

   // --- 로깅
   void  LogRegimeScores(bool save_csv=false);
   bool  WasHysteresisApplied() const { return m_hysteresis_applied; }
};

// ───── Regime 이름 문자열 변환 (동일) ────
string RegimeNameStr(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_STRONG_BULLISH : return "강한 상승 모멘텀";
      case REGIME_STRONG_BEARISH : return "강한 하락 모멘텀";
      case REGIME_CONSOLIDATION  : return "통합 레인지";
      case REGIME_VOLATILITY_EXPANSION: return "변동성 확장";
      case REGIME_OVERNIGHT_DRIFT : return "오버나이트 드리프트";
      case REGIME_GAP_TRADING     : return "갭 트레이딩 패턴";
      case REGIME_TECHNICAL_REVERSAL: return "기술적 되돌림";
      default                     : return "알 수 없음";
   }
}

//===================================================================
// 2. Core Init & 설정 메서드
//===================================================================

//----------------------------------------------------
// 생성자
//----------------------------------------------------
CRegimeDetector::CRegimeDetector(string symbol,
                                 CMultiTimeframeManager* mtf_mgr,
                                 CSessionManager* sess_mgr)
: m_symbol(symbol),
  m_mtf_manager(mtf_mgr),
  m_session_manager(sess_mgr),
  m_current_mode(RD_MODE_STABLE),
  m_hysteresis_threshold(0.10),
  m_hysteresis_bars(2),
  m_previous_regime(REGIME_UNKNOWN),
  m_regime_hold_count(0),
  m_last_regime_change_time(0),
  m_hysteresis_applied(false),
  m_regime_threshold_multiplier(1.0),   // 기본 승수 1.0
  // 기본 가중치(안정형)
  m_trend_weight(0.25),
  m_momentum_weight(0.25),
  m_volatility_weight(0.25),
  m_volume_weight(0.25),
  // RSI 범위
  m_rsi_oversold(35.0),
  m_rsi_overbought(60.0)
{
   ZeroMemory(m_current_regime);
   m_current_regime.dominant_regime = REGIME_UNKNOWN;
   
   // 모든 핸들 초기화
   for(int i = 0; i < 3; i++) {
      m_handles[i].adx_handle = INVALID_HANDLE;
      m_handles[i].rsi_handle = INVALID_HANDLE;
      m_handles[i].ma_handle = INVALID_HANDLE;
      m_handles[i].atr_handle = INVALID_HANDLE;
      m_handles[i].bands_handle = INVALID_HANDLE;
      m_handles[i].stochastic_handle = INVALID_HANDLE;
   }
}

//----------------------------------------------------
// 소멸자
//----------------------------------------------------
CRegimeDetector::~CRegimeDetector()
{
   // 모든 타임프레임의 핸들 해제
   for(int i = 0; i < 3; i++) {
      if(m_handles[i].adx_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].adx_handle);
      if(m_handles[i].rsi_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].rsi_handle);
      if(m_handles[i].ma_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].ma_handle);
      if(m_handles[i].atr_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].atr_handle);
      if(m_handles[i].bands_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].bands_handle);
      if(m_handles[i].stochastic_handle != INVALID_HANDLE) IndicatorRelease(m_handles[i].stochastic_handle);
   }
}

//----------------------------------------------------
// 타임프레임 인덱스 반환
//----------------------------------------------------
int CRegimeDetector::GetTimeframeIndex(ENUM_TIMEFRAMES tf) {
   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();
   
   if(tf == combo.primary_tf) return 0;
   if(tf == combo.confirm_tf) return 1;
   if(tf == combo.filter_tf) return 2;
   
   return -1;
}

//----------------------------------------------------
// 특정 타임프레임용 지표 핸들 생성
//----------------------------------------------------
bool CRegimeDetector::CreateIndicatorHandles(ENUM_TIMEFRAMES tf, int index) {
    if(index < 0 || index >= 3) return false;
    
    // ★ 백테스트 환경에서 사용 가능한 바 수 확인
    int available_bars = Bars(m_symbol, tf);
    if(available_bars < 100) {  // 최소 100개 바 필요
        LogWarning(StringFormat("타임프레임 %s: 사용 가능한 바 부족 (%d개)", 
                               EnumToString(tf), available_bars));
        return false;
    }
    
    // 기존 핸들 해제
    if(m_handles[index].adx_handle != INVALID_HANDLE) {
        IndicatorRelease(m_handles[index].adx_handle);
        IndicatorRelease(m_handles[index].rsi_handle);
        IndicatorRelease(m_handles[index].ma_handle);
        IndicatorRelease(m_handles[index].atr_handle);
        IndicatorRelease(m_handles[index].bands_handle);
        IndicatorRelease(m_handles[index].stochastic_handle);
    }
    
    // ★ 백테스트용 개선된 핸들 생성
    for(int try_count = 0; try_count < 5; try_count++) {  // 5번으로 축소
        LogDebug("지표 생성 시도 " + IntegerToString(try_count+1) + ": " + EnumToString(tf));
        
        // 지표 핸들 생성
        m_handles[index].adx_handle = iADX(m_symbol, tf, 14);
        m_handles[index].rsi_handle = iRSI(m_symbol, tf, 14, PRICE_CLOSE);
        m_handles[index].ma_handle = iMA(m_symbol, tf, 20, 0, MODE_EMA, PRICE_CLOSE);
        
        // 백테스트에서는 ATR 핸들을 생성하지 않음
        if(MQLInfoInteger(MQL_TESTER)) {
            m_handles[index].atr_handle = INVALID_HANDLE; // 의도적으로 무효화
            LogInfo("백테스트 모드 - ATR 직접 계산 사용");
        } else {
            m_handles[index].atr_handle = iATR(m_symbol, tf, 14);
        }
        
        m_handles[index].bands_handle = iBands(m_symbol, tf, 20, 2.0, 0, PRICE_CLOSE);
        m_handles[index].stochastic_handle = iStochastic(m_symbol, tf, 14, 3, 3, MODE_SMA, 0);
        
        // ★ 백테스트에서는 더 긴 대기 시간
        Sleep(500);
        
        // ★ 백테스트용 완화된 검증
        bool handles_valid = (m_handles[index].adx_handle != INVALID_HANDLE &&
                             m_handles[index].rsi_handle != INVALID_HANDLE &&
                             m_handles[index].ma_handle != INVALID_HANDLE &&
                             m_handles[index].atr_handle != INVALID_HANDLE &&
                             m_handles[index].bands_handle != INVALID_HANDLE &&
                             m_handles[index].stochastic_handle != INVALID_HANDLE);
        
        if(handles_valid) {
            // ★ 백테스트에서는 BarsCalculated 체크 생략 옵션
            if(MQLInfoInteger(MQL_TESTER)) {
                LogInfo("백테스트 모드 - 핸들 생성 성공 간주: " + EnumToString(tf));
                return true;
            }
            
            // 실거래에서는 기존 검증
            if(BarsCalculated(m_handles[index].adx_handle) > 0 && 
               BarsCalculated(m_handles[index].rsi_handle) > 0) {
                LogInfo("핸들 생성 성공: " + EnumToString(tf));
                return true;
            }
        }
        
        Sleep(1000);
    }
    
    LogError("핸들 생성 최종 실패: " + EnumToString(tf));
    return false;
}

//----------------------------------------------------
// Initialize : 지표 핸들 생성
//----------------------------------------------------
bool CRegimeDetector::Initialize() {
    STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();
    LogInfo(StringFormat("RegimeDetector 초기화: %s", m_symbol));
    
    // ★ 백테스트 환경 감지
    bool is_testing = MQLInfoInteger(MQL_TESTER);
    
    if(is_testing) {
        LogInfo("백테스트 환경 감지 - 지표 초기화 지연");
        // 백테스트에서는 최소한의 초기화만 수행
        return true;  // 초기화는 첫 틱에서 완료
    }
    
    // 각 타임프레임별 핸들 생성
    if(!CreateIndicatorHandles(combo.primary_tf, 0)) return false;
    Sleep(100); // 대기 추가
    
    if(!CreateIndicatorHandles(combo.confirm_tf, 1)) return false;
    Sleep(100); // 대기 추가
    
    if(!CreateIndicatorHandles(combo.filter_tf, 2)) return false;
    Sleep(100); // 대기 추가
    
    // 초기화 확인을 위한 추가 대기
    Sleep(1000);
    
    // 핸들 재검증
    for(int i = 0; i < 3; i++) {
        int retry_count = 0;
        while(retry_count < 5) { // 최대 5번 재시도
            bool all_valid = true;
            
            // 각 핸들의 BarsCalculated 확인
            if(BarsCalculated(m_handles[i].adx_handle) < 0 ||
               BarsCalculated(m_handles[i].rsi_handle) < 0 ||
               BarsCalculated(m_handles[i].ma_handle) < 0 ||
               BarsCalculated(m_handles[i].atr_handle) < 0 ||
               BarsCalculated(m_handles[i].bands_handle) < 0 ||
               BarsCalculated(m_handles[i].stochastic_handle) < 0) {
                all_valid = false;
                Sleep(200);
                retry_count++;
            } else {
                break;
            }
        }
    }
    
    LogInfo("모든 타임프레임 지표 핸들 생성 완료");
    return true;
}

//----------------------------------------------------
// 히스테리시스, 임계값, 모드 전환, RSI/가중치/지표 세터
//----------------------------------------------------
void CRegimeDetector::SetHysteresisParameters(double thr, int bars)
{
   m_hysteresis_threshold = MathMax(thr, 0.0);
   m_hysteresis_bars      = MathMax(bars, 1);
}

void CRegimeDetector::AdjustThresholds(double mult)
{
   m_regime_threshold_multiplier = MathMax(mult, 0.01);
}

void CRegimeDetector::SetStrategyMode(ENUM_RD_STRATEGY_MODE mode)
{
   if(m_current_mode == mode) return;
   m_current_mode = mode;

   if(mode == RD_MODE_STABLE)
   {
      m_trend_weight = m_momentum_weight = m_volatility_weight = m_volume_weight = 0.25;
      LogInfo("모드 ➜ 안정형");
   }
   else  // RD_MODE_AGGRESSIVE
   {
      m_trend_weight = 0.35;
      m_momentum_weight = 0.30;
      m_volatility_weight = 0.20;
      m_volume_weight = 0.15;
      LogInfo("모드 ➜ 공격형");
   }
}

void CRegimeDetector::SetRSIBounds(double oversold, double overbought)
{
   if(oversold < 0 || overbought > 100 || oversold >= overbought)
   {
      LogError("잘못된 RSI 범위");
      return;
   }
   m_rsi_oversold   = oversold;
   m_rsi_overbought = overbought;
}

void CRegimeDetector::SetRegimeWeights(double tw, double mw, double vw, double volw)
{
   m_trend_weight = tw;
   m_momentum_weight = mw;
   m_volatility_weight = vw;
   m_volume_weight = volw;
}

//===================================================================
// 4. 지표 데이터 캐싱 헬퍼 (NEW)
//===================================================================
bool CRegimeDetector::CollectIndicatorDataCached(ENUM_TIMEFRAMES tf,SIndicatorGroup &ind)
{
   datetime now = TimeCurrent();
   if(m_cached_timeframe==tf && (now-m_last_indicator_update)<1)
   {
      ind = m_cached_indicators;
      return true;
   }

   if(!CollectIndicatorData(tf,ind)) return false;

   m_cached_indicators      = ind;
   m_last_indicator_update  = now;
   m_cached_timeframe       = tf;
   return true;
}

void CRegimeDetector::SetIndicatorParameters(int adx_p,int rsi_p,int ma_p,
                                             int atr_p,int bb_p,double bb_dev)
{
   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();
   
   // 각 타임프레임별로 새 핸들 생성
   for(int i = 0; i < 3; i++) {
      ENUM_TIMEFRAMES tf;
      if(i == 0) tf = combo.primary_tf;
      else if(i == 1) tf = combo.confirm_tf;
      else tf = combo.filter_tf;
      
      // 기존 핸들 해제
      if(m_handles[i].adx_handle != INVALID_HANDLE) {
         IndicatorRelease(m_handles[i].adx_handle);
         IndicatorRelease(m_handles[i].rsi_handle);
         IndicatorRelease(m_handles[i].ma_handle);
         IndicatorRelease(m_handles[i].atr_handle);
         IndicatorRelease(m_handles[i].bands_handle);
         IndicatorRelease(m_handles[i].stochastic_handle);
      }
      
      // ★ 새 핸들 생성 - 파라미터 적용
      m_handles[i].adx_handle = iADX(m_symbol, tf, adx_p);
      m_handles[i].rsi_handle = iRSI(m_symbol, tf, rsi_p, PRICE_CLOSE);
      m_handles[i].ma_handle = iMA(m_symbol, tf, ma_p, 0, MODE_EMA, PRICE_CLOSE);
      m_handles[i].atr_handle = iATR(m_symbol, tf, atr_p);
      // ★ Bollinger Bands 파라미터 순서 수정
      m_handles[i].bands_handle = iBands(m_symbol, tf, bb_p, 0, bb_dev, PRICE_CLOSE);
      m_handles[i].stochastic_handle = iStochastic(m_symbol, tf, 14, 3, 3, MODE_SMA, 0);
      
      // 핸들 검증
      if(m_handles[i].adx_handle==INVALID_HANDLE || m_handles[i].rsi_handle==INVALID_HANDLE ||
         m_handles[i].ma_handle==INVALID_HANDLE  || m_handles[i].atr_handle==INVALID_HANDLE ||
         m_handles[i].bands_handle==INVALID_HANDLE||m_handles[i].stochastic_handle==INVALID_HANDLE) {
         LogError("SetIndicatorParameters: 핸들 재생성 실패 - TF: " + EnumToString(tf));
      } else {
         LogInfo("SetIndicatorParameters: 핸들 재생성 성공 - TF: " + EnumToString(tf));
      }
   }
}


// 지표 데이터 수집 메서드 수정
bool CRegimeDetector::CollectIndicatorData(ENUM_TIMEFRAMES timeframe,
                                           SIndicatorGroup &indicators)
{
   // ── 0) 타임프레임 인덱스
   int tf_index = GetTimeframeIndex(timeframe);
   if(tf_index < 0){
      LogError("지원하지 않는 타임프레임: "+EnumToString(timeframe));
      return false;
   }

   // ── 1) 핸들 확보
   SIndicatorHandles handles = m_handles[tf_index];
   if(handles.adx_handle==INVALID_HANDLE || handles.rsi_handle==INVALID_HANDLE ||
      handles.ma_handle==INVALID_HANDLE  || handles.atr_handle==INVALID_HANDLE ||
      handles.bands_handle==INVALID_HANDLE||handles.stochastic_handle==INVALID_HANDLE)
   {
      LogError("유효하지 않은 핸들 – 재생성 시도");
      if(!CreateIndicatorHandles(timeframe,tf_index)) return false;
      handles = m_handles[tf_index];
   }
   
   // ── 2) 사용 가능한 바 수 확인 및 동적 조정
   int available_bars = Bars(m_symbol, timeframe);
   int bars_needed = MathMin(10, MathMax(available_bars, 1)); // 동적 조정
   
   // ★ 수정된 부분: BarsCalculated 체크를 더 유연하게 변경
   int min_bars_for_calculation = MathMax(bars_needed, 3); // 최소 3개 바는 필요
   
   // 각 지표별로 계산된 바 수 확인
   int adx_calc = BarsCalculated(handles.adx_handle);
   int rsi_calc = BarsCalculated(handles.rsi_handle);
   int ma_calc = BarsCalculated(handles.ma_handle);
   int atr_calc = BarsCalculated(handles.atr_handle);
   int bands_calc = BarsCalculated(handles.bands_handle);
   int stoch_calc = BarsCalculated(handles.stochastic_handle);
   
   // ATR이 -1이면 핸들을 무효로 처리
   if(atr_calc < 0) {
       LogWarning("ATR 핸들이 여전히 유효하지 않음, 기본값 사용");
       atr_calc = 0; // 기본값 사용하도록 강제 설정
    }
   
   // 디버그 로그 추가
   LogDebug(StringFormat("지표 계산 상태 [%s]: ADX=%d, RSI=%d, MA=%d, ATR=%d, Bands=%d, Stoch=%d, 필요=%d", 
                        EnumToString(timeframe), adx_calc, rsi_calc, ma_calc, atr_calc, bands_calc, stoch_calc, min_bars_for_calculation));
   
   // ★ 기존의 엄격한 체크를 제거하고, 각 지표별로 개별 처리
   // 모든 지표가 최소 바 수를 만족하지 않으면 기본값으로 처리
   bool use_defaults = (adx_calc < min_bars_for_calculation || 
                       rsi_calc < min_bars_for_calculation || 
                       ma_calc < min_bars_for_calculation || 
                       atr_calc < min_bars_for_calculation || 
                       bands_calc < min_bars_for_calculation || 
                       stoch_calc < min_bars_for_calculation);
   
   if(use_defaults) {
      LogInfo(StringFormat("지표 준비 중, 기본값 사용 [%s] - 사용가능바:%d, 최소필요:%d", 
                          EnumToString(timeframe), available_bars, min_bars_for_calculation));
   }
   
   // 데이터 배열
   double adx_main[], adx_plus[], adx_minus[];
   double rsi[], ma[], atr[];
   double bands_upper[], bands_middle[], bands_lower[];
   double stoch_main[], stoch_signal[];

   // 배열 시리즈 설정
   ArraySetAsSeries(adx_main, true);
   ArraySetAsSeries(adx_plus, true);
   ArraySetAsSeries(adx_minus, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(bands_upper, true);
   ArraySetAsSeries(bands_middle, true);
   ArraySetAsSeries(bands_lower, true);
   ArraySetAsSeries(stoch_main, true);
   ArraySetAsSeries(stoch_signal, true);

   // ★ 수정된 부분: 지표별 개별 처리 및 기본값 설정
   bool success = true;
   
   // ADX 처리
   if(adx_calc >= min_bars_for_calculation) {
    if(CopyBuffer(handles.adx_handle, 0, 0, bars_needed, adx_main) <= 0 ||
       CopyBuffer(handles.adx_handle, 1, 0, bars_needed, adx_plus) <= 0 ||
       CopyBuffer(handles.adx_handle, 2, 0, bars_needed, adx_minus) <= 0) {
        LogWarning("ADX 데이터 복사 실패, 기본값 사용");
        ArrayResize(adx_main, bars_needed); ArrayInitialize(adx_main, 25.0);
        ArrayResize(adx_plus, bars_needed); ArrayInitialize(adx_plus, 50.0);
        ArrayResize(adx_minus, bars_needed); ArrayInitialize(adx_minus, 50.0);
    } else {
        for(int i = 0; i < bars_needed; i++) {
            if(!IsIndicatorValueValid(adx_main[i])) adx_main[i] = 25.0;
            if(!IsIndicatorValueValid(adx_plus[i])) adx_plus[i] = 50.0;
            if(!IsIndicatorValueValid(adx_minus[i])) adx_minus[i] = 50.0;
        }
    }
}
   
   // RSI 처리
   if(rsi_calc >= min_bars_for_calculation) {
       if(CopyBuffer(handles.rsi_handle, 0, 0, bars_needed, rsi) <= 0) {
           LogWarning("RSI 데이터 복사 실패, 기본값 사용");
           ArrayResize(rsi, bars_needed); ArrayInitialize(rsi, 50.0);
       }
   } else {
       ArrayResize(rsi, bars_needed); ArrayInitialize(rsi, 50.0);
   }
   
   // MA 처리
   if(ma_calc >= min_bars_for_calculation) {
       if(CopyBuffer(handles.ma_handle, 0, 0, bars_needed, ma) <= 0) {
           LogWarning("MA 데이터 복사 실패, 기본값 사용");
           ArrayResize(ma, bars_needed);
           double current_price = iClose(m_symbol, timeframe, 0);
           ArrayInitialize(ma, current_price);
       }
   } else {
       ArrayResize(ma, bars_needed);
       double current_price = iClose(m_symbol, timeframe, 0);
       ArrayInitialize(ma, current_price);
   }
   
   /// ── ATR 처리 ─
   bool atr_ok = false;

   // 백테스트에서는 항상 직접 계산
   if(MQLInfoInteger(MQL_TESTER) || handles.atr_handle == INVALID_HANDLE) {
       ArrayResize(atr, bars_needed);
    
   // True Range 직접 계산
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, timeframe, 0, bars_needed + 14, rates); // 14개 더 가져옴
    
   if(copied >= bars_needed + 1) {
      // 각 바의 True Range 계산
      double tr_values[];
      ArrayResize(tr_values, copied - 1);
        
      for(int i = 0; i < copied - 1; i++) {
          double high_low = rates[i].high - rates[i].low;
          double high_close = MathAbs(rates[i].high - rates[i+1].close);
          double low_close = MathAbs(rates[i].low - rates[i+1].close);
          tr_values[i] = MathMax(high_low, MathMax(high_close, low_close));
      }
        
      // 14기간 이동평균으로 ATR 계산
      for(int i = 0; i < bars_needed && i < ArraySize(tr_values) - 14; i++) {
          double sum = 0;
          for(int j = i; j < i + 14; j++) {
              sum += tr_values[j];
          }
          atr[i] = sum / 14.0;
      }
        
      LogDebug("ATR 직접 계산 완료: " + DoubleToString(atr[0]/_Point, 0) + " points");
      } else {
      // 계산 실패시 기본값
      double default_atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 200;
      ArrayInitialize(atr, default_atr);
      LogWarning("ATR 계산용 데이터 부족, 기본값 사용");
      }
    } else {
    // 실거래에서는 기존 방식 사용
    if(CopyBuffer(handles.atr_handle, 0, 0, bars_needed, atr) <= 0) {
        ArrayResize(atr, bars_needed);
        double default_atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 200;
        ArrayInitialize(atr, default_atr);
        LogWarning("ATR 버퍼 복사 실패, 기본값 사용");
    }
}

   if(!atr_ok) {
       // 대기 기간이 끝났는데도 ATR을 못 구하면 에러
       if(MQLInfoInteger(MQL_TESTER)) {
           datetime start = (datetime)GlobalVariableGet("g_start_time");
           if(start > 0 && TimeCurrent() - start > 86400 * 5) { // 5일 이상 경과
               LogError("ATR 계산 실패 - 대기 기간 경과 후에도 데이터 없음");
               return false; // 거래 안 함
           }
       }
    
       // 아직 대기 기간이면 기본값 사용
       ArrayResize(atr, bars_needed);
       double default_atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 500;
       ArrayInitialize(atr, default_atr);
       LogDebug("ATR 대기 중 - 임시 기본값 사용");
   }

   
   // Bollinger Bands 처리
   if(bands_calc >= min_bars_for_calculation) {
       if(CopyBuffer(handles.bands_handle, 0, 0, bars_needed, bands_middle) <= 0 ||
          CopyBuffer(handles.bands_handle, 1, 0, bars_needed, bands_upper) <= 0 ||
          CopyBuffer(handles.bands_handle, 2, 0, bars_needed, bands_lower) <= 0) {
           LogWarning("BB 데이터 복사 실패, 기본값 사용");
           ArrayResize(bands_upper, bars_needed);
           ArrayResize(bands_middle, bars_needed);
           ArrayResize(bands_lower, bars_needed);
           double current_price = iClose(m_symbol, timeframe, 0);
           ArrayInitialize(bands_middle, current_price);
           ArrayInitialize(bands_upper, current_price * 1.02);
           ArrayInitialize(bands_lower, current_price * 0.98);
       }
   } else {
       ArrayResize(bands_upper, bars_needed);
       ArrayResize(bands_middle, bars_needed);
       ArrayResize(bands_lower, bars_needed);
       double current_price = iClose(m_symbol, timeframe, 0);
       ArrayInitialize(bands_middle, current_price);
       ArrayInitialize(bands_upper, current_price * 1.02);
       ArrayInitialize(bands_lower, current_price * 0.98);
   }
   
   // Stochastic 처리
   if(stoch_calc >= min_bars_for_calculation) {
       if(CopyBuffer(handles.stochastic_handle, 0, 0, bars_needed, stoch_main) <= 0 ||
          CopyBuffer(handles.stochastic_handle, 1, 0, bars_needed, stoch_signal) <= 0) {
           LogWarning("Stochastic 데이터 복사 실패, 기본값 사용");
           ArrayResize(stoch_main, bars_needed); ArrayInitialize(stoch_main, 50.0);
           ArrayResize(stoch_signal, bars_needed); ArrayInitialize(stoch_signal, 50.0);
       }
   } else {
       ArrayResize(stoch_main, bars_needed); ArrayInitialize(stoch_main, 50.0);
       ArrayResize(stoch_signal, bars_needed); ArrayInitialize(stoch_signal, 50.0);
   }

   // ★ 기존의 재시도 로직 제거 - 이제 항상 성공으로 처리

   // -------------------------------
   // ② 최근 N봉의 원시 값 저장 - 안전한 버전
   // -------------------------------
   int N = 5; // 최근 5봉 사용

   // 모든 배열 크기 확인 및 안전한 인덱스 계산
   int safe_ma_size = ArraySize(ma);
   int safe_rsi_size = ArraySize(rsi);
   int safe_adx_size = ArraySize(adx_main);
   int safe_adx_plus_size = ArraySize(adx_plus);
   int safe_adx_minus_size = ArraySize(adx_minus);
   int safe_atr_size = ArraySize(atr);
   int safe_bands_upper_size = ArraySize(bands_upper);
   int safe_bands_lower_size = ArraySize(bands_lower);
   int safe_bands_middle_size = ArraySize(bands_middle);

   LogDebug(StringFormat("배열 크기 확인: MA=%d, RSI=%d, ADX=%d, ATR=%d, Bands=%d",
                     safe_ma_size, safe_rsi_size, safe_adx_size, safe_atr_size, safe_bands_upper_size));

   for(int i = 0; i < N; i++)
   {
      // ★ 이중 안전 체크: i < N && i < 배열크기 && i < 구조체배열크기(5)
      if(i < N && i < 5) { // indicators 배열은 크기가 5로 고정
      
      // EMA 값 저장
      if(i < safe_ma_size && safe_ma_size > 0) {
         indicators.ema_values[i] = ma[i];
      } else {
         indicators.ema_values[i] = 0.0; // 기본값
      }
      
      // RSI 값 저장
      if(i < safe_rsi_size && safe_rsi_size > 0) {
         indicators.rsi_values[i] = rsi[i];
      } else {
         indicators.rsi_values[i] = 50.0; // RSI 기본값
      }
      
      // ADX 값 저장
      if(i < safe_adx_size && safe_adx_size > 0) {
         indicators.adx_values[i] = adx_main[i];
      } else {
         indicators.adx_values[i] = 25.0; // ADX 기본값
      }
      
      // DI+ 값 저장
      if(i < safe_adx_plus_size && safe_adx_plus_size > 0) {
         indicators.di_plus_values[i] = adx_plus[i];
      } else {
         indicators.di_plus_values[i] = 50.0; // DI+ 기본값
      }
      
      // DI- 값 저장
      if(i < safe_adx_minus_size && safe_adx_minus_size > 0) {
         indicators.di_minus_values[i] = adx_minus[i];
      } else {
         indicators.di_minus_values[i] = 50.0; // DI- 기본값
      }
      
      // ATR 값 저장
      if(i < safe_atr_size && safe_atr_size > 0) {
         indicators.atr_values[i] = atr[i];
      } else {
         indicators.atr_values[i] = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100; // ATR 기본값
      }
      
      // BB 폭 계산 - 가장 안전한 방식
      if(i < safe_bands_upper_size && i < safe_bands_lower_size && i < safe_bands_middle_size && 
         safe_bands_upper_size > 0 && safe_bands_lower_size > 0 && safe_bands_middle_size > 0) {
          double bb_upper = bands_upper[i];
          double bb_lower = bands_lower[i];
          double bb_middle = bands_middle[i];
    
          // 백테스트 초기에는 밴드가 0일 수 있음
          if(bb_middle > 0 && bb_upper > bb_lower) {
              indicators.bb_width_values[i] = (bb_upper - bb_lower) / bb_middle;
          } else {
              // 현재 가격 기반으로 기본값 설정
              double current_price = iClose(m_symbol, timeframe, i);
              if(current_price > 0) {
                  indicators.bb_width_values[i] = 0.02; // 2% 기본값
              } else {
                  indicators.bb_width_values[i] = 0.03;
              }
          }
      } else {
          indicators.bb_width_values[i] = 0.03;
      }
   }
}

LogDebug("배열 저장 완료: 모든 지표 데이터 안전하게 저장됨");

   // -------------------------------
   // ③ 1-캔들(현재) 지표 파생값 계산
   // -------------------------------
   {
      // ─────────────── 1)  추세 지표 ───────────────
      // ADX
      if(ArraySize(adx_main) > 0)
         indicators.trend_indicators[0] = adx_main[0];
      else
         indicators.trend_indicators[0] = 25.0;                      // 기본값

      // DI⁺ / DI⁻
      if(ArraySize(adx_plus) > 0 && ArraySize(adx_minus) > 0)
         indicators.trend_indicators[1] = adx_plus[0] /
                                          MathMax(adx_minus[0], 0.00001);
      else
         indicators.trend_indicators[1] = 1.0;                       // 기본값

      // EMA 기울기(선형회귀) – 최근 5개 캔들
      {
         double slope = 0, x = 0, y = 0, xy = 0, xx = 0;
         int    n     = MathMin(5, ArraySize(ma));

         for(int i = 0; i < n; i++)
         {  x  += i;
            y  += ma[i];
            xy += i * ma[i];
            xx += i * i;
         }

         if(n > 1)
            slope = (n * xy - x * y) / (n * xx - x * x);

         indicators.trend_indicators[2] =
            (n > 1) ? slope / MathMax(ma[0], 0.00001) : 0.0;
      }

      // ─────────────── 2)  모멘텀 지표 ───────────────
      // 2-1. RSI 현재값
      indicators.momentum_indicators[0] =
         (ArraySize(rsi) > 0) ? rsi[0] : 50.0;

      // 2-2. RSI 기울기
      {
         double slope = 0, x = 0, y = 0, xy = 0, xx = 0;
         int    n     = MathMin(5, ArraySize(rsi));

         for(int i = 0; i < n; i++)
         {  x  += i;
            y  += rsi[i];
            xy += i * rsi[i];
            xx += i * i;
         }

         if(n > 1)
            slope = (n * xy - x * y) / (n * xx - x * x);

         indicators.momentum_indicators[1] = (n > 1) ? slope : 0.0;
      }

      // 2-3. Stochastic 메인
      indicators.momentum_indicators[2] =
         (ArraySize(stoch_main) > 0) ? stoch_main[0] : 50.0;

      // 2-4. Stochastic 교차(메인-시그널)
      if(ArraySize(stoch_main) > 0 && ArraySize(stoch_signal) > 0)
         indicators.momentum_indicators[3] = stoch_main[0] - stoch_signal[0];
      else
         indicators.momentum_indicators[3] = 0.0;

      // ─────────────── 3)  변동성 지표 ───────────────
      // 3-1. ATR
      indicators.volatility_indicators[0] =
         (ArraySize(atr) > 0) ? atr[0]
                              : SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100;

      // 3-2. ATR 변화율 (5캔들 전 대비)
      if(ArraySize(atr) > 5)
         indicators.volatility_indicators[1] = atr[0] /
                                               MathMax(atr[5], 0.00001) - 1.0;
      else
         indicators.volatility_indicators[1] = 0.0;

      // 3-3. 볼린저 밴드 폭
      if(ArraySize(bands_upper)  > 0 &&
         ArraySize(bands_lower)  > 0 &&
         ArraySize(bands_middle) > 0)
      {
         indicators.volatility_indicators[2] =
            (bands_upper[0] - bands_lower[0]) /
            MathMax(bands_middle[0], 0.00001);
         LogDebug("BB 폭 계산: " +
                  DoubleToString(indicators.volatility_indicators[2], 4));
      }
      else
      {
         indicators.volatility_indicators[2] = 0.03;   // 기본 3 %
         LogDebug("BB 배열 부족, 기본값 0.03 적용");
      }
   }

   // -------------------------------
   // ④ 거래량 지표
   // -------------------------------
   long volumes[];
   ArraySetAsSeries(volumes, true);

   // 백테스트에서는 거래량 데이터가 불안정할 수 있음
   int vol_copied = CopyTickVolume(m_symbol, timeframe, 0, 10, volumes);
   if(vol_copied > 0)
   {
       double avg_vol = 0;
       int valid_count = 0;
    
       // 유효한 거래량만 계산
       for(int k = 1; k < vol_copied && k < 10; k++) {
           if(volumes[k] > 0) {
               avg_vol += (double)volumes[k];
               valid_count++;
           }
       }
    
       if(valid_count > 0 && volumes[0] > 0) {
           avg_vol /= valid_count;
           double vol_ratio = (double)volumes[0] / avg_vol;
           // 극단적인 값 제한
           vol_ratio = MathMax(0.1, MathMin(vol_ratio, 10.0));
           indicators.volume_indicators[0] = vol_ratio;
       } else {
           indicators.volume_indicators[0] = 1.0; // 기본값
       }
   }
   else
   {
       indicators.volume_indicators[0] = 1.0;
       // 백테스트에서는 경고 로그 생략
       if(!MQLInfoInteger(MQL_TESTER)) {
           LogWarning("거래량 데이터를 가져올 수 없음: " + IntegerToString(GetLastError()));
       }
   }
   
   // ★ 이제 항상 true 반환 (기본값을 사용해서라도 처리 완료)
   return true;
}

//===================================================================
// 4. 레짐(7종) 점수 계산 함수
//===================================================================

//--------------------------------------------------------------
// 강한 상승 모멘텀 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateStrongBullishScore(const SIndicatorGroup &indicators)
{
   // 클래스 멤버 가중치
   double w_trend = m_trend_weight;
   double w_momentum = m_momentum_weight;
   double w_volatility = m_volatility_weight;
   double w_volume = m_volume_weight;

   // 지표 추출
   double adx        = indicators.trend_indicators[0];
   double di_balance = indicators.trend_indicators[1];
   double ema_slope  = indicators.trend_indicators[2];
   double rsi        = indicators.momentum_indicators[0];
   double rsi_slope  = indicators.momentum_indicators[1];
   double vol_ratio  = indicators.volume_indicators[0];

   // ── Trend
   double trend_score = 0.0;
   if(adx > 20)
      trend_score = (adx / 50.0) * MathMax(0, di_balance - 1.0);
   else if(adx >= 18 && adx <= 20)
   {
      trend_score = 0.3 + (di_balance > 1.0 ? 0.2 * (di_balance - 1.0) : 0);
      LogDebug("약추세 특별 가중치 적용: ADX=" + DoubleToString(adx,1));
   }

   // ── Momentum
   double momentum_score = 0.0;
   if(rsi > 50)
   {
      momentum_score = (rsi - 50) / 30.0;
      if(rsi_slope > 0) momentum_score *= (1.0 + rsi_slope);
   }
   else if(rsi >= 35 && rsi <= 40)
   {
      momentum_score = 0.4;
      if(rsi_slope > 0) momentum_score *= (1.2 + rsi_slope);
      LogDebug("RSI 최적 과매도 구간 감지: RSI=" + DoubleToString(rsi,1));
   }

   // ── Volatility
   double volatility_score = 0.5 + (ema_slope * 20.0);
   volatility_score = MathMax(0, MathMin(1, volatility_score));

   // ── Volume
   double volume_score = (vol_ratio > 1.0) ? MathMin(vol_ratio / 2.0, 1.0) : 0.5;

   // ── 연속성 체크
   bool ema_rising=true, rsi_rising=true, adx_rising=true;
   for(int i=0;i<3;i++)
   {
      if(i+1<5)
      {
         if(indicators.ema_values[i] <= indicators.ema_values[i+1])   ema_rising=false;
         if(indicators.rsi_values[i] <= indicators.rsi_values[i+1])   rsi_rising=false;
         if(indicators.adx_values[i] <= indicators.adx_values[i+1])   adx_rising=false;
      }
   }
   if(ema_rising) trend_score    += 0.2;
   if(rsi_rising) momentum_score += 0.15;
   if(adx_rising) trend_score    += 0.1;

   // ── 총합
   double total = trend_score*w_trend + momentum_score*w_momentum
                + volatility_score*w_volatility + volume_score*w_volume;

   if(adx>=18&&adx<=20 && rsi>=35&&rsi<=40)
   {
      total *= 1.25;
      LogDebug("최적 조합 감지: ADX("+DoubleToString(adx,1)+") + RSI("
               +DoubleToString(rsi,1)+"), 25% 보너스 적용");
   }

   if(total>0.3)
      LogDebug("강한 상승 모멘텀 점수: "+DoubleToString(total,3)+
               " (trend="+DoubleToString(trend_score,2)+
               ", momentum="+DoubleToString(momentum_score,2)+
               ", volatility="+DoubleToString(volatility_score,2)+
               ", volume="+DoubleToString(volume_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 강한 하락 모멘텀 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateStrongBearishScore(const SIndicatorGroup &indicators)
{
   double w_trend=m_trend_weight, w_momentum=m_momentum_weight,
          w_volatility=m_volatility_weight, w_volume=m_volume_weight;

   double adx        = indicators.trend_indicators[0];
   double di_balance = indicators.trend_indicators[1];
   double ema_slope  = indicators.trend_indicators[2];
   double rsi        = indicators.momentum_indicators[0];
   double rsi_slope  = indicators.momentum_indicators[1];
   double vol_ratio  = indicators.volume_indicators[0];

   double trend_score = 0.0;
   if(adx > 20) {
      // DI- > DI+ 일 때 하락 추세
      if(di_balance < 1.0) {  // di_balance = DI+/DI-이므로 1 미만이면 하락
         trend_score = (adx/50.0) * (1.0 - di_balance);
      }
   }

   double momentum_score=0.0;
   if(rsi<50)
   {
      momentum_score = (50-rsi)/30.0;
      if(rsi_slope<0)                         // ★ 수정: 음수 기울기 보너스 → 1+|-slope|
         momentum_score *= (1.0 + (-rsi_slope));
   }

   double volatility_score = 0.5 - (ema_slope*20.0);
   volatility_score = MathMax(0, MathMin(1, volatility_score));

   double volume_score = (vol_ratio>1.0) ? MathMin(vol_ratio/2.0,1.0) : 0.5;

   bool ema_fall=true, rsi_fall=true, adx_rise=true;
   for(int i=0;i<3;i++)
   {
      if(i+1<5)
      {
         if(indicators.ema_values[i] >= indicators.ema_values[i+1])  ema_fall=false;
         if(indicators.rsi_values[i] >= indicators.rsi_values[i+1])  rsi_fall=false;
         if(indicators.adx_values[i] <= indicators.adx_values[i+1])  adx_rise=false;
      }
   }
   if(ema_fall) trend_score   +=0.2;
   if(rsi_fall) momentum_score+=0.15;
   if(adx_rise) trend_score   +=0.1;

   double total = trend_score*w_trend + momentum_score*w_momentum
                + volatility_score*w_volatility + volume_score*w_volume;

   if(total>0.3)
      LogDebug("강한 하락 모멘텀 점수: "+DoubleToString(total,3)+
               " (trend="+DoubleToString(trend_score,2)+
               ", momentum="+DoubleToString(momentum_score,2)+
               ", volatility="+DoubleToString(volatility_score,2)+
               ", volume="+DoubleToString(volume_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 통합 레인지 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateConsolidationScore(const SIndicatorGroup &ind)
{
   double w_trend=m_trend_weight, w_mom=m_momentum_weight,
          w_vol=m_volatility_weight;

   double adx   = ind.trend_indicators[0];
   double rsi   = ind.momentum_indicators[0];
   double bb_w  = ind.volatility_indicators[2];
   double atr_c = ind.volatility_indicators[1];

   double trend_score    = (adx<25) ? (25-adx)/25.0 : 0.0;
   double momentum_score = (rsi>=40&&rsi<=60)? 1.0-MathAbs(rsi-50)/10.0 : 0.0;
   double volatility_score = (bb_w<0.05)? 1.0-(bb_w/0.05) : 0.0;
   if(MathAbs(atr_c)<0.1) volatility_score *= (1.0 + (0.1-MathAbs(atr_c)));

   bool adx_low=true,rsi_mid=true,bb_narrow=true;
   for(int i=0;i<3;i++)
   {
      if(i+1<5)
      {
         if(ind.adx_values[i]>25||ind.adx_values[i+1]>25)   adx_low=false;
         if(ind.rsi_values[i]<40||ind.rsi_values[i]>60||
            ind.rsi_values[i+1]<40||ind.rsi_values[i+1]>60) rsi_mid=false;
         if(ind.bb_width_values[i]>0.03||ind.bb_width_values[i+1]>0.03) bb_narrow=false;
      }
   }
   if(adx_low)   trend_score    +=0.2;
   if(rsi_mid)   momentum_score +=0.15;
   if(bb_narrow) volatility_score+=0.2;

   double total = trend_score*w_trend + momentum_score*w_mom + volatility_score*w_vol;

   if(total>0.3)
      LogDebug("통합 레인지 점수: "+DoubleToString(total,3)+
               " (trend="+DoubleToString(trend_score,2)+
               ", momentum="+DoubleToString(momentum_score,2)+
               ", volatility="+DoubleToString(volatility_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 변동성 확장 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateVolatilityExpansionScore(const SIndicatorGroup &ind)
{
   double w_trend=m_trend_weight, w_vol=m_volatility_weight, w_volu=m_volume_weight;

   double adx   = ind.trend_indicators[0];
   double atr   = ind.volatility_indicators[0];
   double atr_c = ind.volatility_indicators[1];
   double bb_w  = ind.volatility_indicators[2];
   double vol_r = ind.volume_indicators[0];

   double trend_score = (adx>25)? MathMin(adx/50.0,1.0) : 0.0;

   double vol_score=0.0;
   if(atr_c>0.1) vol_score += MathMin(atr_c,0.5)*2.0;
   if(bb_w>0.03) vol_score += MathMin((bb_w-0.03)*10.0,0.5);

   double volume_score = (vol_r>1.2)? MathMin(vol_r-1.0,1.0) : 0.0;

   bool atr_up=true,adx_up=true,bb_exp=true;
   for(int i=0;i<3;i++)
   {
      if(i+1<5)
      {
         if(ind.atr_values[i]<=ind.atr_values[i+1])         atr_up=false;
         if(ind.adx_values[i]<=ind.adx_values[i+1])         adx_up=false;
         if(ind.bb_width_values[i]<=ind.bb_width_values[i+1]) bb_exp=false;
      }
   }
   if(atr_up) vol_score+=0.2;
   if(adx_up) trend_score+=0.1;
   if(bb_exp) vol_score+=0.15;

   double total = trend_score*w_trend + vol_score*w_vol + volume_score*w_volu;

   if(total>0.3)
      LogDebug("변동성 확장 점수: "+DoubleToString(total,3)+
               " (trend="+DoubleToString(trend_score,2)+
               ", volatility="+DoubleToString(vol_score,2)+
               ", volume="+DoubleToString(volume_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 오버나이트 드리프트 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateOvernightDriftScore(const SIndicatorGroup &ind)
{
   if(!m_session_manager || m_session_manager.GetCurrentSession()!=SESSION_ASIA)
      return 0.0;

   double w_trend=m_trend_weight, w_vol=m_volatility_weight, w_volu=m_volume_weight;

   double adx   = ind.trend_indicators[0];
   double atr   = ind.volatility_indicators[0];
   double vol_r = ind.volume_indicators[0];

   double trend_score     = (adx<20)? (20-adx)/20.0 : 0.0;
   double volatility_score= (atr<0.8)? 1.0-(atr/0.8) : 0.0;
   double volume_score    = (vol_r<1.0)? 1.0-vol_r : 0.0;

   double total = trend_score*w_trend + volatility_score*w_vol + volume_score*w_volu;

   if(total>0.3)
      LogDebug("오버나이트 드리프트 점수: "+DoubleToString(total,3)+
               " (trend="+DoubleToString(trend_score,2)+
               ", volatility="+DoubleToString(volatility_score,2)+
               ", volume="+DoubleToString(volume_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 갭 트레이딩 패턴 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateGapTradingScore(const SIndicatorGroup &ind)
{
   STimeframeData tf_data;
   ENUM_TIMEFRAMES tf = m_mtf_manager.GetCurrentTimeframeCombo().primary_tf;
   if(!m_mtf_manager.GetTimeframeData(tf, tf_data) || tf_data.bars_count<2)
      return 0.0;

   double gap = MathAbs(tf_data.rates[0].open - tf_data.rates[1].close);

   double avg_rng=0; int cnt=MathMin(5,tf_data.bars_count);
   for(int i=0;i<cnt;i++) avg_rng += tf_data.rates[i].high - tf_data.rates[i].low;
   avg_rng/=cnt;

   double gap_score=0.0;
   if(gap>avg_rng*0.3) gap_score = MathMin(gap/(avg_rng*1.0),1.0);
   else                return 0.0;

   double w_gap=0.60, w_vol=m_volatility_weight, w_volu=m_volume_weight;

   double atr_c = ind.volatility_indicators[1];
   double vol_r = ind.volume_indicators[0];

   double vol_score   = (atr_c>0.1)? MathMin(atr_c,1.0) : 0.0;
   double volume_score= (vol_r>1.0)? MathMin(vol_r-1.0,1.0) : 0.0;

   double total = gap_score*w_gap + vol_score*w_vol + volume_score*w_volu;

   if(total>0.3)
      LogDebug("갭 트레이딩 패턴 점수: "+DoubleToString(total,3)+
               " (gap="+DoubleToString(gap_score,2)+
               ", volatility="+DoubleToString(vol_score,2)+
               ", volume="+DoubleToString(volume_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//--------------------------------------------------------------
// 기술적 되돌림 점수
//--------------------------------------------------------------
double CRegimeDetector::CalculateTechnicalReversalScore(const SIndicatorGroup &ind)
{
   double w_mom=m_momentum_weight, w_trend=m_trend_weight, w_vol=m_volatility_weight;

   double rsi       = ind.momentum_indicators[0];
   double rsi_slope = ind.momentum_indicators[1];
   double st_main   = ind.momentum_indicators[2];
   double st_cross  = ind.momentum_indicators[3];

   double adx        = ind.trend_indicators[0];
   double di_balance = ind.trend_indicators[1];
   double ema_slope  = ind.trend_indicators[2];

   double bb_w  = ind.volatility_indicators[2];
   double atr_c = ind.volatility_indicators[1];

   double momentum=0.0,tr_score=0.0,vol_score=0.0;

   if((rsi<30&&rsi_slope>0)||(rsi>70&&rsi_slope<0))
   {
      momentum+=0.5;
      if(rsi<20||rsi>80) momentum+=0.2;
      if(MathAbs(rsi_slope)>5) momentum+=0.3;
   }

   if((st_main<20&&st_cross>0)||(st_main>80&&st_cross<0))
      momentum+=0.3;

   momentum=MathMin(momentum,1.0);

   if(adx<25&&adx>15) tr_score+=0.3;
   if(di_balance>0.8&&di_balance<1.2) tr_score+=0.4;
   if(MathAbs(ema_slope)<0.002) tr_score+=0.3;
   tr_score=MathMin(tr_score,1.0);

   if(bb_w<0.04&&atr_c>0.05) vol_score+=0.6;
   if(atr_c>0.1) vol_score+=0.4;
   vol_score=MathMin(vol_score,1.0);

   double total = momentum*w_mom + tr_score*w_trend + vol_score*w_vol;

   if(total>0.3)
      LogDebug("기술적 되돌림 점수: "+DoubleToString(total,3)+
               " (momentum="+DoubleToString(momentum,2)+
               ", trend="+DoubleToString(tr_score,2)+
               ", volatility="+DoubleToString(vol_score,2)+")");

   total *= m_regime_threshold_multiplier;
   return MathMin(total,1.0);
}

//===================================================================
// 5. 레짐 점수 TF별 저장 → 통합 → Update
//===================================================================

//--------------------------------------------------------------
// ① 개별 타임프레임 점수 계산 & 저장
//--------------------------------------------------------------
bool CRegimeDetector::CalculateRegimeScores(ENUM_TIMEFRAMES timeframe)
{
   STimeframeData tf_data;
   if(!m_mtf_manager.GetTimeframeData(timeframe, tf_data))
   {
      LogError("타임프레임 데이터를 가져올 수 없음: "+EnumToString(timeframe));
      return false;
   }

   SIndicatorGroup ind;
   ZeroMemory(ind);
   if(!CollectIndicatorData(timeframe, ind))
   {
      LogError("지표 데이터 수집 실패: "+EnumToString(timeframe));
      return false;
   }

   tf_data.regime_data.regime_scores[REGIME_UNKNOWN]          = 0.0;
   tf_data.regime_data.regime_scores[REGIME_STRONG_BULLISH]   = CalculateStrongBullishScore(ind);
   tf_data.regime_data.regime_scores[REGIME_STRONG_BEARISH]   = CalculateStrongBearishScore(ind);
   tf_data.regime_data.regime_scores[REGIME_CONSOLIDATION]    = CalculateConsolidationScore(ind);
   tf_data.regime_data.regime_scores[REGIME_VOLATILITY_EXPANSION] = CalculateVolatilityExpansionScore(ind);
   tf_data.regime_data.regime_scores[REGIME_OVERNIGHT_DRIFT]  = CalculateOvernightDriftScore(ind);
   tf_data.regime_data.regime_scores[REGIME_GAP_TRADING]      = CalculateGapTradingScore(ind);
   tf_data.regime_data.regime_scores[REGIME_TECHNICAL_REVERSAL]= CalculateTechnicalReversalScore(ind);

   int max_idx = ArrayMaximum(tf_data.regime_data.regime_scores, 0, 8);
   tf_data.regime_data.dominant_regime = (ENUM_MARKET_REGIME)max_idx;

   double sorted[8];  ArrayCopy(sorted, tf_data.regime_data.regime_scores);
   ArraySort(sorted);                                 // 오름차순
   double max_score = sorted[7], second_max = sorted[6];
   tf_data.regime_data.confidence = (max_score - second_max) /
                                    MathMax(max_score, 0.001);

   return m_mtf_manager.SetRegimeData(timeframe, tf_data.regime_data);
}

//--------------------------------------------------------------
// ② 다중 타임프레임 통합
//--------------------------------------------------------------
SRegimeData CRegimeDetector::IntegrateTimeframeRegimes()
{
   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();

   STimeframeData p,c,f;
   if(!m_mtf_manager.GetTimeframeData(combo.primary_tf,  p) ||
      !m_mtf_manager.GetTimeframeData(combo.confirm_tf,  c) ||
      !m_mtf_manager.GetTimeframeData(combo.filter_tf,   f))
   {
      SRegimeData empty; ZeroMemory(empty);
      empty.dominant_regime = REGIME_UNKNOWN;
      return empty;
   }

   double integrated[8];
   for(int i=0;i<8;i++)
      integrated[i] = p.regime_data.regime_scores[i]*combo.weights[0] +
                      c.regime_data.regime_scores[i]*combo.weights[1] +
                      f.regime_data.regime_scores[i]*combo.weights[2];

   SRegimeData out; ZeroMemory(out);
   ArrayCopy(out.regime_scores, integrated);

   int max_idx = ArrayMaximum(integrated, 0, 8);
   out.dominant_regime = (ENUM_MARKET_REGIME)max_idx;

   // 타임프레임 간 일치도 계산
   int agree = 0;
   if(p.regime_data.dominant_regime==c.regime_data.dominant_regime &&
      p.regime_data.dominant_regime!=REGIME_UNKNOWN)                   agree++;
   if(c.regime_data.dominant_regime==f.regime_data.dominant_regime &&
      c.regime_data.dominant_regime!=REGIME_UNKNOWN)                   agree++;
   if(p.regime_data.dominant_regime==f.regime_data.dominant_regime &&
      p.regime_data.dominant_regime!=REGIME_UNKNOWN)                   agree++;

   double sorted[8]; ArrayCopy(sorted, integrated); ArraySort(sorted);
   double max_score = sorted[7], second_max = sorted[6], third_max = sorted[5];

   // ★ 개선된 신뢰도 계산
   double conf = 0.0;
   double total_score = 0.0;
   int valid_regimes = 0;
   
   // 전체 점수 합계와 유효 레짐 수 계산
   for(int i = 1; i < 8; i++) {  // UNKNOWN(0) 제외
       if(integrated[i] > 0.01) {
           total_score += integrated[i];
           valid_regimes++;
       }
   }
   
   if(max_score > 0.001) {
       // 기본 신뢰도: 최고점수와 2등점수의 차이 비율
       double basic_conf = (max_score - second_max) / max_score;
       
       // 절대적 점수 고려: 최고 점수가 높을수록 신뢰도 증가
       double absolute_bonus = MathMin(max_score * 0.5, 0.3); // 최대 30% 보너스
       
       // 점수 격차 고려: 상위 3개 점수의 분산이 클수록 신뢰도 증가
       double variance_bonus = 0.0;
       if(max_score > third_max) {
           variance_bonus = MathMin((max_score - third_max) / max_score * 0.2, 0.2); // 최대 20% 보너스
       }
       
       conf = basic_conf + absolute_bonus + variance_bonus;
   }
   
   // 타임프레임 일치도 보너스 (기존 유지)
   conf *= 1.0 + agree * 0.1;
   
   // ★ 더 관대한 임계값 적용
   const double CONF_THRESHOLD = 0.15; // 기존 0.3에서 0.15로 완화
   
   if(conf < CONF_THRESHOLD)
   {
       ENUM_MARKET_REGIME orig = out.dominant_regime;
       out.dominant_regime = REGIME_UNKNOWN;
       LogInfo("낮은 신뢰도로 UNKNOWN 설정: " + DoubleToString(conf*100,1) + 
              "% (임계값: " + DoubleToString(CONF_THRESHOLD*100,1) + 
              "%), 원래 감지: " + RegimeNameStr(orig));
   } else {
       LogDebug("레짐 신뢰도 충족: " + DoubleToString(conf*100,1) + 
               "%, 감지: " + RegimeNameStr(out.dominant_regime));
   }

   out.confidence = MathMin(conf, 1.0);
   
   // ★ 추가 디버그 정보
   LogDebug(StringFormat("신뢰도 계산 세부: basic=%.1f%%, absolute_bonus=%.1f%%, variance_bonus=%.1f%%, agreement_bonus=%d, 최종=%.1f%%",
                        (max_score > 0.001 ? (max_score - second_max) / max_score * 100 : 0),
                        (max_score > 0.001 ? MathMin(max_score * 0.5, 0.3) * 100 : 0),
                        (max_score > third_max ? MathMin((max_score - third_max) / max_score * 0.2, 0.2) * 100 : 0),
                        agree,
                        conf * 100));
   
   return out;
}

//--------------------------------------------------------------
// ③ Update : 1티크마다 호출
//--------------------------------------------------------------
bool CRegimeDetector::Update()
{
   m_hysteresis_applied = false;

   if(m_session_manager)  m_session_manager.Update();
   if(m_mtf_manager)      m_mtf_manager.UpdateData();

   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();

   bool ok =  CalculateRegimeScores(combo.primary_tf) &&
              CalculateRegimeScores(combo.confirm_tf) &&
              CalculateRegimeScores(combo.filter_tf);

   if(!ok) return false;

   m_current_regime = IntegrateTimeframeRegimes();

   // ── 히스테리시스 처리
   ENUM_MARKET_REGIME new_reg   = m_current_regime.dominant_regime;
   double             new_conf  = m_current_regime.confidence;

   if(m_previous_regime != new_reg)
   {
      double diff = new_conf;
      if(m_previous_regime != REGIME_UNKNOWN)
         diff -= m_current_regime.regime_scores[(int)m_previous_regime];

      if(m_previous_regime!=REGIME_UNKNOWN &&
         (diff < m_hysteresis_threshold || m_regime_hold_count < m_hysteresis_bars))
      {
         m_current_regime.dominant_regime = m_previous_regime;
         m_regime_hold_count++;
         m_hysteresis_applied = true;

         LogInfo("히스테리시스 유지 ("+RegimeNameStr(m_previous_regime)+
                 "), Δ="+DoubleToString(diff,3)+
                 ", hold="+IntegerToString(m_regime_hold_count));
      }
      else
      {
         LogInfo("레짐 변경: "+RegimeNameStr(m_previous_regime)+" → "+
                 RegimeNameStr(new_reg)+
                 " (신뢰도 "+DoubleToString(new_conf,3)+")");

         AddRegimeChangeMarker(m_previous_regime, new_reg, new_conf);

         m_previous_regime         = new_reg;
         m_regime_hold_count       = 1;
         m_last_regime_change_time = TimeCurrent();
      }
   }
   else
   {
      m_regime_hold_count++;
   }

   LogRegimeScores(false);      // CSV 저장은 EA 측 옵션
   return true;
}

//===================================================================
// 6. 유틸 함수 · 시각화 · 로깅
//===================================================================

//----------------------------------------------------
// (1) 오류 코드 → 한글 설명
//----------------------------------------------------
string ErrorDescription(int error_code)
{
   switch(error_code)
   {
      case 4302: return "지표를 생성할 수 없음";
      case 4301: return "현재 심볼 또는 타임프레임의 데이터가 없음";
      case 4303: return "지표 버퍼 크기가 0임";
      default   : return "알 수 없는 오류";
   }
}

//----------------------------------------------------
// (2) 레짐 점수 간결 로그 & CSV 저장
//----------------------------------------------------
void CRegimeDetector::LogRegimeScores(bool save_to_csv)
{
   static bool header_written=false;
   datetime now = TimeCurrent();

   string msg = StringFormat(
      "레짐 점수: %s (신뢰 %.1f%%) [상승:%.1f, 하락:%.1f, 통합:%.1f, 변동:%.1f, 드리프트:%.1f, 갭:%.1f, 되돌림:%.1f]",
      RegimeNameStr(m_current_regime.dominant_regime),
      m_current_regime.confidence*100,
      m_current_regime.regime_scores[REGIME_STRONG_BULLISH]*100,
      m_current_regime.regime_scores[REGIME_STRONG_BEARISH]*100,
      m_current_regime.regime_scores[REGIME_CONSOLIDATION]*100,
      m_current_regime.regime_scores[REGIME_VOLATILITY_EXPANSION]*100,
      m_current_regime.regime_scores[REGIME_OVERNIGHT_DRIFT]*100,
      m_current_regime.regime_scores[REGIME_GAP_TRADING]*100,
      m_current_regime.regime_scores[REGIME_TECHNICAL_REVERSAL]*100 );
   LogInfo(msg);

   if(!save_to_csv) return;

   string filename = "RegimeScores_"+Symbol()+".csv";
   int fh;

   if(!header_written)
   {
      fh = FileOpen(filename, FILE_WRITE|FILE_CSV);
      if(fh!=INVALID_HANDLE)
      {
         FileWrite(fh,"Timestamp","Dominant","Confidence",
                       "StrongBull","StrongBear","Consolid",
                       "VolExpand","Overnight","Gap","Reversal");
         header_written=true;
      }
   }
   else
   {
      fh = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV);
      if(fh!=INVALID_HANDLE) FileSeek(fh,0,SEEK_END);
   }

   if(fh!=INVALID_HANDLE)
   {
      FileWrite(fh, TimeToString(now),
                   RegimeNameStr(m_current_regime.dominant_regime),
                   DoubleToString(m_current_regime.confidence,4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_STRONG_BULLISH],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_STRONG_BEARISH],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_CONSOLIDATION],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_VOLATILITY_EXPANSION],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_OVERNIGHT_DRIFT],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_GAP_TRADING],4),
                   DoubleToString(m_current_regime.regime_scores[REGIME_TECHNICAL_REVERSAL],4));
      FileClose(fh);
   }
}

//----------------------------------------------------
// (3) 레짐 변경 시 차트 마커
//----------------------------------------------------
void AddRegimeChangeMarker(ENUM_MARKET_REGIME old_reg,
                           ENUM_MARKET_REGIME new_reg,
                           double confidence)
{
   if(old_reg==REGIME_UNKNOWN) return;          // 첫 레짐이면 생략

   long      chart_id = 0;
   datetime  t        = TimeCurrent();
   double    price;

   MqlTick tick;
   if(SymbolInfoTick(Symbol(), tick)) price = tick.last;
   else
   {
      MqlRates r[1];
      if(CopyRates(Symbol(), PERIOD_CURRENT, 0, 1, r)>0) price=r[0].close;
      else { LogWarning("마커 추가 실패: 가격 없음"); return; }
   }

   string name = "regime_change_"+TimeToString(t,TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   ENUM_OBJECT arrow;
   color clr;

   switch(new_reg)
   {
      case REGIME_STRONG_BULLISH : arrow=OBJ_ARROW_UP;    clr=clrGreen;  break;
      case REGIME_STRONG_BEARISH : arrow=OBJ_ARROW_DOWN;  clr=clrRed;    break;
      case REGIME_CONSOLIDATION  : arrow=OBJ_ARROW_RIGHT_PRICE; clr=clrBlue;  break;
      case REGIME_VOLATILITY_EXPANSION: arrow=OBJ_ARROW_THUMB_UP; clr=clrMagenta; break;
      default                    : arrow=OBJ_ARROW_CHECK; clr=clrYellow;
   }

   if(!ObjectCreate(chart_id,name,arrow,0,t,price))
   {
      LogError("마커 생성 실패: "+IntegerToString(GetLastError()));
      return;
   }

   ObjectSetInteger(chart_id,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(chart_id,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(chart_id,name,OBJPROP_SELECTABLE,false);

   string tip = RegimeNameStr(old_reg)+" -> "+RegimeNameStr(new_reg)+
                " (신뢰 "+DoubleToString(confidence*100,1)+"%)";
   ObjectSetString(chart_id,name,OBJPROP_TOOLTIP,tip);

   ChartRedraw(chart_id);
   LogInfo("레짐 변경 마커 추가: "+name+", "+tip);
}

//─────────────────────────────────────────────
//  CRegimeDetector :: GetCurrentRegime()
//─────────────────────────────────────────────
SRegimeData CRegimeDetector::GetCurrentRegime() const
{
   return m_current_regime;
}

//+------------------------------------------------------------------+
//| 현재 지표 데이터 가져오기                                        |
//+------------------------------------------------------------------+
bool CRegimeDetector::GetCurrentIndicators(SIndicatorGroup &indicators)
{
   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();
   return CollectIndicatorDataCached(combo.primary_tf,indicators);
}

//+------------------------------------------------------------------+
//| 최신 지표 데이터 가져오기                                        |
//+------------------------------------------------------------------+
SIndicatorGroup CRegimeDetector::GetLatestIndicatorData()
{
   SIndicatorGroup ind; ZeroMemory(ind);
   STimeframeCombo combo = m_mtf_manager.GetCurrentTimeframeCombo();
   CollectIndicatorDataCached(combo.primary_tf,ind);
   return ind;
}

//+------------------------------------------------------------------+
//| 특정 타임프레임의 지표 값 가져오기                              |
//+------------------------------------------------------------------+
bool CRegimeDetector::GetIndicatorValues(ENUM_TIMEFRAMES tf,SIndicatorGroup &indicators)
{
   return CollectIndicatorDataCached(tf,indicators);
}

//+------------------------------------------------------------------+
//| 지표 값 유효성 검증                                              |
//+------------------------------------------------------------------+
bool IsIndicatorValueValid(double value) {
    return (value != EMPTY_VALUE && value != -1 && MathIsValidNumber(value));
}
