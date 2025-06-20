//+------------------------------------------------------------------+
//|                                           StrategySelector.mqh |
//|                                       NAS100 MTF Regime System   |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_SELECTOR_MQH__
#define __STRATEGY_SELECTOR_MQH__

#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include "../RegimeDetection/RegimeDetector.mqh"
#include "../RegimeDetection/RegimeDefinitions.mqh"
#include "../Utils/Logger.mqh"
#include "../Utils/SessionManager.mqh"
#include "../Trading/RiskManager.mqh"

class CRegimeDetector;

// 전략 유형 열거형
enum ENUM_STRATEGY_TYPE {
    STRATEGY_NONE = 0,               // 거래 없음
    STRATEGY_TREND_FOLLOWING,        // 추세 추종
    STRATEGY_MEAN_REVERSION,         // 평균 회귀
    STRATEGY_BREAKOUT,               // 돌파
    STRATEGY_RANGE_TRADING,          // 레인지 거래
    STRATEGY_SCALPING,               // 스캘핑
    STRATEGY_GAP_FADE,               // 갭 페이드
    STRATEGY_VOLATILITY_BREAKOUT     // 변동성 돌파
};

// 거래 방향 열거형
enum ENUM_TRADE_DIRECTION {
    TRADE_DIRECTION_NONE = 0,        // 거래 없음
    TRADE_DIRECTION_LONG,            // 매수만
    TRADE_DIRECTION_SHORT,           // 매도만
    TRADE_DIRECTION_BOTH             // 양방향
};

// 지표 파라미터 구조체
struct SIndicatorParams {
    int adx_period;                  // ADX 기간
    int rsi_period;                  // RSI 기간
    int ma_period;                   // 이동평균 기간
    int atr_period;                  // ATR 기간
    int bands_period;                // 볼린저 밴드 기간
    double bands_deviation;          // 볼린저 밴드 표준편차
    double adx_trend_threshold;      // ADX 추세 임계값
    double adx_strong_threshold;     // ADX 강한 추세 임계값
    double rsi_overbought;           // RSI 과매수 기준
    double rsi_oversold;             // RSI 과매도 기준
    double rsi_neutral_high;         // RSI 중립대 상단
    double rsi_neutral_low;          // RSI 중립대 하단
    double bb_width_narrow;          // 좁은 밴드 폭 기준
    double bb_width_wide;            // 넓은 밴드 폭 기준
};

// 전략 파라미터 구조체
struct SStrategyParams {
    ENUM_STRATEGY_TYPE strategy_type;    // 전략 유형
    ENUM_TRADE_DIRECTION trade_direction; // 거래 방향
    double entry_threshold;            // 진입 임계값
    double exit_threshold;             // 청산 임계값
    double sl_distance;                // 손절 거리 (ATR 배수)
    double tp_distance;                // 익절 거리 (ATR 배수)
    double trailing_stop;              // 트레일링 스탑 (ATR 배수)
    int max_positions;                 // 최대 포지션 수
    double min_confidence;             // 최소 신뢰도 요구사항
    bool use_time_filter;              // 시간 필터 사용 여부
    int trade_start_hour;              // 거래 시작 시간
    int trade_end_hour;                // 거래 종료 시간
    double risk_multiplier;            // 리스크 배수 (세션별 조정용)
};

// 진입 신호 구조체 (RiskManager 연계 강화)
struct SEntrySignal {
    bool has_signal;                   // 신호 존재 여부
    ENUM_ORDER_TYPE signal_type;       // 신호 유형 (BUY/SELL)
    double suggested_price;            // 제안 진입가
    double suggested_sl;               // 제안 손절가 (RiskManager 조정된)
    double suggested_tp;               // 제안 익절가 (RiskManager 조정된)
    double suggested_lot;              // RiskManager가 계산한 lot 크기
    double signal_strength;            // 신호 강도 (0-1)
    string signal_reason;              // 신호 이유
    datetime signal_time;              // 신호 발생 시간
    double calculated_risk;            // 계산된 리스크 금액
    double risk_reward_ratio;          // 리스크 대비 보상 비율
    bool risk_validated;               // 리스크 검증 통과 여부
    string risk_validation_message;    // 리스크 검증 메시지
};

// 세션별 전략 활성화 구조체
struct SSessionStrategy {
    bool asia_active;                  // 아시아 세션 활성화
    bool europe_active;                // 유럽 세션 활성화
    bool us_active;                    // 미국 세션 활성화
    double asia_multiplier;            // 아시아 세션 파라미터 배수
    double europe_multiplier;          // 유럽 세션 파라미터 배수
    double us_multiplier;              // 미국 세션 파라미터 배수
};

// 전략 성과 추적 구조체
struct SStrategyPerformance {
    int total_signals;                 // 총 신호 수
    int successful_signals;            // 성공한 신호 수
    double total_pnl;                  // 총 손익
    double win_rate;                   // 승률
    double avg_risk_reward;            // 평균 리스크 대비 보상
    datetime last_signal_time;         // 마지막 신호 시간
    double max_consecutive_loss;       // 최대 연속 손실
    int current_streak;                // 현재 연속 결과 (양수=승, 음수=패)
};

// 전략 선택기 클래스
class CStrategySelector {
private:
    // 핵심 의존성 (다른 클래스들과의 연계)
    CRegimeDetector* m_regime_detector;    // 레짐 감지기 포인터
    CSessionManager* m_session_manager;    // 세션 관리자 포인터
    CRiskManager* m_risk_manager;          // 리스크 관리자 포인터
    
    string m_symbol;                       // 거래 심볼
    double m_risk_usd;                     // EA에서 설정하는 리스크 금액 (USD)
    double m_risk_percent;                 // 리스크 비율 (%)

    // 지표 파라미터
    SIndicatorParams m_indicator_params;

    // 현재 전략 정보
    ENUM_STRATEGY_TYPE m_current_strategy;   // 현재 선택된 전략
    SStrategyParams m_current_params;        // 현재 전략 파라미터

    // 전략별 기본 파라미터
    SStrategyParams m_trend_params;          // 추세 추종 파라미터
    SStrategyParams m_reversion_params;      // 평균 회귀 파라미터
    SStrategyParams m_breakout_params;       // 돌파 파라미터
    SStrategyParams m_range_params;          // 레인지 파라미터
    SStrategyParams m_scalping_params;       // 스캘핑 파라미터
    SStrategyParams m_gap_params;            // 갭 페이드 파라미터
    SStrategyParams m_volatility_params;     // 변동성 돌파 파라미터

    // 세션별 전략 활성화 정보
    SSessionStrategy m_trend_sessions;       // 추세 추종 세션별 설정
    SSessionStrategy m_reversion_sessions;   // 평균 회귀 세션별 설정
    SSessionStrategy m_breakout_sessions;    // 돌파 세션별 설정
    SSessionStrategy m_range_sessions;       // 레인지 세션별 설정
    SSessionStrategy m_scalping_sessions;    // 스캘핑 세션별 설정
    SSessionStrategy m_gap_sessions;         // 갭 페이드 세션별 설정
    SSessionStrategy m_volatility_sessions;  // 변동성 돌파 세션별 설정

    // 전략 성과 추적
    SStrategyPerformance m_trend_performance;        // 추세 추종 성과
    SStrategyPerformance m_reversion_performance;    // 평균 회귀 성과
    SStrategyPerformance m_breakout_performance;     // 돌파 성과
    SStrategyPerformance m_range_performance;        // 레인지 성과
    SStrategyPerformance m_scalping_performance;     // 스캘핑 성과
    SStrategyPerformance m_gap_performance;          // 갭 페이드 성과
    SStrategyPerformance m_volatility_performance;   // 변동성 돌파 성과
    
    // RiskManager 연계 강화를 위한 추가 멤버
    bool m_use_dynamic_sizing;               // 동적 포지션 사이징 사용 여부
    double m_max_risk_per_signal;            // 신호당 최대 리스크
    double m_confidence_multiplier;          // 신뢰도 기반 사이즈 조정 배수
    bool m_validate_all_signals;             // 모든 신호 리스크 검증 여부

    // 신호 생성 및 검증 상태
    datetime m_last_signal_time;             // 마지막 신호 생성 시간
    int m_signal_cooldown_seconds;           // 신호 생성 쿨다운 (초)
    bool m_trading_enabled;                  // 거래 활성화 상태

    // 전략 선택 로직
    ENUM_STRATEGY_TYPE SelectStrategyByRegime(ENUM_MARKET_REGIME regime, double confidence);
    bool IsStrategyValidForSession(ENUM_STRATEGY_TYPE strategy, ESessionType session);
    void AdjustStrategyForSession(SStrategyParams &params, ESessionType session);

    // 신호 생성 로직 (RiskManager 완전 연계)
    SEntrySignal GenerateTrendSignal();
    SEntrySignal GenerateReversionSignal();
    SEntrySignal GenerateBreakoutSignal();
    SEntrySignal GenerateRangeSignal();
    SEntrySignal GenerateScalpingSignal();
    SEntrySignal GenerateGapSignal();
    SEntrySignal GenerateVolatilitySignal();

    // 세션별 신호 생성 로직
    SEntrySignal GenerateAsiaSessionSignal(ENUM_STRATEGY_TYPE strategy);
    SEntrySignal GenerateEuropeSessionSignal(ENUM_STRATEGY_TYPE strategy);
    SEntrySignal GenerateUSSessionSignal(ENUM_STRATEGY_TYPE strategy);

    // RiskManager 연계 핵심 메서드들
    bool ValidateSignalWithRiskManager(SEntrySignal &signal);
    bool CalculateOptimalPositionSize(SEntrySignal &signal);
    bool AdjustStopsWithRiskManager(SEntrySignal &signal);
    double CalculateRiskRewardRatio(const SEntrySignal &signal);

    // RegimeDetector로부터 지표 데이터 가져오기
    bool GetIndicatorDataFromRegime(SIndicatorGroup &indicators);
    bool GetCurrentMarketData(double &current_price, double &atr_value, SIndicatorGroup &indicators);
    bool ValidateIndicatorData(const SIndicatorGroup &indicators);
    void SetDefaultIndicatorData(SIndicatorGroup &indicators);
    bool GetSpecificTimeframeIndicators(ENUM_TIMEFRAMES tf, SIndicatorGroup &indicators);
    // 기술적 분석 헬퍼 함수
    bool IsRSIOversold(double rsi_value);
    bool IsRSIOverbought(double rsi_value);
    bool IsADXTrendStrong(double adx_value);
    bool IsBollingerBandNarrow(double bb_width);
    bool IsBollingerBandWide(double bb_width);
    bool IsVolumeHigh(double volume_ratio);

    // 시장 상태 분석
    bool IsMarketTrending(const SIndicatorGroup &indicators);
    bool IsMarketRanging(const SIndicatorGroup &indicators);
    bool IsMarketVolatile(const SIndicatorGroup &indicators);
    double GetMarketStrength(const SIndicatorGroup &indicators);

    // 기본 파라미터 초기화
    void InitializeDefaultParameters();
    void InitializeSessionSettings();
    void InitializePerformanceTracking();

    // 성과 추적 메서드들
    void UpdateStrategyPerformance(ENUM_STRATEGY_TYPE strategy, bool success, double pnl);
    bool GetStrategyPerformanceData(ENUM_STRATEGY_TYPE strategy, SStrategyPerformance &perf_out);
    void ResetPerformanceStats(ENUM_STRATEGY_TYPE strategy);

    // 헬퍼 함수
    string GetSessionNameStr(ESessionType session);
    double GetATRFromIndicators(const SIndicatorGroup &indicators);
    double GetCurrentPrice();
    bool IsSignalCooldownActive();
    void UpdateSignalCooldown();
    double GetStrategyMinConfidence(ENUM_STRATEGY_TYPE strategy);
    string GetRegimeNameForLogging(ENUM_MARKET_REGIME regime);

public:
    // 생성자 및 소멸자
    CStrategySelector(CRegimeDetector* regime_detector, CSessionManager* session_manager,
                      CRiskManager* risk_manager, string symbol, const SIndicatorParams &indicator_params);
    ~CStrategySelector();

    // 초기화
    bool Initialize();
    
    // === RiskManager 연계 핵심 인터페이스 ===
    void SetRiskAmount(double risk_usd) { m_risk_usd = risk_usd; }
    void SetRiskPercent(double risk_percent) { m_risk_percent = risk_percent; }
    void SetMaxRiskPerSignal(double max_risk) { m_max_risk_per_signal = max_risk; }
    void EnableDynamicSizing(bool enable) { m_use_dynamic_sizing = enable; }
    void SetConfidenceMultiplier(double multiplier) { m_confidence_multiplier = multiplier; }

    // 전략 선택 및 업데이트
    bool UpdateStrategy();
    ENUM_STRATEGY_TYPE GetCurrentStrategy() const { return m_current_strategy; }
    SStrategyParams GetCurrentParameters() const { return m_current_params; }

    // === 진입 신호 생성 (완전히 RiskManager 연계) ===
    SEntrySignal GetEntrySignal();
    SEntrySignal GetValidatedEntrySignal();  // 리스크 검증 포함
    bool ValidateEntrySignal(SEntrySignal &signal);  // 외부 신호 검증

    // 전략 파라미터 설정
    void SetStrategyParameters(ENUM_STRATEGY_TYPE strategy, const SStrategyParams &params);
    void SetSessionSettings(ENUM_STRATEGY_TYPE strategy, const SSessionStrategy &settings);
    void UpdateIndicatorParameters(const SIndicatorParams &params);
    void SetMinConfidence(ENUM_STRATEGY_TYPE strategy, double min_confidence);

    // 거래 제어
    void EnableTrading() { m_trading_enabled = true; }
    void DisableTrading() { m_trading_enabled = false; }
    bool IsTradingEnabled() const { return m_trading_enabled; }
    void SetSignalCooldown(int seconds) { m_signal_cooldown_seconds = seconds; }

    // 성과 모니터링
    SStrategyPerformance GetCurrentStrategyPerformance();
    string GetPerformanceReport();
    void LogAllPerformanceStats();

    // 전략 정보 조회
    string GetStrategyName(ENUM_STRATEGY_TYPE strategy);
    string GetCurrentStrategyInfo();
    string GetRiskStatusInfo();

    // 디버깅 및 진단
    bool SelfTest();
    void LogCurrentState();
};

//+------------------------------------------------------------------+
//| 생성자                                                           |
//+------------------------------------------------------------------+
CStrategySelector::CStrategySelector(CRegimeDetector* regime_detector, CSessionManager* session_manager,
                                     CRiskManager* risk_manager, string symbol, const SIndicatorParams &indicator_params) {
    // 핵심 의존성 설정
    m_regime_detector = regime_detector;
    m_session_manager = session_manager;
    m_risk_manager = risk_manager;
    m_symbol = symbol;
    m_indicator_params = indicator_params;
    
    // 기본 설정
    m_current_strategy = STRATEGY_NONE;
    m_risk_usd = 50.0;                    // 기본 리스크 50달러
    m_risk_percent = 2.0;                 // 기본 리스크 2%
    m_max_risk_per_signal = 100.0;        // 신호당 최대 100달러
    m_use_dynamic_sizing = true;          // 동적 사이징 활성화
    m_confidence_multiplier = 1.0;        // 기본 신뢰도 배수
    m_validate_all_signals = true;        // 모든 신호 검증 활성화
    
    // 파라미터 범위 강제 제한
    m_indicator_params.rsi_overbought = MathMin(100.0, m_indicator_params.rsi_overbought);
    m_indicator_params.rsi_oversold = MathMax(0.0, m_indicator_params.rsi_oversold);
    m_indicator_params.rsi_neutral_high = MathMin(100.0, m_indicator_params.rsi_neutral_high);
    m_indicator_params.rsi_neutral_low = MathMax(0.0, MathMin(100.0, m_indicator_params.rsi_neutral_low));
    
    // 신호 제어
    m_last_signal_time = 0;
    m_signal_cooldown_seconds = 60;       // 1분 쿨다운
    m_trading_enabled = true;

    // 초기화 메서드 호출
    InitializeDefaultParameters();
    InitializeSessionSettings();
    InitializePerformanceTracking();
}

//+------------------------------------------------------------------+
//| 소멸자                                                           |
//+------------------------------------------------------------------+
CStrategySelector::~CStrategySelector() {
    // 성과 통계 로깅
    LogAllPerformanceStats();
}

//+------------------------------------------------------------------+
//| 초기화                                                           |
//+------------------------------------------------------------------+
bool CStrategySelector::Initialize() {
    LogInfo("StrategySelector::Initialize() 시작");

    // 포인터 검증
    if(m_regime_detector == NULL) {
        LogError("StrategySelector: RegimeDetector 포인터가 NULL입니다");
        return false;
    }
    
    if(m_session_manager == NULL) {
        LogError("StrategySelector: SessionManager 포인터가 NULL입니다");
        return false;
    }
    
    if(m_risk_manager == NULL) {
        LogError("StrategySelector: RiskManager 포인터가 NULL입니다");
        return false;
    }

    // RiskManager 자체 테스트
    if(!(*m_risk_manager).SelfTest()) {
        LogError("StrategySelector: RiskManager 자체 테스트 실패");
        return false;
    }

    // RegimeDetector 연결 테스트 추가
    if(m_regime_detector != NULL) {
        SIndicatorGroup test_indicators;
        if(!(*m_regime_detector).GetCurrentIndicators(test_indicators)) {
            LogWarning("RegimeDetector와의 지표 데이터 연결 테스트 실패");
        } else {
            LogInfo("RegimeDetector 지표 데이터 연결 확인됨");
        }
    }
    
    // 초기 전략 선택
    if(!UpdateStrategy()) {
        LogError("StrategySelector: 초기 전략 선택 실패");
        return false;
    }

    LogInfo("StrategySelector 초기화 완료");
    LogInfo("현재 전략: " + GetStrategyName(m_current_strategy));
    LogInfo("리스크 설정: $" + DoubleToString(m_risk_usd, 2) + " (" + DoubleToString(m_risk_percent, 1) + "%)");
    
    return true;
}

//+------------------------------------------------------------------+
//| 현재 시장 데이터 가져오기 (RiskManager 연계)                     |
//+------------------------------------------------------------------+
bool CStrategySelector::GetCurrentMarketData(double &current_price, double &atr_value, SIndicatorGroup &indicators) {
    // 현재 가격
    current_price = iClose(m_symbol, PERIOD_CURRENT, 0);
    if(current_price <= 0) {
        LogError("현재 가격 획득 실패");
        return false;
    }

    // RegimeDetector에서 지표 데이터 수집
    if(!GetIndicatorDataFromRegime(indicators)) {
        LogWarning("지표 데이터 수집 실패 - 기본값 사용");  // Error → Warning
        SetDefaultIndicatorData(indicators);  // 기본값 설정
    }

    // ATR 값 추출 및 검증  
    atr_value = GetATRFromIndicators(indicators);
    if(atr_value <= 0) {
        LogWarning("ATR 값이 유효하지 않음 - 기본값 사용: " + DoubleToString(atr_value, 8));
        atr_value = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100; // 기본값 설정
    }

    // 추가 검증: 지표 값들이 합리적인 범위인지 확인
    if(!ValidateIndicatorData(indicators)) {
        LogWarning("지표 데이터 검증 실패 - 기본값 사용");
        SetDefaultIndicatorData(indicators);
    }

    return true;  // 항상 성공 반환
}

//+------------------------------------------------------------------+
//| RiskManager와 완전 연계된 신호 검증                              |
//+------------------------------------------------------------------+
bool CStrategySelector::ValidateSignalWithRiskManager(SEntrySignal &signal) {
    if(!signal.has_signal || m_risk_manager == NULL) {
        signal.risk_validated = false;
        signal.risk_validation_message = "기본 조건 불만족";
        return false;
    }

    // 1. 기본 리스크 검증
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double sl_distance = MathAbs(signal.suggested_price - signal.suggested_sl);
    
    if(!(*m_risk_manager).ValidateRisk(signal.suggested_lot, sl_distance, account_balance)) {
       signal.risk_validated = false;
       signal.risk_validation_message = "기본 리스크 검증 실패";
       return false;
    }

    // 2. 포지션 오픈 가능 여부 확인
    if(!(*m_risk_manager).CanOpenNewPosition(signal.suggested_lot, sl_distance)) {
        signal.risk_validated = false;
        signal.risk_validation_message = "새 포지션 오픈 불가";
        return false;
    }

    // 3. 마진 요구사항 확인
    if(!(*m_risk_manager).CheckMarginRequirement(signal.signal_type, signal.suggested_lot, signal.suggested_price)) {
        signal.risk_validated = false;
        signal.risk_validation_message = "마진 요구사항 미달";
        return false;
    }

    // 4. 일일 한도 확인
    if((*m_risk_manager).IsDailyLimitReached()) {
        signal.risk_validated = false;
        signal.risk_validation_message = "일일 리스크 한도 도달";
        return false;
    }

    // 5. 긴급 레벨 확인
    if((*m_risk_manager).IsEmergencyLevelReached()) {
        signal.risk_validated = false;
        signal.risk_validation_message = "긴급 레벨 도달";
        return false;
    }

    signal.risk_validated = true;
    signal.risk_validation_message = "모든 리스크 검증 통과";
    return true;
}

//+------------------------------------------------------------------+
//| 최적 포지션 사이즈 계산                                          |
//+------------------------------------------------------------------+
bool CStrategySelector::CalculateOptimalPositionSize(SEntrySignal &signal) {
    if(m_risk_manager == NULL || !signal.has_signal) return false;

    double risk_amount = m_risk_usd;
    
    // 동적 사이징이 활성화된 경우 신뢰도 기반 조정
    if(m_use_dynamic_sizing) {
        risk_amount *= signal.signal_strength * m_confidence_multiplier;
        
        // 최대/최소 제한
        risk_amount = MathMax(risk_amount, m_risk_usd * 0.25);  // 최소 25%
        risk_amount = MathMin(risk_amount, m_max_risk_per_signal);  // 최대값 제한
    }

    // RiskManager를 통한 최적 포지션 사이즈 계산
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    SRiskCalculationResult risk_result = (*m_risk_manager).CalculateOptimalPosition(
       risk_amount, signal.suggested_price, signal.suggested_sl, account_balance);

    if(!risk_result.is_valid) {
        LogError("포지션 사이즈 계산 실패: " + risk_result.validation_message);
        signal.suggested_lot = 0;
        signal.calculated_risk = 0;
        return false;
    }

    // 계산 결과 적용
    signal.suggested_lot = risk_result.suggested_lots;
    signal.calculated_risk = risk_result.actual_risk_amount;
    
    LogDebug("포지션 사이즈 계산 완료: " + 
            DoubleToString(signal.suggested_lot, 2) + " 랏, 리스크: $" + 
            DoubleToString(signal.calculated_risk, 2));

    return true;
}

//+------------------------------------------------------------------+
//| RiskManager를 통한 SL/TP 조정                                    |
//+------------------------------------------------------------------+
bool CStrategySelector::AdjustStopsWithRiskManager(SEntrySignal &signal) {
    if(m_risk_manager == NULL || !signal.has_signal) return false;

    // 현재 시장 데이터 가져오기
    SIndicatorGroup indicators;
    double current_price, atr_value;
    
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        return false;
    }

    // RiskManager를 통한 안전한 SL/TP 계산
    double safe_sl, safe_tp;
    bool calc_success = (*m_risk_manager).CalculateSafeStops(
        signal.suggested_price, 
        signal.signal_type,
        atr_value,
        m_current_params.sl_distance,
        m_current_params.tp_distance,
        safe_sl, 
        safe_tp
    );

    if(!calc_success) {
        LogError("안전한 SL/TP 계산 실패");
        return false;
    }

    // 조정된 값 적용
    signal.suggested_sl = safe_sl;
    signal.suggested_tp = safe_tp;

    // 리스크 대비 보상 비율 재계산
    signal.risk_reward_ratio = CalculateRiskRewardRatio(signal);

    LogDebug("SL/TP 조정 완료: SL=" + DoubleToString(safe_sl, _Digits) + 
            ", TP=" + DoubleToString(safe_tp, _Digits) + 
            ", R:R=" + DoubleToString(signal.risk_reward_ratio, 2));

    return true;
}

//+------------------------------------------------------------------+
//| 리스크 대비 보상 비율 계산                                       |
//+------------------------------------------------------------------+
double CStrategySelector::CalculateRiskRewardRatio(const SEntrySignal &signal) {
    if(!signal.has_signal || signal.suggested_sl == 0 || signal.suggested_tp == 0) {
        return 0.0;
    }

    double risk_distance = MathAbs(signal.suggested_price - signal.suggested_sl);
    double reward_distance = MathAbs(signal.suggested_tp - signal.suggested_price);

    if(risk_distance <= 0) return 0.0;

    return reward_distance / risk_distance;
}

//+------------------------------------------------------------------+
//| 검증된 진입 신호 생성                                            |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GetValidatedEntrySignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.signal_time = TimeCurrent();

    // 1. 거래 활성화 상태 확인
    if(!m_trading_enabled) {
        signal.has_signal = false;
        signal.signal_reason = "거래 비활성화 상태";
        return signal;
    }

    // 2. 신고 쿨다운 확인
    if(IsSignalCooldownActive()) {
        signal.has_signal = false;
        signal.signal_reason = "신호 쿨다운 중";
        return signal;
    }

    // 3. RiskManager 상태 확인
    if((*m_risk_manager).ShouldStopTrading()) {
        signal.has_signal = false;
        signal.signal_reason = "리스크 매니저가 거래 중단 권고";
        return signal;
    }
    // 4. 기본 신호 생성
    signal = GetEntrySignal();
    
    if(!signal.has_signal) {
        return signal;  // 기본 신호가 없으면 그대로 반환
    }

    // 5. 최적 포지션 사이즈 계산
    if(!CalculateOptimalPositionSize(signal)) {
        signal.has_signal = false;
        signal.signal_reason = "포지션 사이즈 계산 실패";
        return signal;
    }

    // 6. SL/TP RiskManager로 조정
    if(!AdjustStopsWithRiskManager(signal)) {
        signal.has_signal = false;
        signal.signal_reason = "SL/TP 조정 실패";
        return signal;
    }

    // 7. 최종 리스크 검증
    if(!ValidateSignalWithRiskManager(signal)) {
        signal.has_signal = false;
        signal.signal_reason = "최종 리스크 검증 실패: " + signal.risk_validation_message;
        return signal;
    }

    // 8. 신호 쿨다운 업데이트
    UpdateSignalCooldown();

    // 9. 성공 로깅
    LogInfo("검증된 신호 생성: " + signal.signal_reason + 
           ", 랏=" + DoubleToString(signal.suggested_lot, 2) + 
           ", 리스크=$" + DoubleToString(signal.calculated_risk, 2) + 
           ", R:R=" + DoubleToString(signal.risk_reward_ratio, 2));

    return signal;
}

//+------------------------------------------------------------------+
//| 기본 진입 신호 생성 (GetValidatedEntrySignal에서 호출)           |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GetEntrySignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;
    signal.signal_time = TimeCurrent();
    
    // ============= 디버그 로그 추가 ============= //
    static datetime last_log_time = 0;
    if(TimeCurrent() - last_log_time > 300) { // 5분마다 로그
        LogInfo("=== 전략 파라미터 상태 ===");
        LogInfo("현재 전략: " + GetStrategyName(m_current_strategy));
        LogInfo("ADX 임계값: " + DoubleToString(m_indicator_params.adx_trend_threshold, 1));
        LogInfo("RSI 범위: " + DoubleToString(m_indicator_params.rsi_oversold, 0) + 
                " - " + DoubleToString(m_indicator_params.rsi_overbought, 0));
        last_log_time = TimeCurrent();
    }
    
    // 현재 세션 확인
    ESessionType current_session = SESSION_UNKNOWN;
    if(m_session_manager != NULL) {
       current_session = (*m_session_manager).GetCurrentSession();
    }

    // 세션별 신호 생성
    switch(current_session) {
        case SESSION_ASIA:
            signal = GenerateAsiaSessionSignal(m_current_strategy);
            break;
        case SESSION_EUROPE:
            signal = GenerateEuropeSessionSignal(m_current_strategy);
            break;
        case SESSION_US:
            signal = GenerateUSSessionSignal(m_current_strategy);
            break;
        default:
            // 기본 전략별 신호 생성
            switch(m_current_strategy) {
                case STRATEGY_TREND_FOLLOWING:
                    signal = GenerateTrendSignal();
                    break;
                case STRATEGY_MEAN_REVERSION:
                    signal = GenerateReversionSignal();
                    break;
                case STRATEGY_BREAKOUT:
                    signal = GenerateBreakoutSignal();
                    break;
                case STRATEGY_RANGE_TRADING:
                    signal = GenerateRangeSignal();
                    break;
                case STRATEGY_SCALPING:
                    signal = GenerateScalpingSignal();
                    break;
                case STRATEGY_GAP_FADE:
                    signal = GenerateGapSignal();
                    break;
                case STRATEGY_VOLATILITY_BREAKOUT:
                    signal = GenerateVolatilitySignal();
                    break;
                default:
                    signal.signal_reason = "활성 전략 없음";
            }
    }

    // 시간 필터 적용
    if(signal.has_signal && m_current_params.use_time_filter) {
        MqlDateTime current_time;
        TimeToStruct(TimeCurrent(), current_time);

        if(current_time.hour < m_current_params.trade_start_hour ||
           current_time.hour >= m_current_params.trade_end_hour) {
            signal.has_signal = false;
            signal.signal_reason = "거래 시간 외";
        }
    }

    return signal;
}

//+------------------------------------------------------------------+
//| 추세 추종 신호 생성                                              |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateTrendSignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;

    if(m_regime_detector == NULL) {
        signal.signal_reason = "RegimeDetector 없음";
        return signal;
    }

    // 현재 레짐 데이터 가져오기
    SRegimeData regime_data = (*m_regime_detector).GetCurrentRegime();

    // 시장 데이터 수집
    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    // 강한 상승 추세 신호
    if(regime_data.dominant_regime == REGIME_STRONG_BULLISH) {
        signal.has_signal = true;
        signal.signal_type = ORDER_TYPE_BUY;
        signal.suggested_price = current_price;
        signal.signal_strength = regime_data.confidence;
        signal.signal_reason = "강한 상승 추세 감지";
        
        // 기본 SL/TP (RiskManager에서 나중에 조정됨)
        signal.suggested_sl = current_price - (atr_value * m_current_params.sl_distance);
        signal.suggested_tp = current_price + (atr_value * m_current_params.tp_distance);
    }
    // 강한 하락 추세 신호
    else if(regime_data.dominant_regime == REGIME_STRONG_BEARISH) {
        signal.has_signal = true;
       signal.signal_type = ORDER_TYPE_SELL;
        signal.suggested_price = current_price;
        signal.signal_strength = regime_data.confidence;
        signal.signal_reason = "강한 하락 추세 감지";
    
        signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance);
        signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance);
    } 
    // 추가: UNKNOWN이지만 명확한 추세가 있는 경우
    else if(regime_data.dominant_regime == REGIME_UNKNOWN) {
        // 지표에서 직접 추세 확인
        if(indicators.trend_indicators[0] > 25 && indicators.trend_indicators[1] < 0.8) {
            // ADX > 25 이고 DI+/DI- < 0.8 (하락)
            signal.has_signal = true;
            signal.signal_type = ORDER_TYPE_SELL;
            signal.suggested_price = current_price;
            signal.signal_strength = 0.5;  // 낮은 신뢰도
            signal.signal_reason = "추세 감지 (레짐 불확실)";
        
            signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance);
            signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance);
        }
    }

    return signal;
}

//+------------------------------------------------------------------+
//| 평균 회귀 신호 생성                                              |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateReversionSignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;

    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    double rsi = indicators.momentum_indicators[0];

    // RSI 과매도 반전 신호
    if(IsRSIOversold(rsi)) {
        signal.has_signal = true;
        signal.signal_type = ORDER_TYPE_BUY;
        signal.suggested_price = current_price;
        signal.signal_strength = (m_indicator_params.rsi_oversold - rsi) / m_indicator_params.rsi_oversold;
        signal.signal_reason = "RSI 과매도 반전 (" + DoubleToString(rsi, 1) + ")";
        
        signal.suggested_sl = current_price - (atr_value * m_current_params.sl_distance);
        signal.suggested_tp = current_price + (atr_value * m_current_params.tp_distance);
    }
    // RSI 과매수 반전 신호
    else if(IsRSIOverbought(rsi)) {
        signal.has_signal = true;
        signal.signal_type = ORDER_TYPE_SELL;
        signal.suggested_price = current_price;
        signal.signal_strength = (rsi - m_indicator_params.rsi_overbought) / (100 - m_indicator_params.rsi_overbought);
        signal.signal_reason = "RSI 과매수 반전 (" + DoubleToString(rsi, 1) + ")";
        
        signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance);
        signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance);
    }

    return signal;
}

//+------------------------------------------------------------------+
//| 돌파 신호 생성                                                   |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateBreakoutSignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;

    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    double bb_width = indicators.volatility_indicators[2];
    double volume_ratio = indicators.volume_indicators[0];
    double rsi = indicators.momentum_indicators[0];

    // 변동성 확장과 높은 거래량 조건
    if(IsBollingerBandWide(bb_width) && IsVolumeHigh(volume_ratio)) {
        // 상승 돌파 신호
        if(rsi > 60) {
            signal.has_signal = true;
            signal.signal_type = ORDER_TYPE_BUY;
            signal.suggested_price = current_price;
            signal.signal_strength = MathMin((bb_width / m_indicator_params.bb_width_wide) * (volume_ratio / 2.0), 1.0);
            signal.signal_reason = "상승 돌파 (BB폭=" + DoubleToString(bb_width*100, 2) + "%, 거래량=" + DoubleToString(volume_ratio, 1) + "x)";

            signal.suggested_sl = current_price - (atr_value * m_current_params.sl_distance);
            signal.suggested_tp = current_price + (atr_value * m_current_params.tp_distance);
        }
        // 하락 돌파 신호
        else if(rsi < 40) {
            signal.has_signal = true;
            signal.signal_type = ORDER_TYPE_SELL;
            signal.suggested_price = current_price;
            signal.signal_strength = MathMin((bb_width / m_indicator_params.bb_width_wide) * (volume_ratio / 2.0), 1.0);
            signal.signal_reason = "하락 돌파 (BB폭=" + DoubleToString(bb_width*100, 2) + "%, 거래량=" + DoubleToString(volume_ratio, 1) + "x)";

            signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance);
            signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance);
        }
    }

    return signal;
}

//+------------------------------------------------------------------+
//| 레인지 거래 신호 생성                                            |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateRangeSignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;
    
    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    double rsi = indicators.momentum_indicators[0];
    double adx = indicators.trend_indicators[0];
    double bb_width = indicators.volatility_indicators[2];
    
     // RSI 값 로깅 추가
    LogDebug(StringFormat("레인지 체크: RSI=%.1f, ADX=%.1f, BB_Width=%.4f", rsi, adx, bb_width));
    LogDebug(StringFormat("RSI 범위: Oversold=%.1f, Neutral[%.1f-%.1f], Overbought=%.1f", 
        m_indicator_params.rsi_oversold, m_indicator_params.rsi_neutral_low,
        m_indicator_params.rsi_neutral_high, m_indicator_params.rsi_overbought));
    
    // 파라미터 유효성 체크
    if(m_indicator_params.rsi_neutral_low > 100 || m_indicator_params.rsi_neutral_high > 100) {
        LogError("RSI 중립 범위가 100을 초과 - 신호 생성 중단");
        signal.signal_reason = "잘못된 RSI 파라미터";
        return signal;
    }
    
    // 레인지 조건: 낮은 ADX, 좁은 볼린저 밴드
    if(adx < m_indicator_params.adx_trend_threshold && IsBollingerBandNarrow(bb_width)) {
        
        // 레인지 하단에서 매수
        if(rsi < m_indicator_params.rsi_neutral_low) {
            signal.has_signal = true;
            signal.signal_type = ORDER_TYPE_BUY;
            signal.suggested_price = current_price;
            signal.signal_strength = (m_indicator_params.rsi_neutral_low - rsi) / m_indicator_params.rsi_neutral_low;
            signal.signal_reason = "레인지 하단 매수 (RSI=" + DoubleToString(rsi, 1) + ", ADX=" + DoubleToString(adx, 1) + ")";

            // 레인지 거래는 타이트한 SL/TP 사용
            signal.suggested_sl = current_price - (atr_value * m_current_params.sl_distance * 0.8);
            signal.suggested_tp = current_price + (atr_value * m_current_params.tp_distance * 0.6);
        }
        // 레인지 상단에서 매도
        else if(rsi > m_indicator_params.rsi_neutral_high) {
            signal.has_signal = true;
            signal.signal_type = ORDER_TYPE_SELL;
            signal.suggested_price = current_price;
            signal.signal_strength = (rsi - m_indicator_params.rsi_neutral_high) / (100 - m_indicator_params.rsi_neutral_high);
            signal.signal_reason = "레인지 상단 매도 (RSI=" + DoubleToString(rsi, 1) + ", ADX=" + DoubleToString(adx, 1) + ")";

            signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance * 0.8);
            signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance * 0.6);
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| 스캘핑 신호 생성                                                 |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateScalpingSignal()
{
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;
    
    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    double rsi = indicators.momentum_indicators[0];
    double volume_ratio = indicators.volume_indicators[0];

    // 스캘핑 조건: 중립 RSI, 높은 거래량
    if(rsi > 45 && rsi < 55 && IsVolumeHigh(volume_ratio)) {

        // ✅ 동적 배열 선언 + 크기 지정 + asSeries 적용
        MqlRates recent_rates[];
        ArrayResize(recent_rates, 3);           // 길이 3으로 확보
        ArraySetAsSeries(recent_rates, true);   // [0]=최신, [2]=가장 과거

        // ✅ CopyRates, 최신→과거 순으로 들어감 ([0]=최신)
        if(CopyRates(m_symbol, PERIOD_CURRENT, 0, 3, recent_rates) == 3) {
            // 최신→과거로 순서 바뀜에 주의!
            bool upward_momentum = (recent_rates[0].close > recent_rates[1].close &&
                                    recent_rates[1].close > recent_rates[2].close);
            bool downward_momentum = (recent_rates[0].close < recent_rates[1].close &&
                                      recent_rates[1].close < recent_rates[2].close);

            if(upward_momentum) {
                signal.has_signal = true;
                signal.signal_type = ORDER_TYPE_BUY;
                signal.suggested_price = current_price;
                signal.signal_strength = volume_ratio - 1.0;
                signal.signal_reason = "상승 스캘핑 (3봉 연속 상승, 거래량=" + DoubleToString(volume_ratio, 1) + "x)";

                // 스캘핑: 타이트한 SL/TP
                signal.suggested_sl = current_price - (atr_value * 0.5);
                signal.suggested_tp = current_price + (atr_value * 0.3);
            }
            else if(downward_momentum) {
                signal.has_signal = true;
                signal.signal_type = ORDER_TYPE_SELL;
                signal.suggested_price = current_price;
                signal.signal_strength = volume_ratio - 1.0;
                signal.signal_reason = "하락 스캘핑 (3봉 연속 하락, 거래량=" + DoubleToString(volume_ratio, 1) + "x)";

                signal.suggested_sl = current_price + (atr_value * 0.5);
                signal.suggested_tp = current_price - (atr_value * 0.3);
            }
        }
    }
    
    return signal;
}


//+------------------------------------------------------------------+
//| 갭 페이드 신호 생성                                              |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateGapSignal()
{
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;
    
    // ✅ 동적 배열 + 시리즈 세팅
    MqlRates rates[];
    ArrayResize(rates, 2);
    ArraySetAsSeries(rates, true);

    if(CopyRates(m_symbol, PERIOD_CURRENT, 0, 2, rates) != 2) {
        signal.signal_reason = "가격 데이터 획득 실패";
        return signal;
    }

    // rates[0] = 현재 봉, rates[1] = 이전 봉 ← ★ 순서 명확!
    double gap_size = MathAbs(rates[0].open - rates[1].close);
    double avg_range = (rates[0].high - rates[0].low + rates[1].high - rates[1].low) / 2;

    // 갭이 평균 범위의 30% 이상인 경우만 처리
    if(gap_size > avg_range * 0.3) {
        SIndicatorGroup indicators;
        double current_price, atr_value;
        if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
            signal.signal_reason = "시장 데이터 획득 실패";
            return signal;
        }

        double volume_ratio = indicators.volume_indicators[0];
        // 갭업이면 매도, 갭다운이면 매수
        bool is_gap_up = (rates[0].open > rates[1].close);

        if(IsVolumeHigh(volume_ratio)) {
            signal.has_signal = true;
            signal.signal_type = is_gap_up ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            signal.suggested_price = current_price;
            signal.signal_strength = gap_size / avg_range;
            signal.signal_reason = (is_gap_up ? "갭업 페이드" : "갭다운 페이드") + 
                                   " (갭=" + DoubleToString(gap_size, _Digits) + ", 거래량=" + DoubleToString(volume_ratio, 1) + "x)";

            double gap_multiplier = MathMin(gap_size / avg_range, 2.0);
            signal.suggested_sl = is_gap_up ? 
                                 current_price + (atr_value * m_current_params.sl_distance * gap_multiplier) :
                                 current_price - (atr_value * m_current_params.sl_distance * gap_multiplier);
            signal.suggested_tp = is_gap_up ? 
                                 current_price - (atr_value * m_current_params.tp_distance * gap_multiplier) :
                                 current_price + (atr_value * m_current_params.tp_distance * gap_multiplier);
        }
    }
    
    return signal;
}


//+------------------------------------------------------------------+
//| 변동성 돌파 신호 생성                                            |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateVolatilitySignal() {
    SEntrySignal signal;
    ZeroMemory(signal);
    signal.has_signal = false;
    
    SIndicatorGroup indicators;
    double current_price, atr_value;
    if(!GetCurrentMarketData(current_price, atr_value, indicators)) {
        signal.signal_reason = "시장 데이터 획득 실패";
        return signal;
    }

    double atr_change = indicators.volatility_indicators[1]; // ATR 변화율
    double bb_width = indicators.volatility_indicators[2];
    double volume_ratio = indicators.volume_indicators[0];
    double adx = indicators.trend_indicators[0];
    double di_balance = indicators.trend_indicators[1];

    // 변동성 확장 조건: ATR 증가, 넓은 볼린저 밴드, 높은 거래량
    if(atr_change > 0.1 && IsBollingerBandWide(bb_width) && IsVolumeHigh(volume_ratio)) {
        
        if(IsADXTrendStrong(adx)) {
            // 강한 상승 추세에서 변동성 돌파
            if(di_balance > 1.2) {
                signal.has_signal = true;
                signal.signal_type = ORDER_TYPE_BUY;
                signal.suggested_price = current_price;
                signal.signal_strength = atr_change * bb_width * (volume_ratio / 2.0);
                signal.signal_reason = "변동성 상승 돌파 (ATR변화=" + DoubleToString(atr_change*100, 1) + 
                                     "%, ADX=" + DoubleToString(adx, 1) + ", DI비율=" + DoubleToString(di_balance, 2) + ")";

                // 변동성 돌파는 넓은 SL/TP 사용
                signal.suggested_sl = current_price - (atr_value * m_current_params.sl_distance * 1.2);
                signal.suggested_tp = current_price + (atr_value * m_current_params.tp_distance * 1.5);
            }
            // 강한 하락 추세에서 변동성 돌파
            else if(di_balance < 0.8) {
                signal.has_signal = true;
                signal.signal_type = ORDER_TYPE_SELL;
                signal.suggested_price = current_price;
                signal.signal_strength = atr_change * bb_width * (volume_ratio / 2.0);
                signal.signal_reason = "변동성 하락 돌파 (ATR변화=" + DoubleToString(atr_change*100, 1) + 
                                     "%, ADX=" + DoubleToString(adx, 1) + ", DI비율=" + DoubleToString(di_balance, 2) + ")";

                signal.suggested_sl = current_price + (atr_value * m_current_params.sl_distance * 1.2);
                signal.suggested_tp = current_price - (atr_value * m_current_params.tp_distance * 1.5);
            }
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| 세션별 신호 생성 로직                                            |
//+------------------------------------------------------------------+
SEntrySignal CStrategySelector::GenerateAsiaSessionSignal(ENUM_STRATEGY_TYPE strategy) {
    // 아시아 세션 특화 로직 먼저 적용
    SEntrySignal signal;
    
    // 아시아 세션 특성 확인
    if(m_session_manager != NULL) {
        double asia_volatility = (*m_session_manager).GetSessionVolatilityFactor();
        if(asia_volatility < 0.8) {  // 낮은 변동성
            // 레인지나 스캘핑 전략 선호
            if(strategy == STRATEGY_TREND_FOLLOWING) {
                strategy = STRATEGY_RANGE_TRADING;  // 전략 변경
                LogInfo("아시아 세션 저변동성으로 레인지 거래로 변경");
            }
        }
    }
    
    // 기본 전략 신호 생성
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING: 
            signal = GenerateTrendSignal();
            break;
        case STRATEGY_RANGE_TRADING:
            signal = GenerateRangeSignal();
            break;
        // ... 다른 전략들
        default:
            ZeroMemory(signal);
            signal.signal_reason = "아시아 세션에서 지원하지 않는 전략";
            return signal;
    }
    
    // 아시아 세션 특화 조정
    if(signal.has_signal) {
        signal.signal_strength *= 0.8;  // 아시아 세션 신호 강도 조정
        signal.signal_reason += " (아시아세션 조정)";
    }
    
    return signal;
}

SEntrySignal CStrategySelector::GenerateEuropeSessionSignal(ENUM_STRATEGY_TYPE strategy) {
    // 유럽 세션 특성에 맞춘 신호 생성
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
        case STRATEGY_BREAKOUT:
        case STRATEGY_VOLATILITY_BREAKOUT:
            // 유럽 세션은 추세와 돌파에 적합
            if(strategy == STRATEGY_TREND_FOLLOWING) return GenerateTrendSignal();
            else if(strategy == STRATEGY_BREAKOUT) return GenerateBreakoutSignal();
            else return GenerateVolatilitySignal();
        default:
            // 다른 전략들은 직접 호출
            switch(strategy) {
                case STRATEGY_MEAN_REVERSION: return GenerateReversionSignal();
                case STRATEGY_RANGE_TRADING: return GenerateRangeSignal();
                case STRATEGY_SCALPING: return GenerateScalpingSignal();
                case STRATEGY_GAP_FADE: return GenerateGapSignal();
                default:
                {  // 블록 시작
                    SEntrySignal empty_signal;
                    ZeroMemory(empty_signal);
                    empty_signal.signal_reason = "유럽 세션에서 지원하지 않는 전략";
                    return empty_signal;
                }  // 블록 끝
            }
    }
}

SEntrySignal CStrategySelector::GenerateUSSessionSignal(ENUM_STRATEGY_TYPE strategy) {
    // 미국 세션 특성에 맞춘 신호 생성
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
        case STRATEGY_BREAKOUT:
        case STRATEGY_GAP_FADE:
        case STRATEGY_VOLATILITY_BREAKOUT:
            // 미국 세션은 모든 전략에 적합하지만 특히 이들에 강함
            if(strategy == STRATEGY_TREND_FOLLOWING) return GenerateTrendSignal();
            else if(strategy == STRATEGY_BREAKOUT) return GenerateBreakoutSignal();
            else if(strategy == STRATEGY_GAP_FADE) return GenerateGapSignal();
            else return GenerateVolatilitySignal();
        default:
            // 다른 전략들은 직접 호출
            switch(strategy) {
                case STRATEGY_MEAN_REVERSION: return GenerateReversionSignal();
                case STRATEGY_RANGE_TRADING: return GenerateRangeSignal();
                case STRATEGY_SCALPING: return GenerateScalpingSignal();
                default:
                {  // 블록 시작
                    SEntrySignal empty_signal;
                    ZeroMemory(empty_signal);
                    empty_signal.signal_reason = "미국 세션에서 지원하지 않는 전략";
                    return empty_signal;
                }  // 블록 끝
            }
    }
}

//+------------------------------------------------------------------+
//| 전략 업데이트 (레짐과 세션에 기반한 전략 선택)                   |
//+------------------------------------------------------------------+
bool CStrategySelector::UpdateStrategy() {
    // 포인터 NULL 체크
    if(m_regime_detector == NULL || m_session_manager == NULL) {
        LogError("UpdateStrategy: 필수 포인터가 NULL");
        return false;
    }

    // 현재 레짐 가져오기
    SRegimeData regime_data = (*m_regime_detector).GetCurrentRegime();

    // 현재 세션 가져오기
    ESessionType current_session = (*m_session_manager).GetCurrentSession();

    ENUM_STRATEGY_TYPE selected_strategy = SelectStrategyByRegime(regime_data.dominant_regime, regime_data.confidence);

    // 세션별 유효성 검사
    if(!IsStrategyValidForSession(selected_strategy, current_session)) {
        LogInfo("전략 " + GetStrategyName(selected_strategy) + "은(는) " +
                GetSessionNameStr(current_session) + "에서 유효하지 않음");
        selected_strategy = STRATEGY_NONE;
    }

    // 신뢰도 검사
    bool confidence_ok = (selected_strategy == STRATEGY_NONE) ? true : 
                        (regime_data.confidence >= GetStrategyMinConfidence(selected_strategy));

    if(!confidence_ok) {
        LogInfo("레짐 신뢰도 부족: " + DoubleToString(regime_data.confidence*100, 1) + 
               "% (필요: " + DoubleToString(GetStrategyMinConfidence(selected_strategy)*100, 1) + "%)");
        selected_strategy = STRATEGY_NONE;
    }

    // 전략 변경 시 로깅
    if(m_current_strategy != selected_strategy) {
        LogInfo("전략 변경: " + GetStrategyName(m_current_strategy) + " -> " +
                GetStrategyName(selected_strategy) + " (레짐: " + GetRegimeNameForLogging(regime_data.dominant_regime) + 
                ", 신뢰도: " + DoubleToString(regime_data.confidence*100, 1) + "%)");
    }

    // 전략 설정
    m_current_strategy = selected_strategy;

    // 파라미터 설정
    switch(m_current_strategy) {
        case STRATEGY_TREND_FOLLOWING:
            m_current_params = m_trend_params;
            break;
        case STRATEGY_MEAN_REVERSION:
            m_current_params = m_reversion_params;
            break;
        case STRATEGY_BREAKOUT:
            m_current_params = m_breakout_params;
            break;
        case STRATEGY_RANGE_TRADING:
            m_current_params = m_range_params;
            break;
        case STRATEGY_SCALPING:
            m_current_params = m_scalping_params;
            break;
        case STRATEGY_GAP_FADE:
            m_current_params = m_gap_params;
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            m_current_params = m_volatility_params;
            break;
        default:
            ZeroMemory(m_current_params);
            m_current_params.strategy_type = STRATEGY_NONE;
    }

    // 세션에 따른 파라미터 조정
    if(m_current_strategy != STRATEGY_NONE) {
        AdjustStrategyForSession(m_current_params, current_session);
    }

    return true;
}

//+------------------------------------------------------------------+
//| 레짐에 따른 전략 선택                                            |
//+------------------------------------------------------------------+
ENUM_STRATEGY_TYPE CStrategySelector::SelectStrategyByRegime(ENUM_MARKET_REGIME regime, double confidence) {
    switch(regime) {
        case REGIME_STRONG_BULLISH:
        case REGIME_STRONG_BEARISH:
            return STRATEGY_TREND_FOLLOWING;

        case REGIME_CONSOLIDATION:
            return STRATEGY_RANGE_TRADING;

        case REGIME_VOLATILITY_EXPANSION:
            return (confidence > 0.7) ? STRATEGY_VOLATILITY_BREAKOUT : STRATEGY_BREAKOUT;

        case REGIME_OVERNIGHT_DRIFT:
            return STRATEGY_SCALPING;

        case REGIME_GAP_TRADING:
            return STRATEGY_GAP_FADE;

        case REGIME_TECHNICAL_REVERSAL:
            return STRATEGY_MEAN_REVERSION;

        default:
            return STRATEGY_NONE;
    }
}

//+------------------------------------------------------------------+
//| 세션별 전략 유효성 검사                                          |
//+------------------------------------------------------------------+
bool CStrategySelector::IsStrategyValidForSession(ENUM_STRATEGY_TYPE strategy, ESessionType session) {
    SSessionStrategy session_settings;

    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            session_settings = m_trend_sessions;
            break;
        case STRATEGY_MEAN_REVERSION:
            session_settings = m_reversion_sessions;
            break;
        case STRATEGY_BREAKOUT:
            session_settings = m_breakout_sessions;
            break;
        case STRATEGY_RANGE_TRADING:
            session_settings = m_range_sessions;
            break;
        case STRATEGY_SCALPING:
            session_settings = m_scalping_sessions;
            break;
        case STRATEGY_GAP_FADE:
            session_settings = m_gap_sessions;
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            session_settings = m_volatility_sessions;
            break;
        default:
            return false;
    }

    switch(session) {
        case SESSION_ASIA:
            return session_settings.asia_active;
        case SESSION_EUROPE:
            return session_settings.europe_active;
        case SESSION_US:
            return session_settings.us_active;
        default:
            return false;
    }
}

//+------------------------------------------------------------------+
//| 세션에 따른 전략 파라미터 조정                                   |
//+------------------------------------------------------------------+
void CStrategySelector::AdjustStrategyForSession(SStrategyParams &params, ESessionType session) {
    if(m_session_manager == NULL) return;

    const SStrategyParams base = params;    // [삽입]

    double session_multiplier = 1.0;

    // 전략별 세션 배수 가져오기
    SSessionStrategy session_settings;

    switch(params.strategy_type) {
        case STRATEGY_TREND_FOLLOWING:      session_settings = m_trend_sessions;      break;
        case STRATEGY_MEAN_REVERSION:       session_settings = m_reversion_sessions;  break;
        case STRATEGY_BREAKOUT:             session_settings = m_breakout_sessions;   break;
        case STRATEGY_RANGE_TRADING:        session_settings = m_range_sessions;      break;
        case STRATEGY_SCALPING:             session_settings = m_scalping_sessions;   break;
        case STRATEGY_GAP_FADE:             session_settings = m_gap_sessions;        break;
        case STRATEGY_VOLATILITY_BREAKOUT:  session_settings = m_volatility_sessions; break;
    }

    switch(session) {
        case SESSION_ASIA:   session_multiplier = session_settings.asia_multiplier;   break;
        case SESSION_EUROPE: session_multiplier = session_settings.europe_multiplier; break;
        case SESSION_US:     session_multiplier = session_settings.us_multiplier;     break;
    }

    // [수정] 누적 방지 (항상 base에서 곱하기)
    params.sl_distance     = base.sl_distance     * session_multiplier;
    params.tp_distance     = base.tp_distance     * session_multiplier;
    params.entry_threshold = base.entry_threshold * session_multiplier;
    params.risk_multiplier = base.risk_multiplier * session_multiplier;

    // 세션별 시간 필터 설정
    if(params.use_time_filter) {
        switch(session) {
            case SESSION_ASIA:
                params.trade_start_hour = 1;
                params.trade_end_hour = 7;
                break;
            case SESSION_EUROPE:
                params.trade_start_hour = 8;
                params.trade_end_hour = 16;
                break;
            case SESSION_US:
                params.trade_start_hour = 14;
                params.trade_end_hour = 22;
                break;
        }
    }
}

//+------------------------------------------------------------------+
//| RegimeDetector로부터 지표 데이터 가져오기                        |
//+------------------------------------------------------------------+
bool CStrategySelector::GetIndicatorDataFromRegime(SIndicatorGroup &indicators) {
    static SIndicatorGroup cached_indicators;
    static datetime last_update = 0;
    datetime now = TimeCurrent();
    
    // 1초 이내 재호출이면 캐시 사용
    if(now - last_update < 1) {
        indicators = cached_indicators;
        return true;
    }
    
    if(m_regime_detector == NULL) {
        LogError("RegimeDetector 포인터가 NULL입니다");
        return false;
    }
    
    // ★ 실제 데이터 당겨오기
    if(!(*m_regime_detector).GetCurrentIndicators(cached_indicators)) {
         LogError("RegimeDetector 지표 수집 실패");
         return false;
    }
    
    LogTrace("StrategySelector: RegimeDetector로부터 지표 데이터 수집 완료");
    return true;
}

//+------------------------------------------------------------------+
//| 지표 데이터 검증                                                 |
//+------------------------------------------------------------------+
bool CStrategySelector::ValidateIndicatorData(const SIndicatorGroup &indicators) {
    
    // 백테스트 초기에는 검증을 완화
    if(MQLInfoInteger(MQL_TESTER)) {
        static int validation_skip_count = 0;
        if(validation_skip_count < 10) {
            validation_skip_count++;
            return true; // 처음 10개 바는 검증 스킵
        }
    }
    
    // ADX 범위 체크 (0-100)
    if(indicators.trend_indicators[0] < 0 || indicators.trend_indicators[0] > 100) {
        LogWarning("ADX 값이 범위를 벗어남: " + DoubleToString(indicators.trend_indicators[0], 2));
        return false;
    }
    
    // RSI 범위 체크 (0-100)
    if(indicators.momentum_indicators[0] < 0 || indicators.momentum_indicators[0] > 100) {
        LogWarning("RSI 값이 범위를 벗어남: " + DoubleToString(indicators.momentum_indicators[0], 2));
        return false;
    }
    
    // ATR 양수 체크
    if(indicators.volatility_indicators[0] <= 0) {
        LogWarning("ATR 값이 0 이하: " + DoubleToString(indicators.volatility_indicators[0], 8));
        return false;
    }
    
    // 볼린저 밴드 폭 양수 체크
    if(indicators.volatility_indicators[2] <= 0) {
        LogWarning("볼린저 밴드 폭이 0 이하: " + DoubleToString(indicators.volatility_indicators[2], 6));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 기본 지표 데이터 설정                                            |
//+------------------------------------------------------------------+
void CStrategySelector::SetDefaultIndicatorData(SIndicatorGroup &indicators) {
    // 안전한 기본값들 설정
    indicators.trend_indicators[0] = 25.0;        // ADX
    indicators.trend_indicators[1] = 1.0;         // DI+/DI- 비율
    indicators.trend_indicators[2] = 0.0001;      // EMA 기울기
    
    indicators.momentum_indicators[0] = 50.0;     // RSI (중립)
    indicators.momentum_indicators[1] = 0.0;      // RSI 기울기
    
    double default_atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100;
    indicators.volatility_indicators[0] = default_atr;  // ATR
    indicators.volatility_indicators[1] = 0.0;          // ATR 변화율
    indicators.volatility_indicators[2] = 0.03;         // BB 폭
    
    indicators.volume_indicators[0] = 1.0;        // 거래량 비율
    
    LogInfo("기본 지표 데이터로 설정됨");
}

//+------------------------------------------------------------------+
//| 특정 타임프레임 지표 데이터 가져오기                             |
//+------------------------------------------------------------------+
bool CStrategySelector::GetSpecificTimeframeIndicators(ENUM_TIMEFRAMES tf, SIndicatorGroup &indicators) {
    if(m_regime_detector == NULL) {
        LogError("RegimeDetector 포인터가 NULL");
        return false;
    }
    
    // RegimeDetector에서 특정 타임프레임 지표 데이터 가져오기
    if(!(*m_regime_detector).GetIndicatorValues(tf, indicators)) {
        LogError("특정 타임프레임 지표 데이터 수집 실패: " + EnumToString(tf));
        return false;
    }
    
    return true;
}
//+------------------------------------------------------------------+
//| 기술적 분석 헬퍼 함수들                                          |
//+------------------------------------------------------------------+
bool CStrategySelector::IsRSIOversold(double rsi_value) {
    return (rsi_value < m_indicator_params.rsi_oversold);
}

bool CStrategySelector::IsRSIOverbought(double rsi_value) {
    return (rsi_value > m_indicator_params.rsi_overbought);
}

bool CStrategySelector::IsADXTrendStrong(double adx_value) {
    return (adx_value > m_indicator_params.adx_trend_threshold);
}

bool CStrategySelector::IsBollingerBandNarrow(double bb_width) {
    return (bb_width < m_indicator_params.bb_width_narrow);
}

bool CStrategySelector::IsBollingerBandWide(double bb_width) {
    return (bb_width > m_indicator_params.bb_width_wide);
}

bool CStrategySelector::IsVolumeHigh(double volume_ratio) {
    return (volume_ratio > 1.2); // 20% 이상 증가
}

//+------------------------------------------------------------------+
//| 시장 상태 분석 메서드들                                          |
//+------------------------------------------------------------------+
bool CStrategySelector::IsMarketTrending(const SIndicatorGroup &indicators) {
    double adx = indicators.trend_indicators[0];
    double di_balance = indicators.trend_indicators[1];
    
    return (adx > m_indicator_params.adx_trend_threshold && 
            (di_balance > 1.2 || di_balance < 0.8));
}

bool CStrategySelector::IsMarketRanging(const SIndicatorGroup &indicators) {
    double adx = indicators.trend_indicators[0];
    double rsi = indicators.momentum_indicators[0];
    double bb_width = indicators.volatility_indicators[2];
    
    return (adx < m_indicator_params.adx_trend_threshold && 
            rsi > m_indicator_params.rsi_neutral_low && 
            rsi < m_indicator_params.rsi_neutral_high &&
            bb_width < m_indicator_params.bb_width_narrow);
}

bool CStrategySelector::IsMarketVolatile(const SIndicatorGroup &indicators) {
    double atr_change = indicators.volatility_indicators[1];
    double bb_width = indicators.volatility_indicators[2];
    double volume_ratio = indicators.volume_indicators[0];
    
    return (atr_change > 0.1 || bb_width > m_indicator_params.bb_width_wide || volume_ratio > 1.5);
}

double CStrategySelector::GetMarketStrength(const SIndicatorGroup &indicators) {
    double adx = indicators.trend_indicators[0];
    double volume_ratio = indicators.volume_indicators[0];
    double bb_width = indicators.volatility_indicators[2];
    
    // 정규화된 시장 강도 (0-1)
    double adx_strength = MathMin(adx / 50.0, 1.0);
    double volume_strength = MathMin(volume_ratio / 2.0, 1.0);
    double volatility_strength = MathMin(bb_width / (m_indicator_params.bb_width_wide * 2), 1.0);
    
    return (adx_strength + volume_strength + volatility_strength) / 3.0;
}

//+------------------------------------------------------------------+
//| 헬퍼 함수들                                                      |
//+------------------------------------------------------------------+
double CStrategySelector::GetATRFromIndicators(const SIndicatorGroup &indicators) {
    double atr = indicators.volatility_indicators[0];
    
    // ATR 값이 0이거나 비정상적으로 작은 경우 기본값 사용
    if(atr <= 0 || atr < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10) {
        atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100; // 기본값
        LogWarning("ATR 값이 비정상적, 기본값 사용: " + DoubleToString(atr, 8));
    }
    
    return atr;
}

double CStrategySelector::GetCurrentPrice() {
    return iClose(m_symbol, PERIOD_CURRENT, 0);
}

bool CStrategySelector::IsSignalCooldownActive() {
    if(m_signal_cooldown_seconds <= 0) return false;
    
    datetime current_time = TimeCurrent();
    return ((current_time - m_last_signal_time) < m_signal_cooldown_seconds);
}

void CStrategySelector::UpdateSignalCooldown() {
    m_last_signal_time = TimeCurrent();
}

string CStrategySelector::GetSessionNameStr(ESessionType session) {
    switch(session) {
        case SESSION_ASIA: return "아시아 세션";
        case SESSION_EUROPE: return "유럽 세션";
        case SESSION_US: return "미국 세션";
        default: return "알 수 없는 세션";
    }
}

double CStrategySelector::GetStrategyMinConfidence(ENUM_STRATEGY_TYPE strategy) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING: return m_trend_params.min_confidence;
        case STRATEGY_MEAN_REVERSION: return m_reversion_params.min_confidence;
        case STRATEGY_BREAKOUT: return m_breakout_params.min_confidence;
        case STRATEGY_RANGE_TRADING: return m_range_params.min_confidence;
        case STRATEGY_SCALPING: return m_scalping_params.min_confidence;
        case STRATEGY_GAP_FADE: return m_gap_params.min_confidence;
        case STRATEGY_VOLATILITY_BREAKOUT: return m_volatility_params.min_confidence;
        default: return 0.5;
    }
}

string CStrategySelector::GetRegimeNameForLogging(ENUM_MARKET_REGIME regime) {
    switch(regime) {
        case REGIME_STRONG_BULLISH: return "강한상승";
        case REGIME_STRONG_BEARISH: return "강한하락";
        case REGIME_CONSOLIDATION: return "통합";
        case REGIME_VOLATILITY_EXPANSION: return "변동성확장";
        case REGIME_OVERNIGHT_DRIFT: return "오버나이트";
        case REGIME_GAP_TRADING: return "갭패턴";
        case REGIME_TECHNICAL_REVERSAL: return "기술적반전";
        default: return "알수없음";
    }
}

//+------------------------------------------------------------------+
//| 전략 이름 반환                                                   |
//+------------------------------------------------------------------+
string CStrategySelector::GetStrategyName(ENUM_STRATEGY_TYPE strategy) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING: return "추세 추종";
        case STRATEGY_MEAN_REVERSION: return "평균 회귀";
        case STRATEGY_BREAKOUT: return "돌파";
        case STRATEGY_RANGE_TRADING: return "레인지 거래";
        case STRATEGY_SCALPING: return "스캘핑";
        case STRATEGY_GAP_FADE: return "갭 페이드";
        case STRATEGY_VOLATILITY_BREAKOUT: return "변동성 돌파";
        default: return "없음";
    }
}

//+------------------------------------------------------------------+
//| 현재 전략 정보 반환                                              |
//+------------------------------------------------------------------+
string CStrategySelector::GetCurrentStrategyInfo() {
    string info = "=== 현재 전략 정보 ===\n";
    info += "전략: " + GetStrategyName(m_current_strategy) + "\n";
    info += "신뢰도 요구: " + DoubleToString(m_current_params.min_confidence*100, 1) + "%\n";
    info += "SL 거리: " + DoubleToString(m_current_params.sl_distance, 1) + " ATR\n";
    info += "TP 거리: " + DoubleToString(m_current_params.tp_distance, 1) + " ATR\n";
    info += "최대 포지션: " + IntegerToString(m_current_params.max_positions) + "\n";
    info += "거래 활성화: " + (m_trading_enabled ? "예" : "아니오") + "\n";
    
    if(m_current_params.use_time_filter) {
        info += "거래 시간: " + IntegerToString(m_current_params.trade_start_hour) + 
               ":00 - " + IntegerToString(m_current_params.trade_end_hour) + ":00\n";
    }
    
    return info;
}

//+------------------------------------------------------------------+
//| 리스크 상태 정보 반환                                            |
//+------------------------------------------------------------------+
string CStrategySelector::GetRiskStatusInfo() {
    string info = "=== 리스크 설정 정보 ===\n";
    info += "기본 리스크: $" + DoubleToString(m_risk_usd, 2) + "\n";
    info += "리스크 비율: " + DoubleToString(m_risk_percent, 1) + "%\n";
    info += "최대 신고당 리스크: $" + DoubleToString(m_max_risk_per_signal, 2) + "\n";
    info += "동적 사이징: " + (m_use_dynamic_sizing ? "활성화" : "비활성화") + "\n";
    info += "신뢰도 배수: " + DoubleToString(m_confidence_multiplier, 2) + "\n";
    info += "신호 검증: " + (m_validate_all_signals ? "활성화" : "비활성화") + "\n";
    
    if(m_risk_manager != NULL) {
      info += "사용 가능한 리스크 용량: $" + DoubleToString((*m_risk_manager).GetAvailableRiskCapacity(), 2) + "\n";
      info += "일일 손익: $" + DoubleToString((*m_risk_manager).GetDailyPnL(), 2) + "\n";
   }
    
    return info;
}

//+------------------------------------------------------------------+
//| 기본 파라미터 초기화                                             |
//+------------------------------------------------------------------+
void CStrategySelector::InitializeDefaultParameters() {
    // 추세 추종 전략 파라미터
    m_trend_params.strategy_type = STRATEGY_TREND_FOLLOWING;
    m_trend_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_trend_params.entry_threshold = 0.6;
    m_trend_params.exit_threshold = 0.3;
    m_trend_params.sl_distance = 2.0;
    m_trend_params.tp_distance = 3.0;
    m_trend_params.trailing_stop = 1.5;
    m_trend_params.max_positions = 1;
    m_trend_params.min_confidence = 0.5;
    m_trend_params.use_time_filter = false;
    m_trend_params.risk_multiplier = 1.0;

    // 평균 회귀 전략 파라미터
    m_reversion_params.strategy_type = STRATEGY_MEAN_REVERSION;
    m_reversion_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_reversion_params.entry_threshold = 0.7;
    m_reversion_params.exit_threshold = 0.4;
    m_reversion_params.sl_distance = 1.5;
    m_reversion_params.tp_distance = 1.0;
    m_reversion_params.trailing_stop = 0;
    m_reversion_params.max_positions = 2;
    m_reversion_params.min_confidence = 0.6;
    m_reversion_params.use_time_filter = false;
    m_reversion_params.risk_multiplier = 1.0;

    // 돌파 전략 파라미터
    m_breakout_params.strategy_type = STRATEGY_BREAKOUT;
    m_breakout_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_breakout_params.entry_threshold = 0.7;
    m_breakout_params.exit_threshold = 0.4;
    m_breakout_params.sl_distance = 1.5;
    m_breakout_params.tp_distance = 2.5;
    m_breakout_params.trailing_stop = 1.0;
    m_breakout_params.max_positions = 1;
    m_breakout_params.min_confidence = 0.6;
    m_breakout_params.use_time_filter = true;
    m_breakout_params.trade_start_hour = 8;
    m_breakout_params.trade_end_hour = 20;
    m_breakout_params.risk_multiplier = 1.0;

    // 레인지 거래 전략 파라미터
    m_range_params.strategy_type = STRATEGY_RANGE_TRADING;
    m_range_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_range_params.entry_threshold = 0.5;
    m_range_params.exit_threshold = 0.3;
    m_range_params.sl_distance = 1.0;
    m_range_params.tp_distance = 0.8;
    m_range_params.trailing_stop = 0;
    m_range_params.max_positions = 2;
    m_range_params.min_confidence = 0.5;
    m_range_params.use_time_filter = false;
    m_range_params.risk_multiplier = 1.0;

    // 스캘핑 전략 파라미터
    m_scalping_params.strategy_type = STRATEGY_SCALPING;
    m_scalping_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_scalping_params.entry_threshold = 0.5;
    m_scalping_params.exit_threshold = 0.3;
    m_scalping_params.sl_distance = 0.5;
    m_scalping_params.tp_distance = 0.3;
    m_scalping_params.trailing_stop = 0;
    m_scalping_params.max_positions = 3;
    m_scalping_params.min_confidence = 0.4;
    m_scalping_params.use_time_filter = true;
    m_scalping_params.trade_start_hour = 14;
    m_scalping_params.trade_end_hour = 20;
    m_scalping_params.risk_multiplier = 0.8;

    // 갭 페이드 전략 파라미터
    m_gap_params.strategy_type = STRATEGY_GAP_FADE;
    m_gap_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_gap_params.entry_threshold = 0.6;
    m_gap_params.exit_threshold = 0.4;
    m_gap_params.sl_distance = 2.0;
    m_gap_params.tp_distance = 1.5;
    m_gap_params.trailing_stop = 0;
    m_gap_params.max_positions = 1;
    m_gap_params.min_confidence = 0.6;
    m_gap_params.use_time_filter = true;
    m_gap_params.trade_start_hour = 14;
    m_gap_params.trade_end_hour = 16;
    m_gap_params.risk_multiplier = 1.2;

    // 변동성 돌파 전략 파라미터
    m_volatility_params.strategy_type = STRATEGY_VOLATILITY_BREAKOUT;
    m_volatility_params.trade_direction = TRADE_DIRECTION_BOTH;
    m_volatility_params.entry_threshold = 0.7;
    m_volatility_params.exit_threshold = 0.4;
    m_volatility_params.sl_distance = 2.5;
    m_volatility_params.tp_distance = 3.5;
    m_volatility_params.trailing_stop = 2.0;
    m_volatility_params.max_positions = 1;
    m_volatility_params.min_confidence = 0.7;
    m_volatility_params.use_time_filter = false;
    m_volatility_params.risk_multiplier = 1.3;
}

//+------------------------------------------------------------------+
//| 세션별 설정 초기화                                               |
//+------------------------------------------------------------------+
void CStrategySelector::InitializeSessionSettings() {
    // 추세 추종 세션 설정
    m_trend_sessions.asia_active = false;
    m_trend_sessions.europe_active = true;
    m_trend_sessions.us_active = true;
    m_trend_sessions.asia_multiplier = 0.8;
    m_trend_sessions.europe_multiplier = 1.0;
    m_trend_sessions.us_multiplier = 1.2;

    // 평균 회귀 세션 설정
    m_reversion_sessions.asia_active = true;
    m_reversion_sessions.europe_active = true;
    m_reversion_sessions.us_active = false;
    m_reversion_sessions.asia_multiplier = 1.1;
    m_reversion_sessions.europe_multiplier = 1.0;
    m_reversion_sessions.us_multiplier = 0.9;

    // 돌파 세션 설정
    m_breakout_sessions.asia_active = false;
    m_breakout_sessions.europe_active = true;
    m_breakout_sessions.us_active = true;
    m_breakout_sessions.asia_multiplier = 0.7;
    m_breakout_sessions.europe_multiplier = 1.0;
    m_breakout_sessions.us_multiplier = 1.3;

    // 레인지 거래 세션 설정
    m_range_sessions.asia_active = true;
    m_range_sessions.europe_active = true;
    m_range_sessions.us_active = false;
    m_range_sessions.asia_multiplier = 1.2;
    m_range_sessions.europe_multiplier = 1.0;
    m_range_sessions.us_multiplier = 0.8;

    // 스캘핑 세션 설정
    m_scalping_sessions.asia_active = true;
    m_scalping_sessions.europe_active = false;
    m_scalping_sessions.us_active = true;
    m_scalping_sessions.asia_multiplier = 1.1;
    m_scalping_sessions.europe_multiplier = 0.9;
    m_scalping_sessions.us_multiplier = 1.2;

    // 갭 페이드 세션 설정
    m_gap_sessions.asia_active = false;
    m_gap_sessions.europe_active = false;
    m_gap_sessions.us_active = true;
    m_gap_sessions.asia_multiplier = 0.8;
    m_gap_sessions.europe_multiplier = 0.9;
    m_gap_sessions.us_multiplier = 1.0;

    // 변동성 돌파 세션 설정
    m_volatility_sessions.asia_active = false;
    m_volatility_sessions.europe_active = true;
    m_volatility_sessions.us_active = true;
    m_volatility_sessions.asia_multiplier = 0.7;
    m_volatility_sessions.europe_multiplier = 1.0;
    m_volatility_sessions.us_multiplier = 1.3;
}

//+------------------------------------------------------------------+
//| 성과 추적 초기화                                                 |
//+------------------------------------------------------------------+
void CStrategySelector::InitializePerformanceTracking() {
    // 모든 전략 성과 구조체 초기화
    ZeroMemory(m_trend_performance);
    ZeroMemory(m_reversion_performance);
    ZeroMemory(m_breakout_performance);
    ZeroMemory(m_range_performance);
    ZeroMemory(m_scalping_performance);
    ZeroMemory(m_gap_performance);
    ZeroMemory(m_volatility_performance);
}

//+------------------------------------------------------------------+
//| 전략 성과 데이터 반환                                            |
//+------------------------------------------------------------------+
bool CStrategySelector::GetStrategyPerformanceData(ENUM_STRATEGY_TYPE strategy, SStrategyPerformance &perf_out) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            perf_out = m_trend_performance;
            return true;
        case STRATEGY_MEAN_REVERSION:
            perf_out = m_reversion_performance;
            return true;
        case STRATEGY_BREAKOUT:
            perf_out = m_breakout_performance;
            return true;
        case STRATEGY_RANGE_TRADING:
            perf_out = m_range_performance;
            return true;
        case STRATEGY_SCALPING:
            perf_out = m_scalping_performance;
            return true;
        case STRATEGY_GAP_FADE:
            perf_out = m_gap_performance;
            return true;
        case STRATEGY_VOLATILITY_BREAKOUT:
            perf_out = m_volatility_performance;
            return true;
        default:
            ZeroMemory(perf_out);
            return false;
    }
}

//+------------------------------------------------------------------+
//| 전략 성과 업데이트                                               |
//+------------------------------------------------------------------+
void CStrategySelector::UpdateStrategyPerformance(ENUM_STRATEGY_TYPE strategy, bool success, double pnl) {
   
   switch(strategy) {
       case STRATEGY_TREND_FOLLOWING:
           {
               m_trend_performance.total_signals++;
               if(success) {
                   m_trend_performance.successful_signals++;
                   m_trend_performance.current_streak = (m_trend_performance.current_streak >= 0) ? m_trend_performance.current_streak + 1 : 1;
               } else {
                   m_trend_performance.current_streak = (m_trend_performance.current_streak <= 0) ? m_trend_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_trend_performance.max_consecutive_loss) {
                       m_trend_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_trend_performance.total_pnl += pnl;
               if(m_trend_performance.total_signals > 0) {
                   m_trend_performance.win_rate = (double)m_trend_performance.successful_signals / (double)m_trend_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_trend_performance.avg_risk_reward = (m_trend_performance.avg_risk_reward * (m_trend_performance.successful_signals - 1) + new_rr) / m_trend_performance.successful_signals;
                   }
               }
               m_trend_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_MEAN_REVERSION:
           {
               m_reversion_performance.total_signals++;
               if(success) {
                   m_reversion_performance.successful_signals++;
                   m_reversion_performance.current_streak = (m_reversion_performance.current_streak >= 0) ? m_reversion_performance.current_streak + 1 : 1;
               } else {
                   m_reversion_performance.current_streak = (m_reversion_performance.current_streak <= 0) ? m_reversion_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_reversion_performance.max_consecutive_loss) {
                       m_reversion_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_reversion_performance.total_pnl += pnl;
               if(m_reversion_performance.total_signals > 0) {
                   m_reversion_performance.win_rate = (double)m_reversion_performance.successful_signals / (double)m_reversion_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_reversion_performance.avg_risk_reward = (m_reversion_performance.avg_risk_reward * (m_reversion_performance.successful_signals - 1) + new_rr) / m_reversion_performance.successful_signals;
                   }
               }
               m_reversion_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_BREAKOUT:
           {
               m_breakout_performance.total_signals++;
               if(success) {
                   m_breakout_performance.successful_signals++;
                   m_breakout_performance.current_streak = (m_breakout_performance.current_streak >= 0) ? m_breakout_performance.current_streak + 1 : 1;
               } else {
                   m_breakout_performance.current_streak = (m_breakout_performance.current_streak <= 0) ? m_breakout_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_breakout_performance.max_consecutive_loss) {
                       m_breakout_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_breakout_performance.total_pnl += pnl;
               if(m_breakout_performance.total_signals > 0) {
                   m_breakout_performance.win_rate = (double)m_breakout_performance.successful_signals / (double)m_breakout_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_breakout_performance.avg_risk_reward = (m_breakout_performance.avg_risk_reward * (m_breakout_performance.successful_signals - 1) + new_rr) / m_breakout_performance.successful_signals;
                   }
               }
               m_breakout_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_RANGE_TRADING:
           {
               m_range_performance.total_signals++;
               if(success) {
                   m_range_performance.successful_signals++;
                   m_range_performance.current_streak = (m_range_performance.current_streak >= 0) ? m_range_performance.current_streak + 1 : 1;
               } else {
                   m_range_performance.current_streak = (m_range_performance.current_streak <= 0) ? m_range_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_range_performance.max_consecutive_loss) {
                       m_range_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_range_performance.total_pnl += pnl;
               if(m_range_performance.total_signals > 0) {
                   m_range_performance.win_rate = (double)m_range_performance.successful_signals / (double)m_range_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_range_performance.avg_risk_reward = (m_range_performance.avg_risk_reward * (m_range_performance.successful_signals - 1) + new_rr) / m_range_performance.successful_signals;
                   }
               }
               m_range_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_SCALPING:
           {
               m_scalping_performance.total_signals++;
               if(success) {
                   m_scalping_performance.successful_signals++;
                   m_scalping_performance.current_streak = (m_scalping_performance.current_streak >= 0) ? m_scalping_performance.current_streak + 1 : 1;
               } else {
                   m_scalping_performance.current_streak = (m_scalping_performance.current_streak <= 0) ? m_scalping_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_scalping_performance.max_consecutive_loss) {
                       m_scalping_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_scalping_performance.total_pnl += pnl;
               if(m_scalping_performance.total_signals > 0) {
                   m_scalping_performance.win_rate = (double)m_scalping_performance.successful_signals / (double)m_scalping_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_scalping_performance.avg_risk_reward = (m_scalping_performance.avg_risk_reward * (m_scalping_performance.successful_signals - 1) + new_rr) / m_scalping_performance.successful_signals;
                   }
               }
               m_scalping_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_GAP_FADE:
           {
               m_gap_performance.total_signals++;
               if(success) {
                   m_gap_performance.successful_signals++;
                   m_gap_performance.current_streak = (m_gap_performance.current_streak >= 0) ? m_gap_performance.current_streak + 1 : 1;
               } else {
                   m_gap_performance.current_streak = (m_gap_performance.current_streak <= 0) ? m_gap_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_gap_performance.max_consecutive_loss) {
                       m_gap_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_gap_performance.total_pnl += pnl;
               if(m_gap_performance.total_signals > 0) {
                   m_gap_performance.win_rate = (double)m_gap_performance.successful_signals / (double)m_gap_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_gap_performance.avg_risk_reward = (m_gap_performance.avg_risk_reward * (m_gap_performance.successful_signals - 1) + new_rr) / m_gap_performance.successful_signals;
                   }
               }
               m_gap_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       case STRATEGY_VOLATILITY_BREAKOUT:
           {
               m_volatility_performance.total_signals++;
               if(success) {
                   m_volatility_performance.successful_signals++;
                   m_volatility_performance.current_streak = (m_volatility_performance.current_streak >= 0) ? m_volatility_performance.current_streak + 1 : 1;
               } else {
                   m_volatility_performance.current_streak = (m_volatility_performance.current_streak <= 0) ? m_volatility_performance.current_streak - 1 : -1;
                   if(pnl < 0 && MathAbs(pnl) > m_volatility_performance.max_consecutive_loss) {
                       m_volatility_performance.max_consecutive_loss = MathAbs(pnl);
                   }
               }
               m_volatility_performance.total_pnl += pnl;
               if(m_volatility_performance.total_signals > 0) {
                   m_volatility_performance.win_rate = (double)m_volatility_performance.successful_signals / (double)m_volatility_performance.total_signals;
               }
               if(pnl > 0 && success) {
                   double estimated_risk = MathAbs(pnl) / 2.0;
                   if(estimated_risk > 0) {
                       double new_rr = pnl / estimated_risk;
                       m_volatility_performance.avg_risk_reward = (m_volatility_performance.avg_risk_reward * (m_volatility_performance.successful_signals - 1) + new_rr) / m_volatility_performance.successful_signals;
                   }
               }
               m_volatility_performance.last_signal_time = TimeCurrent();
           }
           break;
           
       default:
           return;
   }
}

//+------------------------------------------------------------------+
//| 성과 통계 리셋                                                   |
//+------------------------------------------------------------------+
void CStrategySelector::ResetPerformanceStats(ENUM_STRATEGY_TYPE strategy) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            ZeroMemory(m_trend_performance);
            break;
        case STRATEGY_MEAN_REVERSION:
            ZeroMemory(m_reversion_performance);
            break;
        case STRATEGY_BREAKOUT:
            ZeroMemory(m_breakout_performance);
            break;
        case STRATEGY_RANGE_TRADING:
            ZeroMemory(m_range_performance);
            break;
        case STRATEGY_SCALPING:
            ZeroMemory(m_scalping_performance);
            break;
        case STRATEGY_GAP_FADE:
            ZeroMemory(m_gap_performance);
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            ZeroMemory(m_volatility_performance);
            break;
    }
}

//+------------------------------------------------------------------+
//| 현재 전략 성과 반환                                              |
//+------------------------------------------------------------------+
SStrategyPerformance CStrategySelector::GetCurrentStrategyPerformance() {
    SStrategyPerformance perf;
    if(GetStrategyPerformanceData(m_current_strategy, perf)) {
        return perf;
    }
    
    ZeroMemory(perf);
    return perf;
}

//+------------------------------------------------------------------+
//| 성과 리포트 생성                                                 |
//+------------------------------------------------------------------+
string CStrategySelector::GetPerformanceReport() {
    string report = "=== 전략별 성과 리포트 ===\n";
    
    ENUM_STRATEGY_TYPE strategies[7] = {
        STRATEGY_TREND_FOLLOWING, STRATEGY_MEAN_REVERSION, STRATEGY_BREAKOUT,
        STRATEGY_RANGE_TRADING, STRATEGY_SCALPING, STRATEGY_GAP_FADE, STRATEGY_VOLATILITY_BREAKOUT
    };
    
    for(int i = 0; i < 7; i++) {
        SStrategyPerformance perf;
        if(GetStrategyPerformanceData(strategies[i], perf) && perf.total_signals > 0) {
            report += GetStrategyName(strategies[i]) + ":\n";
            report += "  총 신호: " + IntegerToString(perf.total_signals) + "\n";
            report += "  성공 신호: " + IntegerToString(perf.successful_signals) + "\n";
            report += "  승률: " + DoubleToString(perf.win_rate * 100, 1) + "%\n";
            report += "  총 손익: $" + DoubleToString(perf.total_pnl, 2) + "\n";
            report += "  평균 R:R: " + DoubleToString(perf.avg_risk_reward, 2) + "\n";
            report += "  연속 결과: " + IntegerToString(perf.current_streak) + "\n\n";
        }
    }
    
    return report;
}

//+------------------------------------------------------------------+
//| 모든 성과 통계 로깅                                              |
//+------------------------------------------------------------------+
void CStrategySelector::LogAllPerformanceStats() {
    string report = GetPerformanceReport();
    LogInfo(report);
}

//+------------------------------------------------------------------+
//| 현재 상태 로깅                                                   |
//+------------------------------------------------------------------+
void CStrategySelector::LogCurrentState() {
    LogInfo("=== StrategySelector 현재 상태 ===");
    LogInfo("현재 전략: " + GetStrategyName(m_current_strategy));
    LogInfo("거래 활성화: " + (m_trading_enabled ? "예" : "아니오"));
    LogInfo("신호 쿨다운: " + (IsSignalCooldownActive() ? "활성" : "비활성"));
    
    if(m_session_manager != NULL) {
       LogInfo("현재 세션: " + GetSessionNameStr((*m_session_manager).GetCurrentSession()));
    }
    
    if(m_risk_manager != NULL) {
       LogInfo("리스크 상태: " + ((*m_risk_manager).ShouldStopTrading() ? "거래 중단" : "정상"));
    }
}

//+------------------------------------------------------------------+
//| 자체 테스트                                                      |
//+------------------------------------------------------------------+
bool CStrategySelector::SelfTest() {
    LogInfo("StrategySelector 자체 테스트 시작...");
    
    bool all_passed = true;
    
    // 1. 필수 포인터 검증
    if(m_regime_detector == NULL) {
        LogError("RegimeDetector 포인터가 NULL");
        all_passed = false;
    }
    
    if(m_session_manager == NULL) {
        LogError("SessionManager 포인터가 NULL");
        all_passed = false;
    }
    
    if(m_risk_manager == NULL) {
        LogError("RiskManager 포인터가 NULL");
        all_passed = false;
    }
    
    // 2. 파라미터 검증
    if(m_risk_usd <= 0) {
        LogError("리스크 금액이 유효하지 않음");
        all_passed = false;
    }
    
    // 3. 지표 데이터 수집 테스트
    SIndicatorGroup test_indicators;
    if(!GetIndicatorDataFromRegime(test_indicators)) {
        LogError("지표 데이터 수집 실패");
        all_passed = false;
    }
    
    // 4. 전략 선택 테스트
    if(!UpdateStrategy()) {
        LogError("전략 업데이트 실패");
        all_passed = false;
    }
    
    // 5. RiskManager 연계 테스트
    if(m_risk_manager != NULL && !(*m_risk_manager).SelfTest()) {
       LogError("RiskManager 연계 테스트 실패");
       all_passed = false;
    }
    
    if(all_passed) {
        LogInfo("StrategySelector 자체 테스트 통과");
    } else {
        LogError("StrategySelector 자체 테스트 실패");
    }
    
    return all_passed;
}

//+------------------------------------------------------------------+
//| 설정 관련 메서드들                                               |
//+------------------------------------------------------------------+
void CStrategySelector::SetStrategyParameters(ENUM_STRATEGY_TYPE strategy, const SStrategyParams &params) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            m_trend_params = params;
            break;
        case STRATEGY_MEAN_REVERSION:
            m_reversion_params = params;
            break;
        case STRATEGY_BREAKOUT:
            m_breakout_params = params;
            break;
        case STRATEGY_RANGE_TRADING:
            m_range_params = params;
            break;
        case STRATEGY_SCALPING:
            m_scalping_params = params;
            break;
        case STRATEGY_GAP_FADE:
            m_gap_params = params;
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            m_volatility_params = params;
            break;
    }
}

void CStrategySelector::SetSessionSettings(ENUM_STRATEGY_TYPE strategy, const SSessionStrategy &settings) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            m_trend_sessions = settings;
            break;
        case STRATEGY_MEAN_REVERSION:
            m_reversion_sessions = settings;
            break;
        case STRATEGY_BREAKOUT:
            m_breakout_sessions = settings;
            break;
        case STRATEGY_RANGE_TRADING:
            m_range_sessions = settings;
            break;
        case STRATEGY_SCALPING:
            m_scalping_sessions = settings;
            break;
        case STRATEGY_GAP_FADE:
            m_gap_sessions = settings;
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            m_volatility_sessions = settings;
            break;
    }
}

void CStrategySelector::UpdateIndicatorParameters(const SIndicatorParams &params) {
    m_indicator_params = params;
}

void CStrategySelector::SetMinConfidence(ENUM_STRATEGY_TYPE strategy, double min_confidence) {
    switch(strategy) {
        case STRATEGY_TREND_FOLLOWING:
            m_trend_params.min_confidence = min_confidence;
            break;
        case STRATEGY_MEAN_REVERSION:
            m_reversion_params.min_confidence = min_confidence;
            break;
        case STRATEGY_BREAKOUT:
            m_breakout_params.min_confidence = min_confidence;
            break;
        case STRATEGY_RANGE_TRADING:
            m_range_params.min_confidence = min_confidence;
            break;
        case STRATEGY_SCALPING:
            m_scalping_params.min_confidence = min_confidence;
            break;
        case STRATEGY_GAP_FADE:
            m_gap_params.min_confidence = min_confidence;
            break;
        case STRATEGY_VOLATILITY_BREAKOUT:
            m_volatility_params.min_confidence = min_confidence;
            break;
    }
}

//+------------------------------------------------------------------+
//| 외부 신호 검증 (다른 시스템에서 생성된 신호 검증용)              |
//+------------------------------------------------------------------+
bool CStrategySelector::ValidateEntrySignal(SEntrySignal &signal) {
    if(!signal.has_signal) {
        signal.risk_validated = false;
        signal.risk_validation_message = "신호가 없음";
        return false;
    }

    // 거래 활성화 상태 확인
    if(!m_trading_enabled) {
        signal.risk_validated = false;
        signal.risk_validation_message = "거래 비활성화 상태";
        return false;
    }

    // 쿨다운 확인
    if(IsSignalCooldownActive()) {
        signal.risk_validated = false;
        signal.risk_validation_message = "신호 쿨다운 중";
        return false;
    }

    // RiskManager 상태 확인
    if(m_risk_manager != NULL && (*m_risk_manager).ShouldStopTrading()) {
       signal.risk_validated = false;
       signal.risk_validation_message = "리스크 매니저가 거래 중단 권고";
       return false;
    }

    // 포지션 사이즈가 설정되지 않은 경우 계산
    if(signal.suggested_lot <= 0) {
        if(!CalculateOptimalPositionSize(signal)) {
            signal.risk_validated = false;
            signal.risk_validation_message = "포지션 사이즈 계산 실패";
            return false;
        }
    }

    // SL/TP 조정
    if(!AdjustStopsWithRiskManager(signal)) {
        signal.risk_validated = false;
        signal.risk_validation_message = "SL/TP 조정 실패";
        return false;
    }

    // 최종 리스크 검증
    if(!ValidateSignalWithRiskManager(signal)) {
        return false; // ValidateSignalWithRiskManager에서 이미 메시지 설정
    }

    return true;
}

#endif // __STRATEGY_SELECTOR_MQH__