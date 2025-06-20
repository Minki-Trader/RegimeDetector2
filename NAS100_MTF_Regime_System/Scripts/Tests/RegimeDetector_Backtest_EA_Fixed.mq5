//+------------------------------------------------------------------+
//|                      RegimeDetector_Backtest_EA_Fixed_Corrected.mq5        |
//|                      NAS100 MTF Regime System                    |
//+------------------------------------------------------------------+
#property copyright "NAS100 MTF Regime System"
#property version   "1.04"
#property strict
#property description "NAS100 Multi-Timeframe Regime Detection EA (Arrow Operators Fixed)"

//--------------------------------------------------------------------
// 1) include
//--------------------------------------------------------------------
#include <Trade\Trade.mqh>
#include "..\\..\\Include\\RegimeDetection\\RegimeDefinitions.mqh"
#include "..\\..\\Include\\TimeFrames\\TimeframeData.mqh"
#include "..\\..\\Include\\Utils\\SessionManager.mqh"
#include "..\\..\\Include\\TimeFrames\\MultiTimeframeManager.mqh"
#include "..\\..\\Include\\RegimeDetection\\RegimeDetector.mqh"
#include "..\\..\\Include\\RegimeDetection\\RegimeDetectorExtensions.mqh"
#include "..\\..\\Include\\Utils\\Logger.mqh"
#include "..\\..\\Include\\Trading\\ExecutionManager.mqh"
#include "..\\..\\Include\\Trading\\RiskManager.mqh"
#include "..\\..\\Include\\Trading\\StrategySelector.mqh" 

//--------------------------------------------------------------------
// 2) 입력 파라미터
//--------------------------------------------------------------------
input string TestID = "DefaultTest";               // 결과 파일명 접두
input int InpMagic = 20250521;                     // EA 매직번호

// ―― 타임프레임
input ENUM_TIMEFRAMES Primary_TF = PERIOD_M5;      // 주 타임프레임
input ENUM_TIMEFRAMES Confirm_TF = PERIOD_M30;     // 확인 타임프레임
input ENUM_TIMEFRAMES Filter_TF  = PERIOD_H4;      // 필터 타임프레임

// === 전략 모드 ===
input group "===== 전략 모드 설정 ====="
input bool Auto_Mode_By_Session = true;            // 세션별 자동 전환

// ―― 타임프레임 가중치 기본 (사용자 우선)
input bool Use_Custom_Weights = true;              // 사용자 가중치 사용
input double Primary_Weight  = 0.5;                // 주 타임프레임 가중치
input double Confirm_Weight  = 0.3;                // 확인 타임프레임 가중치
input double Filter_Weight   = 0.2;                // 필터 타임프레임 가중치

// ―― 지표 주기
input int    ADX_Period   = 14;                    // ADX 기간
input int    RSI_Period   = 14;                    // RSI 기간
input int    MA_Period    = 20;                    // 이동평균 기간
input int    ATR_Period   = 14;                    // ATR 기간
input int    Bands_Period = 20;                    // 볼린저밴드 기간
input double Bands_Deviation = 2.0;                // 볼린저밴드 표준편차

// ―― 레짐 가중치(기본)
input double Trend_Weight      = 0.35;             // 추세 가중치
input double Momentum_Weight   = 0.30;             // 모멘텀 가중치
input double Volatility_Weight = 0.15;             // 변동성 가중치
input double Volume_Weight     = 0.20;             // 거래량 가중치

// ―― 히스테리시스
input double Hysteresis_Threshold = 0.07;          // 히스테리시스 임계값
input int    Hysteresis_Bars      = 3;             // 히스테리시스 봉 수

// ―― 신뢰도/점수 임계
input double Regime_Threshold     = 0.5;           // 레짐 임계값

// ―― RSI 영역
input double RSI_Overbought   = 70.0;              // RSI 과매수 기준
input double RSI_Oversold     = 30.0;              // RSI 과매도 기준

// === 트레이딩 파라미터 ===
input group "===== 트레이딩 파라미터 ====="
input double InpLots      = 0.10;                  // 진입 랏 크기
input int    InpSL_Pips   = 50;                    // 기본 SL (pips)
input int    InpTP_Pips   = 100;                   // 기본 TP (pips)
input int    DriftTargetPips = 40;                 // Overnight drift 목표 pips
input bool   UseStrategySelector = false;          // 전략 선택기 사용 여부 (기본 false)

// === 레벨 계산 파라미터 ===
input int    SR_LookbackBars      = 20;            // S/R 계산용 최근 N-봉
input double SR_ATR_Multiplier    = 0.5;           // ATR * 계수만큼 버퍼
input int    Breakout_LookbackBars = 15;           // 브레이크아웃용 N-봉

// === 리스크 관리 파라미터 ===
input group "===== 리스크 관리 설정 ====="
input ENUM_RISK_CALCULATION RiskType = RISK_PERCENT_EQUITY;  // 리스크 계산 방식
input double RiskValue = 2.0;                 // 리스크 값 (랏 또는 %)
input double RiskRewardRatio = 2.0;           // 손익비
input double MaxRiskPerTrade = 2.0;           // 거래당 최대 리스크 (%)
input double MaxRiskTotal = 10.0;             // 총 포지션 최대 리스크 (%)
input int MaxPositions = 5;                   // 최대 동시 포지션 수
input bool AdjustByRegimeConfidence = true;   // 레짐 신뢰도에 따른 포지션 크기 조정
input double MarginSafetyPercent = 30.0;      // 마진 안전 비율 (%)

// === UI & 저장 ===
input group "===== UI & 로깅 설정 ====="
input bool Show_Dashboard     = true;              // 대시보드 표시
input bool Mark_Regime_Changes= true;              // 레짐 변경 마커
input bool Save_Results_To_CSV= true;              // CSV 저장

// === 로깅 ===
enum ENUM_LOG_MODE_INPUT { LOG_CONSOLE_ONLY=1, LOG_FILE_ONLY=2, LOG_CONSOLE_AND_FILE=3 };

input ENUM_LOG_LEVEL     LogLevel = LOG_LEVEL_INFO;     // 로그 레벨
input ENUM_LOG_MODE_INPUT LogMode = LOG_CONSOLE_ONLY;   // 로그 출력 모드
input string             LogFileName = "";              // 로그 파일명

// ―― CSV 경로
input string CSV_Subfolder  = "Results";                // CSV 저장 폴더
input bool   Use_Custom_Path= false;                    // 사용자 경로 사용
input string Custom_CSV_Path= "";                       // 사용자 지정 경로

//--------------------------------------------------------------------
// 3) 전역 변수
//--------------------------------------------------------------------
string g_csv_filename = "";
int    file_handle    = INVALID_HANDLE;
int g_test_atr = INVALID_HANDLE;
int g_test_rsi = INVALID_HANDLE;

// 핵심 객체들 (포인터로 통일)
CSessionManager*         g_session_manager   = NULL;
CMultiTimeframeManager*  g_mtf_manager       = NULL;
CRegimeDetector*         g_regime_detector   = NULL;
CExecutionManager*       g_execution_manager = NULL;
CRiskManager*            g_risk_manager      = NULL;
CStrategySelector*       g_strategy_selector = NULL;

// input 파라미터의 조정된 값을 저장할 변수들
double adjusted_RSI_Overbought;
double adjusted_RSI_Oversold;
double adjusted_RSI_Neutral_High;
double adjusted_RSI_Neutral_Low;
double adjusted_Trend_Min_Confidence;
double adjusted_Breakout_Min_Confidence;
double adjusted_Volatility_Min_Confidence;
double adjusted_Risk_Per_Trade;
double adjusted_Partial_Close_Percent;

// 상태 관리 변수
datetime            g_last_bar_time = 0;
ENUM_MARKET_REGIME  g_last_regime   = REGIME_UNKNOWN;
bool                g_was_hysteresis_applied = false;

// 레벨 및 지표 값들 (전역 지표 핸들로 통일)
double SupportLevel      = 0;   // 레인지 하단
double ResistanceLevel   = 0;   // 레인지 상단
double BreakoutHigh      = 0;   // 변동성 확장 상단
double BreakoutLow       = 0;   // 변동성 확장 하단
double GapDirection      = 0;   // +1 위로갭, -1 아래로갭
double RSI               = 50;  // 현재 RSI 값 (0~100)

//--------------------------------------------------------------------
// 4) 유틸리티 함수들
//--------------------------------------------------------------------
// ATR 핸들
int g_atr_M5    = INVALID_HANDLE;
int g_atr_M30   = INVALID_HANDLE;
int g_atr_H4    = INVALID_HANDLE;
// RSI 핸들
int g_rsi_M5    = INVALID_HANDLE;
int g_rsi_M30   = INVALID_HANDLE;
int g_rsi_H4    = INVALID_HANDLE;
// ADX 핸들
int g_adx_M5    = INVALID_HANDLE;
int g_adx_M30   = INVALID_HANDLE;
int g_adx_H4    = INVALID_HANDLE;
// MA 핸들
int g_ma_M5     = INVALID_HANDLE;
int g_ma_M30    = INVALID_HANDLE;
int g_ma_H4     = INVALID_HANDLE;
// Bands 핸들
int g_bands_M5  = INVALID_HANDLE;
int g_bands_M30 = INVALID_HANDLE;
int g_bands_H4  = INVALID_HANDLE;

// 새 봉 확인 함수
bool IsNewBar()
{
   datetime current_time = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(current_time != g_last_bar_time)
   {
      g_last_bar_time = current_time;
      return true;
   }
   return false;
}

// 폴더 존재/생성
bool DirExists(string path, int flags=0)
{
   return FileIsExist(path+"\\*.*", flags);
}

bool MakeDir(string path, bool common=false)
{
   int flags = common ? FILE_COMMON : 0;
   if(DirExists(path, flags)) return true;
   return FolderCreate(path, flags);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo("=== NAS100 MTF Regime Backtest EA 초기화 시작 ===");
   LogInfo("TestID: " + TestID + ", Magic: " + IntegerToString(InpMagic));
   
   // ── 1) 로거 초기화 ─────────────────────────────────────────
   string log_file = (LogFileName == "") 
        ? StringFormat("NAS100_%s_%s.log", Symbol(), EnumToString(Period()))
        : LogFileName;

   if(!LoggerInit(LogLevel, (ENUM_LOG_MODE)LogMode, log_file))
   {
      Print("로거 초기화 실패");
      return INIT_FAILED;
   }
   
      // ── 2) 전역 지표 핸들 초기화 ────────────────────────────────
   g_atr_M5    = iATR (Symbol(), PERIOD_M5,  ATR_Period);
   g_atr_M30   = iATR (Symbol(), PERIOD_M30, ATR_Period);
   g_atr_H4    = iATR (Symbol(), PERIOD_H4,  ATR_Period);

   g_rsi_M5    = iRSI (Symbol(), PERIOD_M5,  RSI_Period, PRICE_CLOSE);
   g_rsi_M30   = iRSI (Symbol(), PERIOD_M30, RSI_Period, PRICE_CLOSE);
   g_rsi_H4    = iRSI (Symbol(), PERIOD_H4,  RSI_Period, PRICE_CLOSE);

   g_adx_M5    = iADX (Symbol(), PERIOD_M5,  ADX_Period);
   g_adx_M30   = iADX (Symbol(), PERIOD_M30, ADX_Period);
   g_adx_H4    = iADX (Symbol(), PERIOD_H4,  ADX_Period);

   g_ma_M5     = iMA  (Symbol(), PERIOD_M5,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_ma_M30    = iMA  (Symbol(), PERIOD_M30, MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_ma_H4     = iMA  (Symbol(), PERIOD_H4,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);

   g_bands_M5  = iBands(Symbol(), PERIOD_M5,  Bands_Period, Bands_Deviation, 0, PRICE_CLOSE);
   g_bands_M30 = iBands(Symbol(), PERIOD_M30, Bands_Period, Bands_Deviation, 0, PRICE_CLOSE);
   g_bands_H4  = iBands(Symbol(), PERIOD_H4,  Bands_Period, Bands_Deviation, 0, PRICE_CLOSE);

   // 핸들 생성 실패 체크
   if(
      g_atr_M5    == INVALID_HANDLE || g_atr_M30   == INVALID_HANDLE || g_atr_H4    == INVALID_HANDLE ||
      g_rsi_M5    == INVALID_HANDLE || g_rsi_M30   == INVALID_HANDLE || g_rsi_H4    == INVALID_HANDLE ||
      g_adx_M5    == INVALID_HANDLE || g_adx_M30   == INVALID_HANDLE || g_adx_H4    == INVALID_HANDLE ||
      g_ma_M5     == INVALID_HANDLE || g_ma_M30    == INVALID_HANDLE || g_ma_H4     == INVALID_HANDLE ||
      g_bands_M5  == INVALID_HANDLE || g_bands_M30 == INVALID_HANDLE || g_bands_H4  == INVALID_HANDLE
   )
   {
      LogError("전역 지표 핸들 생성 실패");
      return INIT_FAILED;
   }
   LogInfo("✓ 전역 ATR/RSI/ADX/MA/Bands 핸들 초기화 완료");
   
   // ── 3) 세션 관리자 초기화 ────────────────────────────────────
   g_session_manager = new CSessionManager();
   if(!g_session_manager)
   {
      LogError("SessionManager 생성 실패");
      return INIT_FAILED;
   }
   
   g_session_manager.Update();
   LogInfo("✓ SessionManager 초기화 완료");

   // ── 4) 다중 타임프레임 관리자 초기화 ──────────────────────────
   g_mtf_manager = new CMultiTimeframeManager(Symbol(), g_session_manager);
   if(!g_mtf_manager)
   {
      LogError("MultiTimeframeManager 생성 실패");
      delete g_session_manager;
      return INIT_FAILED;
   }

   // 기본 타임프레임 조합 설정 (사용자 설정 우선)
   STimeframeCombo combo;
   combo.primary_tf = Primary_TF;
   combo.confirm_tf = Confirm_TF;
   combo.filter_tf  = Filter_TF;
   
   if(Use_Custom_Weights)
   {
      combo.weights[0] = Primary_Weight;
      combo.weights[1] = Confirm_Weight;
      combo.weights[2] = Filter_Weight;
      LogInfo("사용자 정의 가중치 사용");
   }
   else
   {
      // 세션별 최적화된 가중치 사용
      combo.weights[0] = 0.3;
      combo.weights[1] = 0.4;
      combo.weights[2] = 0.3;
      LogInfo("기본 가중치 사용");
   }

   g_mtf_manager.SetTimeframeCombo(combo);

   if(!g_mtf_manager.Initialize())
   {
      LogError("MultiTimeframeManager 초기화 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      return INIT_FAILED;
   }
   
   LogInfo("✓ MultiTimeframeManager 초기화 완료");

   // ── 5) 레짐 감지기 초기화 ────────────────────────────────────
   g_regime_detector = new CRegimeDetector(Symbol(), g_mtf_manager, g_session_manager);
   if(!g_regime_detector)
   {
      LogError("RegimeDetector 생성 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      return INIT_FAILED;
   }

   if(!g_regime_detector.Initialize())
   {
      LogError("RegimeDetector 초기화 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      delete g_regime_detector;
      return INIT_FAILED;
   }

   // 레짐 감지기 파라미터 설정
   g_regime_detector.SetHysteresisParameters(Hysteresis_Threshold, Hysteresis_Bars);
   g_regime_detector.AdjustThresholds(Regime_Threshold);
   g_regime_detector.SetRegimeWeights(Trend_Weight, Momentum_Weight, 
                                      Volatility_Weight, Volume_Weight);
   g_regime_detector.SetIndicatorParameters(ADX_Period, RSI_Period, MA_Period,
                                            ATR_Period, Bands_Period, Bands_Deviation);
   g_regime_detector.SetRSIBounds(RSI_Oversold, RSI_Overbought);

   // 세션별 전략 모드 설정
   if(Auto_Mode_By_Session)
   {
      if(g_session_manager.GetCurrentSession() == SESSION_US)
         g_regime_detector.SetStrategyMode(RD_MODE_AGGRESSIVE);
      else
         g_regime_detector.SetStrategyMode(RD_MODE_STABLE);
   }
   else
   {
      g_regime_detector.SetStrategyMode(RD_MODE_STABLE); // 기본값
   }
   
   LogInfo("✓ RegimeDetector 초기화 완료");

   // ── 6) 실행 관리자 초기화 ────────────────────────────────────
   g_execution_manager = new CExecutionManager(Symbol(), InpMagic, 3, 1000);
   if(!g_execution_manager)
   {
      LogError("ExecutionManager 생성 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      delete g_regime_detector;
      return INIT_FAILED;
   }
   
   if(!g_execution_manager.Initialize())
   {
      LogError("ExecutionManager 초기화 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      delete g_regime_detector;
      delete g_execution_manager;
      return INIT_FAILED;
   }
   
   LogInfo("✓ ExecutionManager 초기화 완료");

   // ── 7) 리스크 관리자 초기화 ──────────────────────────────────
   g_risk_manager = new CRiskManager(Symbol(), InpMagic);
   if(!g_risk_manager)
   {
      LogError("RiskManager 생성 실패");
      delete g_session_manager;
      delete g_mtf_manager;
      delete g_regime_detector;
      delete g_execution_manager;
      return INIT_FAILED;
   }
   
   // 리스크 파라미터 설정
   SRiskParameters risk_params;
   risk_params.risk_type = RiskType;
   risk_params.risk_value = RiskValue;
   risk_params.risk_reward_ratio = RiskRewardRatio;
   risk_params.max_risk_per_trade = MaxRiskPerTrade;
   risk_params.max_risk_total = MaxRiskTotal;
   risk_params.max_positions = MaxPositions;
   risk_params.adjust_by_regime_confidence = AdjustByRegimeConfidence;
   risk_params.margin_safety_percent = MarginSafetyPercent;
   
   g_risk_manager.SetRiskParameters(risk_params);
   
   LogInfo("✓ RiskManager 초기화 완료");

   // ── 8) 전략 선택기 초기화 (옵션) ──────────────────────────────
   if(UseStrategySelector)
   {
      g_strategy_selector = new CStrategySelector(Symbol(), g_regime_detector, 
                                                 g_session_manager, g_risk_manager, InpMagic);
      if(!g_strategy_selector)
      {
         LogError("StrategySelector 생성 실패");
         delete g_session_manager;
         delete g_mtf_manager;
         delete g_regime_detector;
         delete g_execution_manager;
         delete g_risk_manager;
         return INIT_FAILED;
      }
      
      if(!g_strategy_selector.Initialize())
      {
         LogError("StrategySelector 초기화 실패");
         delete g_session_manager;
         delete g_mtf_manager;
         delete g_regime_detector;
         delete g_execution_manager;
         delete g_risk_manager;
         delete g_strategy_selector;
         return INIT_FAILED;
      }
      
      LogInfo("✓ StrategySelector 초기화 완료");
   }
   else
   {
      LogInfo("✓ StrategySelector 사용 안함 (기본 레짐 로직 사용)");
   }

   // ── 9) CSV 파일 준비 ────────────────────────────────────────
   if(Save_Results_To_CSV)
   {
      string filename = TestID + "_" + Symbol() + ".csv";
      string filepath;
      int flags = FILE_WRITE | FILE_CSV | FILE_REWRITE;

      if(Use_Custom_Path && StringLen(Custom_CSV_Path) > 0)
      {
         if(!MakeDir(Custom_CSV_Path, true))
            LogError("디렉토리 생성 실패: " + Custom_CSV_Path);

         filepath = Custom_CSV_Path;
         if(filepath[StringLen(filepath)-1] != '\\' && filepath[StringLen(filepath)-1] != '/')
            filepath += "/";
         filepath += filename;
         flags |= FILE_COMMON;
      }
      else
      {
         filepath = (StringLen(CSV_Subfolder) > 0) 
                    ? (CSV_Subfolder + "/" + filename)
                    : filename;

         if(StringLen(CSV_Subfolder) > 0 && !MakeDir(CSV_Subfolder, false))
            LogError("서브폴더 생성 실패: " + CSV_Subfolder);
      }

      g_csv_filename = filepath;
      file_handle = FileOpen(filepath, flags);
      if(file_handle != INVALID_HANDLE)
      {
         // CSV 헤더 작성
         FileWrite(file_handle,
                   "Date", "Time", "Regime", "Confidence",
                   "Score_Bull", "Score_Bear", "Score_Cons", "Score_Vola",
                   "Score_Drift", "Score_Gap", "Score_Rev",
                   "Price", "Session",
                   "ADX", "RSI", "ATR", "Volume_Ratio",
                   "Position_Type", "Position_Volume", "Total_Risk_Percent",
                   "Support_Level", "Resistance_Level", "Gap_Direction");
         
         LogInfo("✓ CSV 파일 준비 완료: " + filepath);
      }
      else
      {
         LogError("CSV 파일 열기 실패: " + filepath);
      }
   }

   // ── 10) 타이머 설정 ─────────────────────────────────────────
   EventSetTimer(1);  // 1초 주기 타이머
   
   // ── 11) 초기 레벨 업데이트 ───────────────────────────────────
   UpdateLevels();

   LogInfo("🔧 NAS100 MTF Regime Backtest EA 초기화 완료");
   LogInfo("현재 세션: " + GetSessionNameStr(g_session_manager.GetCurrentSession()));
   LogInfo("전략 선택기 사용: " + (UseStrategySelector ? "예" : "아니오"));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogInfo("=== EA 종료 시작, reason=" + IntegerToString(reason) + " ===");
   
   // 타이머 종료
   EventKillTimer();
   
   // CSV 파일 닫기
   if(file_handle != INVALID_HANDLE)
   { 
      FileClose(file_handle); 
      file_handle = INVALID_HANDLE; 
   }

   // UI 객체 정리
   if(Show_Dashboard) ObjectsDeleteAll(0, "dashboard_");
   if(Mark_Regime_Changes) ObjectsDeleteAll(0, "regime_marker_");

   // 객체들 정리 (역순으로)
   if(g_strategy_selector)
   {
      delete g_strategy_selector;
      g_strategy_selector = NULL;
   }
   
   if(g_risk_manager)
   {
      delete g_risk_manager;
      g_risk_manager = NULL;
   }
   
   if(g_execution_manager)
   {
      g_execution_manager.Deinitialize();
      delete g_execution_manager;
      g_execution_manager = NULL;
   }
   
   if(g_regime_detector)
   {
      delete g_regime_detector;
      g_regime_detector = NULL;
   }
   
   if(g_mtf_manager)
   {
      delete g_mtf_manager;
      g_mtf_manager = NULL;
   }
   
   if(g_session_manager)
   {
      delete g_session_manager;
      g_session_manager = NULL;
   }

      // 전역 핸들 해제
   if(g_atr_M5    != INVALID_HANDLE) IndicatorRelease(g_atr_M5);
   if(g_atr_M30   != INVALID_HANDLE) IndicatorRelease(g_atr_M30);
   if(g_atr_H4    != INVALID_HANDLE) IndicatorRelease(g_atr_H4);

   if(g_rsi_M5    != INVALID_HANDLE) IndicatorRelease(g_rsi_M5);
   if(g_rsi_M30   != INVALID_HANDLE) IndicatorRelease(g_rsi_M30);
   if(g_rsi_H4    != INVALID_HANDLE) IndicatorRelease(g_rsi_H4);

   if(g_adx_M5    != INVALID_HANDLE) IndicatorRelease(g_adx_M5);
   if(g_adx_M30   != INVALID_HANDLE) IndicatorRelease(g_adx_M30);
   if(g_adx_H4    != INVALID_HANDLE) IndicatorRelease(g_adx_H4);

   if(g_ma_M5     != INVALID_HANDLE) IndicatorRelease(g_ma_M5);
   if(g_ma_M30    != INVALID_HANDLE) IndicatorRelease(g_ma_M30);
   if(g_ma_H4     != INVALID_HANDLE) IndicatorRelease(g_ma_H4);

   if(g_bands_M5  != INVALID_HANDLE) IndicatorRelease(g_bands_M5);
   if(g_bands_M30 != INVALID_HANDLE) IndicatorRelease(g_bands_M30);
   if(g_bands_H4  != INVALID_HANDLE) IndicatorRelease(g_bands_H4);

   // 확장 핸들 해제
   ReleaseIndicatorHandles();
   
   // 로거 종료
   LoggerShutdown();
   
   LogInfo("🔧 리소스 해제 완료");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 포지션 상태 동기화 (1초마다)
   static datetime last_sync_time = 0;
   datetime current_time = TimeCurrent();
   
   if(current_time - last_sync_time >= 1)
   {
      if(g_execution_manager)
         g_execution_manager.SyncPositionState();
      last_sync_time = current_time;
   }
   
   // 새 봉이 아닐 때는 즉시 종료
   if(!IsNewBar()) return;
   
   // 레벨 및 지표 업데이트
   UpdateLevels();
   
   // ── 1) 세션 변화 감시 및 파라미터 조정 ──────────────────────
   static ESessionType prev_session = SESSION_UNKNOWN;
   if(g_session_manager)
   {
      g_session_manager.Update();
      ESessionType cur_session = g_session_manager.GetCurrentSession();

      if(cur_session != prev_session)
      {
          // 세션 변경 로그
          LogInfo("세션 변경: " 
              + GetSessionNameStr(prev_session) 
              + " → " 
              + GetSessionNameStr(cur_session));
    
          // 사용자 정의 가중치를 사용하지 않는 경우에만 세션별 최적화
          if(!Use_Custom_Weights)
          {
              STimeframeCombo combo = 
                  g_session_manager.GetOptimalTimeframeCombo(1.0);
              g_mtf_manager.SetTimeframeCombo(combo);
              LogInfo("세션별 타임프레임 가중치 적용");
          }
    
          // 세션별 전략 모드 조정
          if(Auto_Mode_By_Session)
          {
              if(cur_session == SESSION_US)
                  g_regime_detector.SetStrategyMode(RD_MODE_AGGRESSIVE);
              else
                  g_regime_detector.SetStrategyMode(RD_MODE_STABLE);
          }
    
         // 이전 세션 갱신
          prev_session = cur_session;
      }
   }

   // ── 2) 레짐 감지 업데이트 (실패해도 계속 진행) ──────────────────
   SRegimeData regime;
   regime.dominant_regime = REGIME_UNKNOWN;
   
   if(g_regime_detector && g_regime_detector.Update())
   {
      regime = g_regime_detector.GetCurrentRegime();
   }
   else
   {
      LogWarning("레짐 감지 업데이트 실패 - 이전 레짐 유지");
      // 이전 레짐 유지하거나 기본값 사용
      regime.dominant_regime = g_last_regime;
      regime.confidence = 0.3; // 낮은 신뢰도로 설정
   }
   
   double price = iClose(Symbol(), PERIOD_CURRENT, 0);

   // ── 3) 전략 선택기 업데이트 (옵션) ────────────────────────────
   bool strategy_changed = false;
   if(UseStrategySelector)
   {
      // 포인터라 NULL 체크가 필요하다면
      if(g_strategy_selector != NULL)
      {
         strategy_changed = g_strategy_selector.Update();
         if(strategy_changed)
            LogInfo("전략 변경됨: " + g_strategy_selector.GetStrategyName());
      }
      else
      {
         LogError("Update: g_strategy_selector is NULL");
      }
   }

   // ── 4) CSV 기록 ───────────────────────────────────────────
   if(Save_Results_To_CSV && file_handle != INVALID_HANDLE)
   {
      WriteCSVRecord(regime, price);
   }

   // ── 5) 거래 로직 실행 ──────────────────────────────────────
   if(g_execution_manager && g_risk_manager)
   {
      ExecuteTradingLogic(regime, price);
   }

   // ── 6) UI 업데이트 ────────────────────────────────────────
   if(Show_Dashboard) 
   {
      UpdateDashboard(regime);
   }

   if(Mark_Regime_Changes && g_last_regime != regime.dominant_regime)
   {
      MarkRegimeChange(regime);
      g_last_regime = regime.dominant_regime;
   }

   // ── 7) 로깅 ──────────────────────────────────────────────
   LogInfo("레짐: " + GetRegimeNameStr(regime.dominant_regime) + 
          " (신뢰도 " + DoubleToString(regime.confidence * 100, 1) + "%)");
   
   // 히스테리시스 적용 여부 확인
   if(g_regime_detector)
   {
      g_was_hysteresis_applied = g_regime_detector.WasHysteresisApplied();
      if(g_was_hysteresis_applied)
      {
         LogDebug("히스테리시스 적용됨 - 레짐 유지: " + GetRegimeNameStr(regime.dominant_regime));
      }
   }
}

//+------------------------------------------------------------------+
//| CSV 기록 함수                                                    |
//+------------------------------------------------------------------+
void WriteCSVRecord(const SRegimeData &regime, double price)
{
   // 지표 값 수집 (수정된 방식)
   double adx = 0, rsi = 0, atr = 0, vol_ratio = 1.0;
   
   // 전역 핸들에서 직접 가져오기
   double atr_buf[1], rsi_buf[1];
   
   if(CopyBuffer(g_rsi_M5, 0, 1, 1, atr_buf) > 0)
      atr = atr_buf[0];
   
   if(CopyBuffer(g_rsi_M5, 0, 1, 1, rsi_buf) > 0)
      rsi = rsi_buf[0];
   
   // ADX는 임시로 기본값 사용 (RegimeDetector 내부 값 활용 가능)
   adx = 25.0; // 기본값
   
   // 거래량 비율 계산
   long volumes[10];
   if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, 10, volumes) > 0)
   {
      double avg_vol = 0;
      for(int i = 1; i < 10; i++) avg_vol += volumes[i];
      avg_vol /= 9.0;
      vol_ratio = (avg_vol > 0) ? (double)volumes[0] / avg_vol : 1.0;
   }

   // 현재 시간
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // 포지션 정보
   string position_type = "NONE";
   double position_volume = 0.0;
   
   if(g_execution_manager && g_execution_manager.HasOpenPosition())
   {
      if(PositionSelect(Symbol()))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(pos_magic == InpMagic)
         {
            long pos_type = PositionGetInteger(POSITION_TYPE);
            position_type = (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            position_volume = PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   // 총 리스크 계산
   double total_risk = 0.0;
   if(g_risk_manager)
   {
      total_risk = g_risk_manager.GetTotalRiskPercent();
   }

   // CSV 레코드 작성
   FileWrite(file_handle,
             StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day),
             StringFormat("%02d:%02d", dt.hour, dt.min),
             GetRegimeNameStr(regime.dominant_regime),
             DoubleToString(regime.confidence, 2),
             DoubleToString(regime.regime_scores[REGIME_STRONG_BULLISH], 2),
             DoubleToString(regime.regime_scores[REGIME_STRONG_BEARISH], 2),
             DoubleToString(regime.regime_scores[REGIME_CONSOLIDATION], 2),
             DoubleToString(regime.regime_scores[REGIME_VOLATILITY_EXPANSION], 2),
             DoubleToString(regime.regime_scores[REGIME_OVERNIGHT_DRIFT], 2),
             DoubleToString(regime.regime_scores[REGIME_GAP_TRADING], 2),
             DoubleToString(regime.regime_scores[REGIME_TECHNICAL_REVERSAL], 2),
             DoubleToString(price, _Digits),
             GetSessionNameStr(g_session_manager.GetCurrentSession()),
             DoubleToString(adx, 1),
             DoubleToString(rsi, 1),
             DoubleToString(atr, 5),
             DoubleToString(vol_ratio, 2),
             position_type,
             DoubleToString(position_volume, 2),
             DoubleToString(total_risk, 2),
             DoubleToString(SupportLevel, _Digits),
             DoubleToString(ResistanceLevel, _Digits),
             DoubleToString(GapDirection, 1));
}

//+------------------------------------------------------------------+
//| 거래 로직 실행 함수                                              |
//+------------------------------------------------------------------+
void ExecuteTradingLogic(const SRegimeData &regime, double price)
{
   if(UseStrategySelector)
      ExecuteWithStrategySelector(regime, price);
   else
      ExecuteBasicRegimeTrading(regime, price);
}


//+------------------------------------------------------------------+
//| 전략 선택기 기반 거래 실행                                        |
//+------------------------------------------------------------------+
void ExecuteWithStrategySelector(const SRegimeData &regime, double price)
{
   // 포지션 상태 재확인
   g_execution_manager.SyncPositionState();
   
   // 진입 신호 확인
   if(!g_execution_manager.HasOpenPosition())
   {
      SEntrySignal entry_signal = g_strategy_selector.GetEntrySignal();
      
      if(entry_signal.valid)
      {
         LogInfo("전략 선택기 진입 신호: " + 
                (entry_signal.direction == ORDER_TYPE_BUY ? "매수" : "매도") +
                ", 가격=" + DoubleToString(entry_signal.entry_price, _Digits) +
                ", 수량=" + DoubleToString(entry_signal.volume, 2));
         
         // 리스크 검증
         if(g_risk_manager.IsRiskAcceptable(entry_signal.entry_price, 
                                           entry_signal.stop_loss, 
                                           entry_signal.volume))
         {
            if(g_execution_manager.OpenPosition(entry_signal.direction,
                                              entry_signal.volume,
                                              entry_signal.entry_price,
                                              entry_signal.stop_loss,
                                              entry_signal.take_profit,
                                              entry_signal.comment))
            {
               LogInfo("전략 선택기 진입 성공: " + entry_signal.signal_id);
            }
            else
            {
               LogError("전략 선택기 진입 실패: " + entry_signal.signal_id);
            }
         }
         else
         {
            LogWarning("전략 선택기 리스크 제약으로 진입 취소: " + entry_signal.signal_id);
         }
      }
   }
   else
   {
      // 청산 신호 확인
      SExitSignal exit_signal = g_strategy_selector.GetExitSignal();
      
      if(exit_signal.valid)
      {
         LogInfo("전략 선택기 청산 신호: " + exit_signal.reason +
                ", 가격=" + DoubleToString(exit_signal.exit_price, _Digits));
         
         if(exit_signal.partial_ratio > 0 && exit_signal.partial_ratio < 1.0)
         {
            // 부분 청산 (향후 구현)
            LogInfo("부분 청산 신호 (미구현): " + 
                   DoubleToString(exit_signal.partial_ratio * 100, 0) + "%");
         }
         else
         {
            // 전체 청산
            if(g_execution_manager.ClosePosition())
            {
               LogInfo("전략 선택기 청산 성공: " + exit_signal.signal_id);
            }
            else
            {
               LogError("전략 선택기 청산 실패: " + exit_signal.signal_id);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 기본 레짐 기반 거래 실행                                          |
//+------------------------------------------------------------------+
void ExecuteBasicRegimeTrading(const SRegimeData &regime, double price)
{
   // 신뢰도가 너무 낮으면 거래하지 않음
   if(regime.confidence < 0.4)
   {
      LogDebug("레짐 신뢰도 부족 (" + DoubleToString(regime.confidence, 2) + ") - 거래 건너뜀");
      return;
   }
   
   // 세션별 리스크 조정
   ESessionType current_session = g_session_manager.GetCurrentSession();
   double session_risk_multiplier = GetSessionRiskMultiplier(current_session);
   
   // 레짐별 리스크 파라미터 조정
   SRiskParameters current_params = GetRiskParamsByRegime(regime.dominant_regime, 
                                                         session_risk_multiplier);
   g_risk_manager.SetRiskParameters(current_params);

   // 포지션 상태 재확인
   g_execution_manager.SyncPositionState();

   // 레짐별 거래 로직 실행
   switch(regime.dominant_regime)
   {
      case REGIME_STRONG_BULLISH:
         ExecuteBullishMomentumTrading(regime, price);
         break;
         
      case REGIME_STRONG_BEARISH:
         ExecuteBearishMomentumTrading(regime, price);
         break;
         
      case REGIME_CONSOLIDATION:
         ExecuteRangeTrading(regime, price);
         break;
         
      case REGIME_VOLATILITY_EXPANSION:
         ExecuteBreakoutTrading(regime, price);
         break;
         
      case REGIME_OVERNIGHT_DRIFT:
         ExecuteDriftTrading(regime, price);
         break;
         
      case REGIME_GAP_TRADING:
         ExecuteGapTrading(regime, price);
         break;
         
      case REGIME_TECHNICAL_REVERSAL:
         ExecuteReversalTrading(regime, price);
         break;
         
      default:
         // 알 수 없는 레짐에서는 기존 포지션 관리만
         ManageUnknownRegime(regime, price);
         break;
   }
}

//+------------------------------------------------------------------+
//| 세션별 리스크 승수 반환                                           |
//+------------------------------------------------------------------+
double GetSessionRiskMultiplier(ESessionType session)
{
   switch(session)
   {
      case SESSION_ASIA:   return 0.8;  // 낮은 변동성
      case SESSION_EUROPE: return 1.0;  // 표준
      case SESSION_US:     return 1.2;  // 높은 변동성
      default:             return 0.5;  // 알 수 없는 세션
   }
}

//+------------------------------------------------------------------+
//| 레짐별 리스크 파라미터 반환                                       |
//+------------------------------------------------------------------+
SRiskParameters GetRiskParamsByRegime(ENUM_MARKET_REGIME regime, double session_multiplier)
{
   SRiskParameters params;
   params.risk_type = RiskType;
   params.adjust_by_regime_confidence = AdjustByRegimeConfidence;
   params.margin_safety_percent = MarginSafetyPercent;
   params.max_positions = MaxPositions;
   params.max_risk_per_trade = MaxRiskPerTrade;
   params.max_risk_total = MaxRiskTotal;
   
   // 레짐별 세부 조정
   switch(regime)
   {
      case REGIME_STRONG_BULLISH:
      case REGIME_STRONG_BEARISH:
         params.risk_value = RiskValue * session_multiplier * 1.0;
         params.risk_reward_ratio = 2.0;
         break;
         
      case REGIME_VOLATILITY_EXPANSION:
         params.risk_value = RiskValue * session_multiplier * 0.8;
         params.risk_reward_ratio = 3.0;
         break;
         
      case REGIME_CONSOLIDATION:
         params.risk_value = RiskValue * session_multiplier * 0.9;
         params.risk_reward_ratio = 1.5;
         break;
         
      case REGIME_OVERNIGHT_DRIFT:
         params.risk_value = RiskValue * session_multiplier * 0.7;
         params.risk_reward_ratio = 1.5;
         break;
         
      case REGIME_GAP_TRADING:
         params.risk_value = RiskValue * session_multiplier * 0.8;
         params.risk_reward_ratio = 2.0;
         break;
         
      case REGIME_TECHNICAL_REVERSAL:
         params.risk_value = RiskValue * session_multiplier * 1.0;
         params.risk_reward_ratio = 2.5;
         break;
         
      default:
         params.risk_value = RiskValue * session_multiplier * 0.5; // 불확실한 레짐
         params.risk_reward_ratio = RiskRewardRatio;
   }
   
   return params;
}

//+------------------------------------------------------------------+
//| 강한 상승 모멘텀 거래                                             |
//+------------------------------------------------------------------+
void ExecuteBullishMomentumTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      double entry_price = price;
      double stop_loss = entry_price - InpSL_Pips;
      double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                    regime.dominant_regime, 
                                                    regime.confidence);
      double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                             ORDER_TYPE_BUY);
      
      if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
      {
         if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                            stop_loss, take_profit, 
                                            "BullMomentum_" + DoubleToString(regime.confidence, 2)))
         {
            LogInfo("강한 상승 모멘텀 매수 성공: 볼륨=" + DoubleToString(volume, 2));
         }
         else
         {
            LogError("강한 상승 모멘텀 매수 실패");
         }
      }
      else
      {
         LogWarning("강한 상승 모멘텀 리스크 제약으로 매수 취소");
      }
   }
}

//+------------------------------------------------------------------+
//| 강한 하락 모멘텀 거래                                             |
//+------------------------------------------------------------------+
void ExecuteBearishMomentumTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      double entry_price = price;
      double stop_loss = price + InpSL_Pips * Point();
      double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                    regime.dominant_regime, 
                                                    regime.confidence);
      double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                             ORDER_TYPE_SELL);
      
      if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
      {
         if(g_execution_manager.OpenPosition(ORDER_TYPE_SELL, volume, entry_price,
                                            stop_loss, take_profit, 
                                            "BearMomentum_" + DoubleToString(regime.confidence, 2)))
         {
            LogInfo("강한 하락 모멘텀 매도 성공: 볼륨=" + DoubleToString(volume, 2));
         }
         else
         {
            LogError("강한 하락 모멘텀 매도 실패");
         }
      }
      else
      {
         LogWarning("강한 하락 모멘텀 리스크 제약으로 매도 취소");
      }
   }
}

//+------------------------------------------------------------------+
//| 레인지 거래                                                      |
//+------------------------------------------------------------------+
void ExecuteRangeTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      if(price <= SupportLevel && SupportLevel > 0)
      {
         // 지지선 근처에서 매수
         double entry_price = price;
         double stop_loss = SupportLevel - InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = ResistanceLevel;
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "RangeLong_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("레인지 하단 매수 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
      else if(price >= ResistanceLevel && ResistanceLevel > 0)
      {
         // 저항선 근처에서 매도
         double entry_price = price;
         double stop_loss = ResistanceLevel + InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = SupportLevel;
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_SELL, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "RangeShort_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("레인지 상단 매도 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
   }
   else
   {
      // 레인지 이탈 시 청산
      if((SupportLevel > 0 && price < SupportLevel) || 
         (ResistanceLevel > 0 && price > ResistanceLevel))
      {
         if(g_execution_manager.ClosePosition())
         {
            LogInfo("레인지 이탈로 청산 성공");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 브레이크아웃 거래                                                 |
//+------------------------------------------------------------------+
void ExecuteBreakoutTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      if(price > BreakoutHigh && BreakoutHigh > 0)
      {
         // 상향 브레이크아웃
         double entry_price = price;
         double stop_loss = BreakoutHigh - InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_BUY);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "BreakoutLong_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("상향 브레이크아웃 매수 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
      else if(price < BreakoutLow && BreakoutLow > 0)
      {
         // 하향 브레이크아웃
         double entry_price = price;
         double stop_loss = BreakoutLow + InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_SELL);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_SELL, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "BreakoutShort_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("하향 브레이크아웃 매도 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 드리프트 거래                                                    |
//+------------------------------------------------------------------+
void ExecuteDriftTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      // 오버나이트 드리프트는 보통 롱 포지션
      double entry_price = price;
      double stop_loss = price - InpSL_Pips * Point();
      double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                    regime.dominant_regime, 
                                                    regime.confidence);
      double take_profit = price + DriftTargetPips * Point();
      
      if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
      {
         if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                            stop_loss, take_profit, 
                                            "DriftLong_" + DoubleToString(regime.confidence, 2)))
         {
            LogInfo("드리프트 매수 성공: 볼륨=" + DoubleToString(volume, 2));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 갭 거래                                                          |
//+------------------------------------------------------------------+
void ExecuteGapTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      if(GapDirection > 0)
      {
         // 갭업 후 매도 (갭 메우기)
         double entry_price = price;
         double stop_loss = price + InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_SELL);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_SELL, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "GapUpShort_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("갭업 매도 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
      else if(GapDirection < 0)
      {
         // 갭다운 후 매수 (갭 메우기)
         double entry_price = price;
         double stop_loss = price - InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_BUY);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "GapDownLong_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("갭다운 매수 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 기술적 되돌림 거래                                                |
//+------------------------------------------------------------------+
void ExecuteReversalTrading(const SRegimeData &regime, double price)
{
   if(!g_execution_manager.HasOpenPosition())
   {
      if(RSI < 30)  // 과매도 → 매수
      {
         double entry_price = price;
         double stop_loss = price - InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_BUY);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_BUY, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "ReversalLong_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("기술적 되돌림 매수 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
      else if(RSI > 70)  // 과매수 → 매도
      {
         double entry_price = price;
         double stop_loss = price + InpSL_Pips * Point();
         double volume = g_risk_manager.GetPositionSize(entry_price, stop_loss, 
                                                       regime.dominant_regime, 
                                                       regime.confidence);
         double take_profit = g_risk_manager.CalculateTakeProfit(entry_price, stop_loss, 
                                                                ORDER_TYPE_SELL);
         
         if(g_risk_manager.IsRiskAcceptable(entry_price, stop_loss, volume))
         {
            if(g_execution_manager.OpenPosition(ORDER_TYPE_SELL, volume, entry_price,
                                               stop_loss, take_profit, 
                                               "ReversalShort_" + DoubleToString(regime.confidence, 2)))
            {
               LogInfo("기술적 되돌림 매도 성공: 볼륨=" + DoubleToString(volume, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 알 수 없는 레짐 관리                                              |
//+------------------------------------------------------------------+
void ManageUnknownRegime(const SRegimeData &regime, double price)
{
   if(g_execution_manager.HasOpenPosition())
   {
      if(regime.confidence < 0.3)  // 매우 낮은 신뢰도에서 청산 고려
      {
         if(g_execution_manager.ClosePosition())
         {
            LogInfo("불확실한 레짐에서 청산 성공 (신뢰도: " + 
                   DoubleToString(regime.confidence, 2) + ")");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 레벨 및 지표 업데이트                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 레벨 및 지표 업데이트                                          |
//+------------------------------------------------------------------+
void UpdateLevels()
{
    // --- ATR 값 가져오기 (Primary_TF, 예: M5 전용 핸들 사용) ---
    double atr_buf[1];
    double atr = 0.0; 
    
    if (g_atr_M5 != INVALID_HANDLE) {
        int calculated_bars = BarsCalculated(g_atr_M5);
        LogInfo(StringFormat("UpdateLevels: g_atr_M5 (PERIOD_M5) BarsCalculated: %d. ATR_Period (EA input): %d", 
                             calculated_bars, ATR_Period));
        if (calculated_bars < ATR_Period) {
            LogWarning("UpdateLevels: g_atr_M5 (PERIOD_M5) - Not enough bars calculated for ATR period.");
        }

        if(CopyBuffer(g_atr_M5, 0, 1, 1, atr_buf) == 1) {
            atr = atr_buf[0];
        } else {
            int error_code = GetLastError();
            LogWarning(StringFormat("ATR 데이터 가져오기 실패 (Primary TF: M5, Handle: %d). Error: %d", 
                                    g_atr_M5, error_code)); // GetErrorDescription 호출 부분은 일단 숫자만 출력하도록 수정
        }
    } else {
        LogWarning("UpdateLevels: g_atr_M5 handle is INVALID_HANDLE before CopyBuffer.");
    }

    // --- 지지/저항 레벨 계산 ---
    double recent_high = iHigh(Symbol(), PERIOD_CURRENT, iHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, SR_LookbackBars, 1));
    double recent_low  = iLow(Symbol(), PERIOD_CURRENT, iLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, SR_LookbackBars, 1));

    // ATR 값 유효성 검사 수정: 0보다 크고, EMPTY_VALUE가 아니며, 비정상적으로 크지 않은 값 (예: 현재 가격의 절반 이하)
    double current_price_for_atr_check = SymbolInfoDouble(Symbol(), SYMBOL_BID); // 현재가 참조
    if (atr > Point() && atr != DBL_MAX && atr < current_price_for_atr_check * 0.5) { // Point()보다 커야 의미 있음, 가격의 50% 이상은 비정상으로 간주 (이 비율은 조절 가능)
        SupportLevel  = recent_low  - SR_ATR_Multiplier * atr;
        ResistanceLevel = recent_high + SR_ATR_Multiplier * atr;
    } else {
        LogWarning(StringFormat("UpdateLevels: 유효하지 않은 ATR 값(%.5f)으로 S/R 레벨 계산 건너뜀. 현재가: %.5f", atr, current_price_for_atr_check));
        // SupportLevel, ResistanceLevel은 이전 값을 유지하거나, ATR 없이 (SR_ATR_Multiplier = 0 으로 간주) 계산
        // 여기서는 이전 값을 유지한다고 가정 (별도 처리 없으면 이전 값 유지됨)
    }

    // --- 브레이크아웃 레벨 계산 ---
    BreakoutHigh = iHigh(Symbol(), PERIOD_CURRENT, iHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, Breakout_LookbackBars, 1));
    BreakoutLow  = iLow(Symbol(), PERIOD_CURRENT, iLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, Breakout_LookbackBars, 1));

    // --- 갭 방향 계산 ---
    double today_open      = iOpen(Symbol(), PERIOD_D1, 0);
    double yesterday_close = iClose(Symbol(), PERIOD_D1, 1);
    
    if(today_open != 0 && yesterday_close != 0) { 
        GapDirection = (today_open > yesterday_close) ?  1.0 :
                       (today_open < yesterday_close) ? -1.0 : 0.0;
    } else {
        LogWarning("UpdateLevels: 일일 시가/종가 데이터 부족으로 갭 방향 계산 불가.");
        GapDirection = 0.0;
    }

    // --- RSI 값 가져오기 (Primary_TF, 예: M5 전용 핸들 사용) ---
    double rsi_buf[1];
    
    if (g_rsi_M5 != INVALID_HANDLE) {
        int calculated_bars_rsi = BarsCalculated(g_rsi_M5);
        LogInfo(StringFormat("UpdateLevels: g_rsi_M5 (PERIOD_M5) BarsCalculated: %d. RSI_Period (EA input): %d", 
                             calculated_bars_rsi, RSI_Period));
        if (calculated_bars_rsi < RSI_Period) {
             LogWarning("UpdateLevels: g_rsi_M5 (PERIOD_M5) - Not enough bars calculated for RSI period.");
        }

        if(CopyBuffer(g_rsi_M5, 0, 1, 1, rsi_buf) == 1) {
            RSI = rsi_buf[0]; 
        } else {
            int error_code_rsi = GetLastError();
            LogWarning(StringFormat("RSI 데이터 가져오기 실패 (Primary TF: M5, Handle: %d). Error: %d", 
                                     g_rsi_M5, error_code_rsi));
        }
    } else {
        LogWarning("UpdateLevels: g_rsi_M5 handle is INVALID_HANDLE before CopyBuffer.");
    }
}


//+------------------------------------------------------------------+
//| 대시보드 업데이트                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard(const SRegimeData &r)
{
   ObjectsDeleteAll(0, "dashboard_");

   // 패널 생성
   CreatePanel("dashboard_panel", 10, 10, 240, 200, clrBlack, clrDimGray);

   // 제목
   CreateLabel("dashboard_title", "📊 NAS100 Regime", 20, 18, clrWhite, 11);
   
   // 레짐 정보
   string regime_txt = "Regime: " + GetRegimeNameStr(r.dominant_regime);
   color regime_clr = (r.dominant_regime == REGIME_STRONG_BULLISH) ? clrLime :
                      (r.dominant_regime == REGIME_STRONG_BEARISH) ? clrTomato :
                      (r.dominant_regime == REGIME_VOLATILITY_EXPANSION) ? clrViolet : clrAqua;
   CreateLabel("dashboard_regime", regime_txt, 20, 40, regime_clr, 10);

   // 신뢰도
   string conf_txt = StringFormat("Confidence: %.1f%%", r.confidence * 100);
   color conf_clr = (r.confidence > 0.7) ? clrLime : 
                    (r.confidence > 0.4) ? clrYellow : clrRed;
   CreateLabel("dashboard_conf", conf_txt, 20, 58, conf_clr, 9);

   // 세션 정보
   CreateLabel("dashboard_sess",
               "Session: " + GetSessionNameStr(g_session_manager.GetCurrentSession()),
               20, 74, clrSilver, 8);

   // 포지션 정보
   string pos_info = "Position: ";
   if(g_execution_manager && g_execution_manager.HasOpenPosition())
   {
      if(PositionSelect(Symbol()))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(pos_magic == InpMagic)
         {
            long pos_type = PositionGetInteger(POSITION_TYPE);
            double pos_volume = PositionGetDouble(POSITION_VOLUME);
            pos_info += (pos_type == POSITION_TYPE_BUY ? "BUY " : "SELL ") + 
                       DoubleToString(pos_volume, 2);
         }
         else
         {
            pos_info += "NONE";
         }
      }
      else
      {
         pos_info += "NONE";
      }
   }
   else
   {
      pos_info += "NONE";
   }
   CreateLabel("dashboard_pos", pos_info, 20, 90, clrWhite, 8);

   // 리스크 정보
   double total_risk = g_risk_manager ? g_risk_manager.GetTotalRiskPercent() : 0.0;
   string risk_info = StringFormat("Risk: %.1f%%", total_risk);
   color risk_clr = (total_risk > 8.0) ? clrRed : 
                    (total_risk > 5.0) ? clrOrange : clrLime;
   CreateLabel("dashboard_risk", risk_info, 20, 106, risk_clr, 8);

   // 전략 선택기 정보
   if(UseStrategySelector)
   {
      string strategy_info = "Strategy: " + g_strategy_selector.GetStrategyName();
      CreateLabel("dashboard_strategy", strategy_info, 20, 122, clrCyan, 8);
   }
   else
   {
      CreateLabel("dashboard_strategy", "Strategy: Basic Regime", 20, 122, clrCyan, 8);
   }

   // 레벨 정보
   string level_info = StringFormat("S/R: %.1f / %.1f", SupportLevel, ResistanceLevel);
   CreateLabel("dashboard_levels", level_info, 20, 138, clrGold, 7);

   // 레짐별 점수 미니 바
   int baseY = 156;
   for(int i = 0; i < 8; i++)
   {
      string pre = "dashboard_score_" + IntegerToString(i);
      int barW = (int)(r.regime_scores[i] * 80); // 폭 축소

      CreateRect(pre + "_bg", 160, baseY + i * 10, 80, 8, clrGray);
      CreateRect(pre, 160, baseY + i * 10, barW, 8,
                 (i == (int)r.dominant_regime) ? regime_clr : clrDarkSlateGray);

      CreateLabel(pre + "_lbl",
                  StringSubstr(GetRegimeNameStr((ENUM_MARKET_REGIME)i), 0, 6),
                  20, baseY + i * 10 - 1, clrWhite, 6);
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| 레짐 변경 마커 생성                                               |
//+------------------------------------------------------------------+
void MarkRegimeChange(const SRegimeData &r)
{
   datetime t = TimeCurrent();
   double px = iClose(Symbol(), PERIOD_CURRENT, 0);

   ENUM_OBJECT arrowType;
   color arrowClr;
   
   switch(r.dominant_regime)
   {
      case REGIME_STRONG_BULLISH:
         arrowType = OBJ_ARROW_UP;
         arrowClr = clrLime;
         break;
      case REGIME_STRONG_BEARISH:
         arrowType = OBJ_ARROW_DOWN;
         arrowClr = clrRed;
         break;
      case REGIME_VOLATILITY_EXPANSION:
         arrowType = OBJ_ARROW_THUMB_UP;
         arrowClr = clrViolet;
         break;
      case REGIME_CONSOLIDATION:
         arrowType = OBJ_ARROW_LEFT_PRICE;
         arrowClr = clrBlue;
         break;
      default:
         arrowType = OBJ_ARROW_CHECK;
         arrowClr = clrYellow;
   }

   string name = "regime_marker_" + TimeToString(t, TIME_SECONDS);

   ObjectCreate(0, name, arrowType, 0, t, px);
   ObjectSetInteger(0, name, OBJPROP_COLOR, arrowClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // 텍스트 태그
   string tag = name + "_txt";
   ObjectCreate(0, tag, OBJ_TEXT, 0, t, px);
   ObjectSetString(0, tag, OBJPROP_TEXT,
                   GetRegimeNameStr(r.dominant_regime) +
                   StringFormat(" (%.1f%%)", r.confidence * 100));
   ObjectSetInteger(0, tag, OBJPROP_COLOR, arrowClr);
   ObjectSetInteger(0, tag, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, tag, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, tag, OBJPROP_BACK, true);
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UI 헬퍼 함수들                                                   |
//+------------------------------------------------------------------+
void CreatePanel(string id, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, id, OBJPROP_BGCOLOR, ColorToARGB(bg, 180));
   ObjectSetInteger(0, id, OBJPROP_COLOR, border);
   ObjectSetInteger(0, id, OBJPROP_BACK, true);
}

void CreateLabel(string id, string txt, int x, int y, color col, int fsz)
{
   ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, id, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, id, OBJPROP_COLOR, col);
   ObjectSetInteger(0, id, OBJPROP_FONTSIZE, fsz);
}

void CreateRect(string id, int x, int y, int w, int h, color c)
{
   ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, id, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
   ObjectSetInteger(0, id, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| 타이머 이벤트 처리                                                |
//+------------------------------------------------------------------+
void OnTimer()
{
   // ExecutionManager 타이머 이벤트 처리
   if(g_execution_manager)
   {
      g_execution_manager.OnTimer();
   }
   
   // 주기적 리스크 모니터링 (5분마다)
   static datetime last_risk_check = 0;
   datetime current_time = TimeCurrent();
   
   if(current_time - last_risk_check >= 300)
   {
      if(g_risk_manager)
      {
         double total_risk = g_risk_manager.GetTotalRiskPercent();
         int open_positions = g_risk_manager.GetOpenPositionsCount();
         
         LogInfo("리스크 모니터링: 총 리스크=" + DoubleToString(total_risk, 2) + 
                "%, 포지션 수=" + IntegerToString(open_positions));
         
         // ── 레짐 변경 후 포지션 충돌 확인 ─────────────────────────────
         if(open_positions > 0)
         {
            // 포인터라 NULL 체크가 필요하다면
            if(g_regime_detector != NULL)
           {
               SRegimeData current_regime = g_regime_detector.GetCurrentRegime();
               bool regime_changed = (g_last_regime != current_regime.dominant_regime);

               if(regime_changed)
               {
                  LogWarning("포지션 진입 후 레짐 변화: " 
                     + GetRegimeNameStr(g_last_regime) 
                     + " → " 
                     + GetRegimeNameStr(current_regime.dominant_regime));

                  // 레짐 충돌 확인 및 처리 로직
                  CheckRegimePositionConflict(current_regime);
               }
            }
            else
            {
               LogError("CheckConflict: g_regime_detector is NULL");
            }
         }

      }
      
      last_risk_check = current_time;
   }
   
   // 데이터 동기화 상태 모니터링 (2분마다)
   static datetime last_sync_check = 0;
   if(current_time - last_sync_check >= 120)
   {
      if(g_mtf_manager)
      {
         MonitorDataSynchronization();
      }
      last_sync_check = current_time;
   }
}

//+------------------------------------------------------------------+
//| 레짐-포지션 충돌 확인                                            |
//+------------------------------------------------------------------+
void CheckRegimePositionConflict(const SRegimeData &regime)
{
   if(!g_execution_manager || !g_execution_manager.HasOpenPosition())
      return;
      
   if(!PositionSelect(Symbol()))
      return;
      
   long pos_magic = PositionGetInteger(POSITION_MAGIC);
   if(pos_magic != InpMagic)
      return;
      
   ENUM_ORDER_TYPE position_type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
   bool is_conflicting = false;
   
   // 충돌 조건 확인
   switch(regime.dominant_regime)
   {
      case REGIME_STRONG_BULLISH:
         if(position_type == ORDER_TYPE_SELL)
            is_conflicting = true;
         break;
         
      case REGIME_STRONG_BEARISH:
         if(position_type == ORDER_TYPE_BUY)
            is_conflicting = true;
         break;
         
      case REGIME_GAP_TRADING:
         // 갭 방향과 반대 포지션은 충돌
         if((GapDirection > 0 && position_type == ORDER_TYPE_BUY) ||
            (GapDirection < 0 && position_type == ORDER_TYPE_SELL))
            is_conflicting = true;
         break;
   }
   
   if(is_conflicting && regime.confidence > 0.6)
   {
      LogWarning("레짐 충돌 감지: 현재 포지션 재평가 필요 (신뢰도: " + 
                DoubleToString(regime.confidence, 2) + ")");
      
      // 충돌 시 포지션 청산 고려 (보수적 접근)
      if(g_execution_manager.ClosePosition())
      {
         LogInfo("레짐 충돌로 인한 포지션 청산 성공");
      }
   }
}

//+------------------------------------------------------------------+
//| 데이터 동기화 모니터링                                            |
//+------------------------------------------------------------------+
void MonitorDataSynchronization()
{
   STimeframeCombo combo = g_mtf_manager.GetCurrentTimeframeCombo();
   STimeframeData primary_data, confirm_data, filter_data;
   datetime now = TimeCurrent();

   bool sync_ok = true;
   string out_of_sync = "";

   // 1) primary_tf (예: M5 → 300초)
   if(g_mtf_manager.GetTimeframeData(combo.primary_tf, primary_data))
   {
      int sec = PeriodSeconds(combo.primary_tf);            // bar 1개 주기(초)
      int thresh = int(sec * 1.2);                         // 1.2배 여유
      if(now - primary_data.last_update > thresh)
      {
         sync_ok = false;
         out_of_sync += EnumToString(combo.primary_tf) + " ";
      }
   }

   // 2) confirm_tf
   if(g_mtf_manager.GetTimeframeData(combo.confirm_tf, confirm_data))
   {
      int sec = PeriodSeconds(combo.confirm_tf);
      int thresh = int(sec * 1.2);
      if(now - confirm_data.last_update > thresh)
      {
         sync_ok = false;
         out_of_sync += EnumToString(combo.confirm_tf) + " ";
      }
   }

   // 3) filter_tf
   if(g_mtf_manager.GetTimeframeData(combo.filter_tf, filter_data))
   {
      int sec = PeriodSeconds(combo.filter_tf);
      int thresh = int(sec * 1.2);
      if(now - filter_data.last_update > thresh)
      {
         sync_ok = false;
         out_of_sync += EnumToString(combo.filter_tf) + " ";
      }
   }

   if(!sync_ok)
   {
      LogWarning("타임프레임 데이터 동기화 문제 감지: " + out_of_sync);
      g_mtf_manager.UpdateData();
      LogInfo("타임프레임 데이터 재동기화 시도 완료");
   }
}


//+------------------------------------------------------------------+
//| 거래 트랜잭션 이벤트 처리                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(g_execution_manager)
   {
      g_execution_manager.ProcessTradeTransaction(trans, request, result);
   }
   
   // 추가 트랜잭션 로깅 (매직 넘버 필터링)
   if(trans.symbol == Symbol())
   {
      // 매직 넘버 확인
      bool is_our_trade = false;
      
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
      {
         if(HistoryDealSelect(trans.deal))
         {
            long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            if(deal_magic == InpMagic)
               is_our_trade = true;
         }
      }
      else if(trans.order > 0)
      {
         // 주문 관련 트랜잭션에서는 request에서 확인
         if(request.magic == InpMagic)
            is_our_trade = true;
      }
      
      if(is_our_trade)
      {
         switch(trans.type)
         {
            case TRADE_TRANSACTION_DEAL_ADD:
               LogInfo("거래 체결: 딜 ID=" + IntegerToString(trans.deal) + 
                      ", 볼륨=" + DoubleToString(trans.volume, 2) + 
                      ", 가격=" + DoubleToString(trans.price, _Digits));
               break;
               
            case TRADE_TRANSACTION_ORDER_ADD:
               LogInfo("주문 등록: 주문 ID=" + IntegerToString(trans.order) + 
                      ", 타입=" + EnumToString((ENUM_ORDER_TYPE)trans.order_type));
               break;
               
            case TRADE_TRANSACTION_ORDER_DELETE:
               LogInfo("주문 삭제: 주문 ID=" + IntegerToString(trans.order));
               break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 차트 이벤트 처리                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // 차트 클릭 이벤트 등 처리
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, "dashboard_") >= 0)
      {
         LogInfo("대시보드 클릭: " + sparam);
         
         // 대시보드 클릭 시 레짐 정보 업데이트
         if(g_regime_detector)
         {
            SRegimeData current_regime = g_regime_detector.GetCurrentRegime();
            UpdateDashboard(current_regime);
         }
      }
   }
}