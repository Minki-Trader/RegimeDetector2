//+------------------------------------------------------------------+
//|                         RegimeDetector_Backtest_EA.mq5             |
//|                         NAS100 MTF Regime System                  |
//+------------------------------------------------------------------+
#property copyright "NAS100 MTF Regime System"
#property version   "1.01"
#property strict
#property description "NAS100 Multi-Timeframe Regime Detection EA"

// 포함 파일
#include "..\..\Include\RegimeDetection\RegimeDefinitions.mqh"
#include "..\..\Include\TimeFrames\TimeframeData.mqh"
#include "..\..\Include\Utils\SessionManager.mqh"
#include "..\..\Include\TimeFrames\MultiTimeframeManager.mqh"
#include "..\..\Include\RegimeDetection\RegimeDetector.mqh"
#include "..\..\Include\RegimeDetection\RegimeDetectorExtensions.mqh" 
#include "..\..\Include\Utils\Logger.mqh"
#include "..\..\Include\Trading\StrategySelector.mqh"
#include "..\..\Include\Trading\RiskManager.mqh"
#include "..\..\Include\Trading\ExecutionManager.mqh"

//+------------------------------------------------------------------+
//| 입력 파라미터 그룹화 및 정리                                     |
//+------------------------------------------------------------------+
input group "===== 기본 설정 =====";
input string TestID = "DefaultTest";  // 테스트 ID (결과 파일명)

input group "===== 백테스트 설정 =====";
input int Warmup_Days = 5;                      // 지표 계산 대기 일수
input bool Skip_Warmup_Period = false;         // 대기 기간 건너뛰기

input group "===== 타임프레임 설정 =====";
input ENUM_TIMEFRAMES Primary_TF = PERIOD_M5;      // 주 타임프레임
input ENUM_TIMEFRAMES Confirm_TF = PERIOD_M30;     // 확인 타임프레임
input ENUM_TIMEFRAMES Filter_TF = PERIOD_H4;       // 필터 타임프레임

// 기본 타임프레임 가중치 (세션별로 자동 조정됨)
input double Primary_Weight = 0.5;    // 주 타임프레임 가중치
input double Confirm_Weight = 0.3;    // 확인 타임프레임 가중치
input double Filter_Weight = 0.2;     // 필터 타임프레임 가중치

input group "===== 지표 설정 =====";
input int ADX_Period = 14;              // ADX 기간
input int RSI_Period = 14;              // RSI 기간
input int MA_Period = 20;               // 이동평균 기간
input int ATR_Period = 14;              // ATR 기간
input int Bands_Period = 20;            // 볼린저 밴드 기간
input double Bands_Deviation = 2.0;     // 볼린저 밴드 표준편차

input group "===== 레짐 감지 가중치 =====";
input double Trend_Weight = 0.35;      // 추세 지표 가중치
input double Momentum_Weight = 0.30;   // 모멘텀 지표 가중치
input double Volatility_Weight = 0.15; // 변동성 지표 가중치
input double Volume_Weight = 0.20;     // 거래량 지표 가중치

input group "===== 레짐 임계값 설정 =====";
input double Hysteresis_Threshold = 0.1; // 레짐 전환 임계값
input int Hysteresis_Bars = 2;           // 레짐 유지 최소 봉 수
input double Regime_Threshold = 0.5;     // 레짐 최소 신뢰도 임계값

input group "===== 지표 임계값 설정 =====";
input double ADX_Trend_Threshold = 20.0;    // ADX 트렌드 임계값
input double ADX_Strong_Threshold = 30.0;   // ADX 강한 트렌드 임계값
input double RSI_Overbought = 70.0;         // RSI 과매수 기준
input double RSI_Oversold = 30.0;           // RSI 과매도 기준
input double RSI_Neutral_High = 60.0;       // RSI 중립대 상단
input double RSI_Neutral_Low = 40.0;        // RSI 중립대 하단
input double BB_Width_Narrow = 0.02;        // 좁은 밴드 폭 기준
input double BB_Width_Wide = 0.05;          // 넓은 밴드 폭 기준

input group "===== 전략별 최소 신뢰도 설정 =====";
input double Trend_Min_Confidence = 0.5;      // 추세 추종 최소 신뢰도
input double Reversion_Min_Confidence = 0.6;  // 평균 회귀 최소 신뢰도  
input double Breakout_Min_Confidence = 0.6;   // 돌파 최소 신뢰도
input double Range_Min_Confidence = 0.25;     // 레인지 거래 최소 신뢰도
input double Scalping_Min_Confidence = 0.4;   // 스캘핑 최소 신뢰도
input double Gap_Min_Confidence = 0.6;        // 갭 페이드 최소 신뢰도
input double Volatility_Min_Confidence = 0.7; // 변동성 돌파 최소 신뢰도

input group "===== 거래 실행 설정 =====";
input bool Enable_Trading = true;              // 거래 실행 활성화 (백테스트/라이브 공통)
input double Risk_Per_Trade = 1.0;             // 거래당 리스크 (%)
input double Max_Total_Risk = 10.0;            // 총 최대 리스크 (%)
input double Max_Daily_Loss = 5.0;             // 일일 최대 손실 (%)
input int Max_Positions = 3;                   // 최대 포지션 수
input ulong Magic_Number = 123456;             // 매직 넘버

input group "===== SL/TP 설정 =====";
input double Default_SL_ATR_Multiplier = 1.0;  // 기본 SL (ATR 배수)
input double Default_TP_ATR_Multiplier = 3.0;  // 기본 TP (ATR 배수)
input bool Use_Trailing_Stop = true;           // 트레일링 스탑 사용
input double Trailing_Start_Points = 50;       // 트레일링 시작 포인트
input double Trailing_Step_Points = 10;        // 트레일링 스텝 포인트

input group "===== 리스크 관리 설정 =====";
input double Max_Lot_Size = 1.0;               // 최대 랏 사이즈
input int Max_Execution_Retries = 3;           // 최대 실행 재시도 횟수
input int Max_Slippage_Points = 10;            // 최대 슬리피지 (포인트)
input double Max_Spread_Points = 20;           // 최대 스프레드 (포인트)
input double Emergency_Margin_Level = 20.0;    // 긴급 청산 마진 레벨
input double Partial_Close_Percent = 50.0;     // 부분 청산 비율 (%)
input double Partial_Close_ATR_Trigger = 1.5;  // 부분 청산 트리거 (ATR 배수)

input group "===== 화면 표시 설정 =====";
input bool Show_Dashboard = true;              // 대시보드 표시
input bool Mark_Regime_Changes = true;         // 레짐 변경 마커 표시
input bool Show_Trading_Stats = true;          // 거래 통계 표시

input group "===== 로깅 설정 =====";
input ENUM_LOG_LEVEL LogLevel = LOG_LEVEL_INFO;     // 로그 레벨 (INFO 권장)
input bool Enable_File_Logging = false;             // 파일 로깅 활성화
input string LogFileName = "";                      // 로그 파일명 (비워두면 자동)

input group "===== CSV 저장 설정 =====";
input bool Save_Results_To_CSV = true;         // CSV 결과 저장
input string CSV_Subfolder = "Results";        // CSV 저장 하위 폴더
input bool Use_Custom_Path = false;            // 사용자 지정 경로 사용
input string Custom_CSV_Path = "";             // 사용자 지정 저장 경로

//+------------------------------------------------------------------+
//| 글로벌 변수                                                      |
//+------------------------------------------------------------------+
CSessionManager* g_session_manager = NULL;
CMultiTimeframeManager* g_mtf_manager = NULL;
CRegimeDetector* g_regime_detector = NULL;
CStrategySelector* g_strategy_selector = NULL;
CRiskManager* g_risk_manager = NULL;
CExecutionManager* g_execution_manager = NULL;

// 기존 글로벌 변수들 아래에 추가
datetime g_start_time = 0;
bool g_warmup_complete = false;

// input 파라미터의 조정된 값을 저장할 변수들
double adjusted_RSI_Overbought;
double adjusted_RSI_Oversold;
double adjusted_RSI_Neutral_High;
double adjusted_RSI_Neutral_Low;
int adjusted_RSI_Period;
double adjusted_Trend_Min_Confidence;
double adjusted_Breakout_Min_Confidence;
double adjusted_Volatility_Min_Confidence;
double adjusted_Risk_Per_Trade;
double adjusted_Partial_Close_Percent;

datetime g_last_bar_time = 0;
ENUM_MARKET_REGIME g_last_regime = REGIME_UNKNOWN;

bool g_indicators_initialized = false;

// CSV 저장 관련
string g_csv_filename = "";
int file_handle = INVALID_HANDLE;

// 거래 통계
struct STradingStats {
   int total_signals;
   int executed_trades;
   int winning_trades;
   int losing_trades;
   double total_profit;
   double max_drawdown;
   datetime last_trade_time;
   datetime last_update_time;
};
STradingStats g_trading_stats;

//+------------------------------------------------------------------+
//| 유틸리티 함수들                                                  |
//+------------------------------------------------------------------+
string GetRegimeNameStr(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_UNKNOWN: return "알 수 없음";
      case REGIME_STRONG_BULLISH: return "강한 상승";
      case REGIME_STRONG_BEARISH: return "강한 하락";
      case REGIME_CONSOLIDATION: return "통합 레인지";
      case REGIME_VOLATILITY_EXPANSION: return "변동성 확장";
      case REGIME_OVERNIGHT_DRIFT: return "오버나이트";
      case REGIME_GAP_TRADING: return "갭 패턴";
      case REGIME_TECHNICAL_REVERSAL: return "기술적 반전";
      default: return "정의되지 않음";
   }
}

string GetSessionNameStr(ESessionType session)
{
   switch(session)
   {
      case SESSION_ASIA: return "아시아";
      case SESSION_EUROPE: return "유럽";
      case SESSION_US: return "미국";
      default: return "알 수 없음";
   }
}

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

bool DirectoryExists(string path)
{
   if(path == "") return false;
   if(StringSubstr(path, StringLen(path) - 1, 1) == "\\" || 
      StringSubstr(path, StringLen(path) - 1, 1) == "/")
      path = StringSubstr(path, 0, StringLen(path) - 1);
   return (bool)FileIsExist(path + "\\*.*");
}

//+------------------------------------------------------------------+
//| 세션별 가중치 설정                                               |
//+------------------------------------------------------------------+
void ApplySessionWeights(ESessionType session)
{
   if(g_mtf_manager == NULL || g_regime_detector == NULL) return;
   
   STimeframeCombo combo = g_mtf_manager.GetCurrentTimeframeCombo();
   
   // 세션별 타임프레임 가중치 조정
   switch(session)
   {
      case SESSION_ASIA:
         combo.weights[0] = 0.4; combo.weights[1] = 0.4; combo.weights[2] = 0.2;
         g_regime_detector.SetRegimeWeights(0.3, Momentum_Weight, Volatility_Weight, Volume_Weight);
         break;
      case SESSION_EUROPE:
         combo.weights[0] = 0.3; combo.weights[1] = 0.4; combo.weights[2] = 0.3;
         g_regime_detector.SetRegimeWeights(0.35, Momentum_Weight, Volatility_Weight, Volume_Weight);
         break;
      case SESSION_US:
         combo.weights[0] = 0.2; combo.weights[1] = 0.3; combo.weights[2] = 0.5;
         g_regime_detector.SetRegimeWeights(0.4, Momentum_Weight, Volatility_Weight, Volume_Weight);
         break;
      default:
         combo.weights[0] = Primary_Weight;
         combo.weights[1] = Confirm_Weight;
         combo.weights[2] = Filter_Weight;
         g_regime_detector.SetRegimeWeights(Trend_Weight, Momentum_Weight, Volatility_Weight, Volume_Weight);
   }
   
   g_mtf_manager.SetTimeframeCombo(combo);
}

//+------------------------------------------------------------------+
//| CSV 파일 초기화                                                  |
//+------------------------------------------------------------------+
bool InitializeCSVFile()
{
   if(!Save_Results_To_CSV) return true;
   
   string filename = TestID + ".csv";
   string filepath;
   int open_flags = FILE_WRITE | FILE_CSV | FILE_REWRITE;
   
   if(Use_Custom_Path && StringLen(Custom_CSV_Path) > 0)
   {
      filepath = Custom_CSV_Path;
      if(!DirectoryExists(filepath))
      {
         if(!FolderCreate(filepath, 0))
         {
            LogError("디렉토리 생성 실패: " + filepath);
            return false;
         }
      }
      int len = StringLen(filepath);
      string last = StringSubstr(filepath, len-1, 1);
      if(last != "/" && last != "\\") filepath += "/";
      filepath += filename;
      open_flags |= FILE_COMMON;
   }
   else if(StringLen(CSV_Subfolder) > 0)
   {
      filepath = CSV_Subfolder;
      if(!DirectoryExists(filepath))
      {
         if(!FolderCreate(filepath, 0))
         {
            LogError("서브폴더 생성 실패: " + filepath);
            return false;
         }
      }
      filepath += "/" + filename;
   }
   else
   {
      filepath = filename;
   }
   
   g_csv_filename = filepath;
   file_handle = FileOpen(filepath, open_flags);
   
   if(file_handle == INVALID_HANDLE)
   {
      LogError("CSV 파일 생성 실패: " + filepath);
      return false;
   }
   
   // CSV 헤더 작성
   FileWrite(file_handle, "TestID: " + TestID);
   FileWrite(file_handle, "Symbol: " + Symbol() + ", TimeFrame: " + EnumToString(Primary_TF));
   FileWrite(file_handle, "Trading Enabled: " + (Enable_Trading ? "Yes" : "No"));
   FileWrite(file_handle, "");
   
   FileWrite(file_handle,
             "Date","Time","Regime","Confidence","StrongBull","StrongBear",
             "Consol","Volatility","Overnight","Gap","Reversal","Price","Session",
             "Strategy","SignalCount","ActivePositions");
   
   LogInfo("CSV 파일 생성 완료: " + filepath);
   return true;
}

//+------------------------------------------------------------------+
//| 거래 통계 업데이트                                               |
//+------------------------------------------------------------------+
void UpdateTradingStats()
{
   datetime current_time = TimeCurrent();
   if(current_time - g_trading_stats.last_update_time < 60) return; // 1분마다 업데이트
   
   g_trading_stats.last_update_time = current_time;
   
   if(g_execution_manager != NULL)
   {
      SExecutionStats exec_stats = g_execution_manager.GetExecutionStats();
      SPositionSummary pos_summary = g_execution_manager.GetPositionSummary();
      g_trading_stats.total_profit = pos_summary.total_profit;
      
      // 최대 드로다운 계산
      static double peak_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(current_balance > peak_balance) peak_balance = current_balance;
      
      double drawdown = (peak_balance - current_balance) / peak_balance * 100.0;
      if(drawdown > g_trading_stats.max_drawdown)
         g_trading_stats.max_drawdown = drawdown;
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   /// 로거 초기화
   string log_file = LogFileName;
   if(log_file == "") log_file = "NAS100_" + Symbol() + "_" + EnumToString(Period()) + ".log";
   
   ENUM_LOG_MODE log_mode = Enable_File_Logging ? LOG_MODE_BOTH : LOG_MODE_CONSOLE;
   LoggerInit(LogLevel, log_mode, log_file);
   
   // ===== 완전한 파라미터 검증 및 정규화 =====
   LogInfo("=== 입력 파라미터 검증 시작 ===");
   
   // RSI 파라미터 정규화 (0-100 범위)
   adjusted_RSI_Overbought = MathMax(50.0, MathMin(100.0, RSI_Overbought));
   if(adjusted_RSI_Overbought != RSI_Overbought) {
      LogWarning(StringFormat("RSI_Overbought %.0f -> %.0f로 조정", RSI_Overbought, adjusted_RSI_Overbought));
   }
   
   adjusted_RSI_Oversold = MathMax(0.0, MathMin(50.0, RSI_Oversold));
   if(adjusted_RSI_Oversold != RSI_Oversold) {
      LogWarning(StringFormat("RSI_Oversold %.0f -> %.0f로 조정", RSI_Oversold, adjusted_RSI_Oversold));
   }
   
   adjusted_RSI_Neutral_High = MathMax(50.0, MathMin(80.0, RSI_Neutral_High));
   if(adjusted_RSI_Neutral_High != RSI_Neutral_High) {
      LogWarning(StringFormat("RSI_Neutral_High %.0f -> %.0f로 조정", RSI_Neutral_High, adjusted_RSI_Neutral_High));
   }
   
   adjusted_RSI_Neutral_Low = MathMax(20.0, MathMin(50.0, RSI_Neutral_Low));
   if(adjusted_RSI_Neutral_Low != RSI_Neutral_Low) {
      LogWarning(StringFormat("RSI_Neutral_Low %.0f -> %.0f로 조정", RSI_Neutral_Low, adjusted_RSI_Neutral_Low));
   }
   
   // RSI 논리적 순서 보장
   if(adjusted_RSI_Oversold >= adjusted_RSI_Neutral_Low) {
      adjusted_RSI_Oversold = 30.0;
      adjusted_RSI_Neutral_Low = 40.0;
      LogError("RSI 순서 오류 - 기본값으로 재설정: Oversold=30, Neutral_Low=40");
   }
   
   if(adjusted_RSI_Neutral_High >= adjusted_RSI_Overbought) {
      adjusted_RSI_Neutral_High = 60.0;
      adjusted_RSI_Overbought = 70.0;
      LogError("RSI 순서 오류 - 기본값으로 재설정: Neutral_High=60, Overbought=70");
   }
   
   // ADX 파라미터 정규화 (합리적 범위)
   double adjusted_ADX_Trend = MathMax(15.0, MathMin(40.0, ADX_Trend_Threshold));
   if(adjusted_ADX_Trend != ADX_Trend_Threshold) {
      LogWarning(StringFormat("ADX_Trend_Threshold %.0f -> %.0f로 조정", ADX_Trend_Threshold, adjusted_ADX_Trend));
   }
   
   double adjusted_ADX_Strong = MathMax(25.0, MathMin(60.0, ADX_Strong_Threshold));
   if(adjusted_ADX_Strong != ADX_Strong_Threshold) {
      LogWarning(StringFormat("ADX_Strong_Threshold %.0f -> %.0f로 조정", ADX_Strong_Threshold, adjusted_ADX_Strong));
   }
   
   // 신뢰도 파라미터 정규화 (0-1 범위)
   adjusted_Trend_Min_Confidence = MathMax(0.0, MathMin(1.0, Trend_Min_Confidence));
   if(MathAbs(adjusted_Trend_Min_Confidence - Trend_Min_Confidence) > 0.01) {
      LogWarning(StringFormat("Trend_Min_Confidence %.2f -> %.2f로 조정", Trend_Min_Confidence, adjusted_Trend_Min_Confidence));
   }
   
   adjusted_Breakout_Min_Confidence = MathMax(0.0, MathMin(1.0, Breakout_Min_Confidence));
   adjusted_Volatility_Min_Confidence = MathMax(0.0, MathMin(1.0, Volatility_Min_Confidence));
   
   // 리스크 파라미터 정규화
   adjusted_Risk_Per_Trade = MathMax(0.5, MathMin(10.0, Risk_Per_Trade));
   if(adjusted_Risk_Per_Trade != Risk_Per_Trade) {
      LogWarning(StringFormat("Risk_Per_Trade %.1f%% -> %.1f%%로 조정", Risk_Per_Trade, adjusted_Risk_Per_Trade));
   }
   
   double adjusted_Max_Total_Risk = MathMax(5.0, MathMin(50.0, Max_Total_Risk));
   if(adjusted_Max_Total_Risk != Max_Total_Risk) {
      LogWarning(StringFormat("Max_Total_Risk %.1f%% -> %.1f%%로 조정", Max_Total_Risk, adjusted_Max_Total_Risk));
   }
   
   adjusted_Partial_Close_Percent = MathMax(10.0, MathMin(100.0, Partial_Close_Percent));
   if(adjusted_Partial_Close_Percent != Partial_Close_Percent) {
      LogWarning(StringFormat("Partial_Close_Percent %.0f%% -> %.0f%%로 조정", Partial_Close_Percent, adjusted_Partial_Close_Percent));
   }
   
   LogInfo("=== 파라미터 검증 완료 ===");
   
   // input 값을 조정된 변수에 복사 및 검증
   adjusted_RSI_Overbought = RSI_Overbought;
   adjusted_RSI_Oversold = RSI_Oversold;
   adjusted_RSI_Neutral_High = RSI_Neutral_High;
   adjusted_RSI_Neutral_Low = RSI_Neutral_Low;
   adjusted_RSI_Period = RSI_Period; 
   adjusted_Trend_Min_Confidence = Trend_Min_Confidence;
   adjusted_Breakout_Min_Confidence = Breakout_Min_Confidence;
   adjusted_Volatility_Min_Confidence = Volatility_Min_Confidence;
   adjusted_Risk_Per_Trade = Risk_Per_Trade;
   adjusted_Partial_Close_Percent = Partial_Close_Percent;
   
   // 파라미터 검증 및 자동 수정 (366줄부터 수정)
   if(adjusted_RSI_Period > 100 || adjusted_RSI_Period < 2) {
    LogWarning("RSI_Period " + IntegerToString(RSI_Period) + " -> 14로 조정");
    adjusted_RSI_Period = 14;  // input이 아닌 adjusted_ 변수 수정
   }
   
   if(adjusted_RSI_Overbought > 100) {
    LogWarning("RSI_Overbought " + DoubleToString(RSI_Overbought, 0) + " -> 70으로 조정");
    adjusted_RSI_Overbought = 70;
   }
   if(adjusted_RSI_Neutral_High > 100) {
      LogWarning("RSI_Neutral_High " + DoubleToString(RSI_Neutral_High, 0) + " -> 60으로 조정");
      adjusted_RSI_Neutral_High = 60;  // ✅ adjusted_ 변수 수정
   }
   if(adjusted_RSI_Neutral_Low > 100) {
      LogWarning("RSI_Neutral_Low " + DoubleToString(RSI_Neutral_Low, 0) + " -> 40으로 조정");
      adjusted_RSI_Neutral_Low = 40;  // ✅ adjusted_ 변수 수정
   }

   // 신뢰도 검증 (0-1 범위)
   if(adjusted_Trend_Min_Confidence > 1.0) {
      LogWarning("Trend_Min_Confidence " + DoubleToString(Trend_Min_Confidence, 2) + " -> 0.5로 조정");
      adjusted_Trend_Min_Confidence = 0.5;  // ✅ adjusted_ 변수 수정
   }
   if(adjusted_Breakout_Min_Confidence > 1.0) {
      LogWarning("Breakout_Min_Confidence " + DoubleToString(Breakout_Min_Confidence, 2) + " -> 0.6으로 조정");
      adjusted_Breakout_Min_Confidence = 0.6;  // ✅ adjusted_ 변수 수정
   }
   if(adjusted_Volatility_Min_Confidence > 1.0) {
      LogWarning("Volatility_Min_Confidence " + DoubleToString(Volatility_Min_Confidence, 2) + " -> 0.7으로 조정");
      adjusted_Volatility_Min_Confidence = 0.7;  // ✅ adjusted_ 변수 수정
   }

   // 리스크 파라미터 검증
   if(adjusted_Risk_Per_Trade > 10.0) {
      LogWarning("Risk_Per_Trade " + DoubleToString(Risk_Per_Trade, 1) + "% -> 2%로 조정");
      adjusted_Risk_Per_Trade = 2.0;  // ✅ adjusted_ 변수 수정
   }
   if(adjusted_Partial_Close_Percent > 100) {
      LogWarning("Partial_Close_Percent " + DoubleToString(Partial_Close_Percent, 0) + "% -> 50%로 조정");
      adjusted_Partial_Close_Percent = 50;  // ✅ adjusted_ 변수 수정
   }

   // RSI 논리적 순서 검증
   if(adjusted_RSI_Oversold >= adjusted_RSI_Neutral_Low) {
      LogError("RSI_Oversold >= RSI_Neutral_Low - 자동 조정");
      adjusted_RSI_Oversold = 30;     // ✅ adjusted_ 변수 수정
      adjusted_RSI_Neutral_Low = 40;  // ✅ adjusted_ 변수 수정
   }
   if(adjusted_RSI_Neutral_High >= adjusted_RSI_Overbought) {
      LogError("RSI_Neutral_High >= RSI_Overbought - 자동 조정");
      adjusted_RSI_Neutral_High = 60;   // ✅ adjusted_ 변수 수정
      adjusted_RSI_Overbought = 70;     // ✅ adjusted_ 변수 수정
   }
   
   LogInfo("=== NAS100 레짐 감지 EA 초기화 시작 ===");
   LogInfo("심볼: " + Symbol() + ", 차트: " + EnumToString(Period()));
   LogInfo("거래 실행: " + (Enable_Trading ? "활성화" : "비활성화"));
   
   // 통계 초기화
   ZeroMemory(g_trading_stats);
   
   // 세션 관리자 초기화
   g_session_manager = new CSessionManager();
   if(!g_session_manager)
   {
      LogError("SessionManager 생성 실패");
      return INIT_FAILED;
   }
   g_session_manager.Update();
   
   // MTF 관리자 초기화
   g_mtf_manager = new CMultiTimeframeManager(Symbol(), g_session_manager);
   if(!g_mtf_manager || !g_mtf_manager.Initialize())
   {
      LogError("MultiTimeframeManager 초기화 실패");
      delete g_session_manager;
      return INIT_FAILED;
   }
   
   // 레짐 감지기 초기화
   g_regime_detector = new CRegimeDetector(Symbol(), g_mtf_manager, g_session_manager);
   if(!g_regime_detector || !g_regime_detector.Initialize())
   {
      // ★ 백테스트 환경에서는 초기화 실패를 허용
      if(MQLInfoInteger(MQL_TESTER)) {
         LogWarning("RegimeDetector 초기화 지연 - 첫 틱에서 재시도");
         g_indicators_initialized = false;  // 첫 틱에서 재초기화 필요
      } else {
         LogError("RegimeDetector 초기화 실패");
         delete g_mtf_manager;
         delete g_session_manager;
         return INIT_FAILED;
      }
   } else {
      g_indicators_initialized = true;
   }
   
   // 레짐 감지기 설정
   g_regime_detector.SetHysteresisParameters(Hysteresis_Threshold, Hysteresis_Bars);
   g_regime_detector.AdjustThresholds(Regime_Threshold);
   g_regime_detector.SetIndicatorParameters(ADX_Period, adjusted_RSI_Period, MA_Period, ATR_Period, Bands_Period, Bands_Deviation);
   
   // 지표 파라미터 구조체 생성
   SIndicatorParams indicator_params;
   indicator_params.adx_period = ADX_Period;
   indicator_params.rsi_period = adjusted_RSI_Period;
   indicator_params.ma_period = MA_Period;
   indicator_params.atr_period = ATR_Period;
   indicator_params.bands_period = Bands_Period;
   indicator_params.bands_deviation = Bands_Deviation;
   indicator_params.adx_trend_threshold = ADX_Trend_Threshold;
   indicator_params.adx_strong_threshold = ADX_Strong_Threshold;
   indicator_params.rsi_overbought = adjusted_RSI_Overbought;
   indicator_params.rsi_oversold = adjusted_RSI_Oversold;
   indicator_params.rsi_neutral_high = adjusted_RSI_Neutral_High;
   indicator_params.rsi_neutral_low = adjusted_RSI_Neutral_Low;
   indicator_params.bb_width_narrow = BB_Width_Narrow;
   indicator_params.bb_width_wide = BB_Width_Wide;
   
   // RiskManager 초기화 (백테스트에서도 필요)
   g_risk_manager = new CRiskManager(Symbol());
   if(!g_risk_manager || !g_risk_manager.Initialize())
   {
      LogError("RiskManager 초기화 실패");
      delete g_regime_detector;
      delete g_mtf_manager;
      delete g_session_manager;
      return INIT_FAILED;
   }
   
   g_risk_manager.SetRiskParameters(adjusted_Risk_Per_Trade, Max_Total_Risk, Max_Daily_Loss, Max_Positions);
   g_risk_manager.SetMaxLotSize(Max_Lot_Size);
   g_risk_manager.SetEmergencyLevel(Emergency_Margin_Level);
   
   // StrategySelector 초기화
   g_strategy_selector = new CStrategySelector(g_regime_detector, g_session_manager, 
                                              g_risk_manager, Symbol(), indicator_params);
   if(!g_strategy_selector || !g_strategy_selector.Initialize())
   {
      LogError("StrategySelector 초기화 실패");
      delete g_risk_manager;
      delete g_regime_detector;
      delete g_mtf_manager;
      delete g_session_manager;
      return INIT_FAILED;
   }
   
   // 전략별 신뢰도 설정 - 조정된 값 사용
   g_strategy_selector.SetMinConfidence(STRATEGY_TREND_FOLLOWING, adjusted_Trend_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_MEAN_REVERSION, Reversion_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_BREAKOUT, adjusted_Breakout_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_RANGE_TRADING, Range_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_SCALPING, Scalping_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_GAP_FADE, Gap_Min_Confidence);
   g_strategy_selector.SetMinConfidence(STRATEGY_VOLATILITY_BREAKOUT, adjusted_Volatility_Min_Confidence);
   
   // ExecutionManager 초기화 (백테스트에서도 필요)
   g_execution_manager = new CExecutionManager(Symbol(), Magic_Number);
   if(!g_execution_manager || !g_execution_manager.Initialize(g_risk_manager, g_session_manager, g_strategy_selector))
   {
      LogError("ExecutionManager 초기화 실패");
      delete g_strategy_selector;
      delete g_risk_manager;
      delete g_regime_detector;
      delete g_mtf_manager;
      delete g_session_manager;
      return INIT_FAILED;
   }
   
   g_execution_manager.SetExecutionParameters(Max_Execution_Retries, Max_Slippage_Points, Max_Spread_Points);
   g_execution_manager.SetTrailingStopParameters(Use_Trailing_Stop, Trailing_Start_Points, Trailing_Step_Points);
   g_execution_manager.SetPartialCloseParameters(true, Partial_Close_Percent, Partial_Close_ATR_Trigger);
   
   // StrategySelector 리스크 설정 (백테스트에서도 필요)
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_strategy_selector.SetRiskAmount(account_balance * adjusted_Risk_Per_Trade / 100.0);
   g_strategy_selector.SetRiskPercent(adjusted_Risk_Per_Trade);
   g_strategy_selector.EnableDynamicSizing(true);
   
   // 초기 세션 가중치 적용
   ESessionType current_session = g_session_manager.GetCurrentSession();
   ApplySessionWeights(current_session);
   
   // CSV 파일 초기화
   if(!InitializeCSVFile())
   {
      LogWarning("CSV 파일 초기화 실패, 계속 진행");
   }
   
   LogInfo("초기화 완료 - 현재 세션: " + GetSessionNameStr(current_session));
   LogInfo("거래 실행: " + (Enable_Trading ? "활성화됨" : "비활성화됨"));
   
   // 백테스트 시작 시간 저장
   g_start_time = TimeCurrent();
   g_warmup_complete = Skip_Warmup_Period; // 건너뛰기 옵션 확인

   LogInfo("백테스트 시작 시간: " + TimeToString(g_start_time));
   if(!Skip_Warmup_Period) {
       LogInfo("지표 안정화 대기: " + IntegerToString(Warmup_Days) + "일");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogInfo("EA 종료, 이유: " + IntegerToString(reason));
   
   // 파일 핸들 닫기
   if(file_handle != INVALID_HANDLE)
   {
      FileClose(file_handle);
      file_handle = INVALID_HANDLE;
   }
   
   // 차트 객체 정리
   if(Show_Dashboard) ObjectsDeleteAll(0, "dashboard_");
   if(Mark_Regime_Changes) ObjectsDeleteAll(0, "regime_marker_");
   
   // 객체 해제
   delete g_execution_manager;
   delete g_strategy_selector;
   delete g_risk_manager;
   delete g_regime_detector;
   delete g_mtf_manager;
   delete g_session_manager;
   
   // 지표 핸들 해제
   ReleaseIndicatorHandles();
   
   // 로거 종료
   LoggerShutdown();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
      // 대기 기간 체크
   if(!g_warmup_complete && !Skip_Warmup_Period) {
      datetime current_time = TimeCurrent();
      int elapsed_days = (int)((current_time - g_start_time) / 86400); // 86400 = 24시간
      
      if(elapsed_days < Warmup_Days) {
         // 10분마다 한 번씩만 로그 출력
         static datetime last_log = 0;
         if(current_time - last_log > 600) {
            LogInfo("지표 안정화 대기 중... " + IntegerToString(elapsed_days) + "/" + 
                   IntegerToString(Warmup_Days) + "일 경과");
            last_log = current_time;
         }
         return; // 거래하지 않고 종료
      } else if(!g_warmup_complete) {
         g_warmup_complete = true;
         LogInfo("대기 기간 완료! 거래 시작 준비...");
         
         // 여기서 지표 핸들 재초기화
         if(g_regime_detector != NULL) {
            g_regime_detector.ReinitializeIndicators();
         }
      }
   }
   
   // 첫 번째 틱에서 지표 재초기화 시도
if(!g_indicators_initialized && g_regime_detector!=NULL)
{
   static int init_attempts   = 0;
   static datetime last_try   = 0;
   datetime now = TimeCurrent();

   if(now - last_try < 1)     // 1초에 한 번만
      return;

   last_try = now;
   init_attempts++;

   LogInfo(StringFormat("지표 재초기화 시도 %d/20…", init_attempts));

   // 추가: 각 타임프레임별 데이터 검증
   STimeframeCombo combo = g_mtf_manager.GetCurrentTimeframeCombo();
   bool data_ready = true;
   
   // 각 타임프레임별 최소 필요 바 수 계산
   int min_bars_m5 = MathMax(100, adjusted_RSI_Period + 20);  // adjusted_ 변수 사용
   int min_bars_m30 = MathMax(20, (adjusted_RSI_Period + 20) / 6);  // M30은 M5의 1/6
   int min_bars_h4 = MathMax(10, (adjusted_RSI_Period + 20) / 48);  // H4는 M5의 1/48
   
   // 각 타임프레임별로 적절한 최소 바 수 확인
   if(combo.primary_tf == PERIOD_M5 && Bars(Symbol(), combo.primary_tf) < min_bars_m5) {
      LogWarning("M5 데이터 부족: " + IntegerToString(Bars(Symbol(), combo.primary_tf)) + " < " + IntegerToString(min_bars_m5));
      data_ready = false;
   }
   else if(combo.primary_tf == PERIOD_M30 && Bars(Symbol(), combo.primary_tf) < min_bars_m30) {
      LogWarning("M30 데이터 부족: " + IntegerToString(Bars(Symbol(), combo.primary_tf)) + " < " + IntegerToString(min_bars_m30));
      data_ready = false;
   }
   else if(combo.primary_tf == PERIOD_H4 && Bars(Symbol(), combo.primary_tf) < min_bars_h4) {
      LogWarning("H4 데이터 부족: " + IntegerToString(Bars(Symbol(), combo.primary_tf)) + " < " + IntegerToString(min_bars_h4));
      data_ready = false;
   }
   
   // confirm_tf와 filter_tf도 확인
   if(combo.confirm_tf == PERIOD_M30 && Bars(Symbol(), combo.confirm_tf) < min_bars_m30) {
      LogWarning("확인 TF (M30) 데이터 부족");
      data_ready = false;
   }
   if(combo.filter_tf == PERIOD_H4 && Bars(Symbol(), combo.filter_tf) < min_bars_h4) {
      LogWarning("필터 TF (H4) 데이터 부족");
      data_ready = false;
   }

      if(!data_ready)
      {
         LogWarning("히스토리 데이터 아직 부족");
         if(init_attempts >= 50)
         {
            LogError("최대 재시도 초과 – EA 종료");
            ExpertRemove();
         }
         return;
      }

      // 핸들 재생성
      if(g_regime_detector.ReinitializeIndicators())
      {
         g_indicators_initialized = true;
         LogInfo("지표 재초기화 성공!");
      }
      else if(init_attempts >= 20)
      {
         LogError("지표 재초기화 최종 실패 – EA 종료");
         ExpertRemove();
      }
      return;                    // 초기화 완료 전엔 이하 로직 스킵
   }
   
   
   if(!IsNewBar()) return;
   
   // 세션 업데이트 및 가중치 조정
   static ESessionType prev_session = SESSION_UNKNOWN;
   if(g_session_manager != NULL)
   {
      g_session_manager.Update();
      ESessionType current_session = g_session_manager.GetCurrentSession();
      
      if(current_session != prev_session)
      {
         ApplySessionWeights(current_session);
         LogInfo("세션 변경: " + GetSessionNameStr(prev_session) + " → " + GetSessionNameStr(current_session));
         prev_session = current_session;
      }
   }
   
   // 레짐 업데이트 (안전한 방식으로)
   if(g_regime_detector != NULL)
   {
      // 지표 준비 상태 확인을 위한 짧은 대기
      static int update_attempts = 0;
      
      if(g_regime_detector.Update())
      {
         update_attempts = 0; // 성공 시 재시도 카운터 리셋
         
         SRegimeData current_regime = g_regime_detector.GetCurrentRegime();
      
      // CSV 데이터 기록
      if(Save_Results_To_CSV && file_handle != INVALID_HANDLE)
      {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         
         string strategy_name = "None";
         int active_positions = 0;
         
         if(g_strategy_selector != NULL)
         {
            ENUM_STRATEGY_TYPE current_strategy = g_strategy_selector.GetCurrentStrategy();
            strategy_name = g_strategy_selector.GetStrategyName(current_strategy);
         }
         
         if(g_execution_manager != NULL)
         {
            active_positions = g_execution_manager.GetActivePositionCount();
         }
         
         FileWrite(file_handle,
            StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day),
            StringFormat("%02d:%02d", dt.hour, dt.min),
            GetRegimeNameStr(current_regime.dominant_regime),
            DoubleToString(current_regime.confidence, 2),
            DoubleToString(current_regime.regime_scores[REGIME_STRONG_BULLISH], 2),
            DoubleToString(current_regime.regime_scores[REGIME_STRONG_BEARISH], 2),
            DoubleToString(current_regime.regime_scores[REGIME_CONSOLIDATION], 2),
            DoubleToString(current_regime.regime_scores[REGIME_VOLATILITY_EXPANSION], 2),
            DoubleToString(current_regime.regime_scores[REGIME_OVERNIGHT_DRIFT], 2),
            DoubleToString(current_regime.regime_scores[REGIME_GAP_TRADING], 2),
            DoubleToString(current_regime.regime_scores[REGIME_TECHNICAL_REVERSAL], 2),
            DoubleToString(iClose(Symbol(), PERIOD_CURRENT, 0), _Digits),
            GetSessionNameStr(g_session_manager.GetCurrentSession()),
            strategy_name,
            IntegerToString(g_trading_stats.total_signals),
            IntegerToString(active_positions)
         );
      }
      
      // 레짐 정보 출력 (간소화)
      if(LogLevel >= LOG_LEVEL_INFO)
      {
         LogInfo("레짐: " + GetRegimeNameStr(current_regime.dominant_regime) + 
                " (" + DoubleToString(current_regime.confidence * 100, 0) + "%)");
      }
      
      // 전략 업데이트 및 거래 실행
      if(g_strategy_selector != NULL)
      {
         g_strategy_selector.UpdateStrategy();
         
         // 포지션 관리 (항상 실행)
         if(g_execution_manager != NULL)
         {
            g_execution_manager.UpdatePositions();
            g_execution_manager.UpdateTrailingStops();
            g_execution_manager.CheckAndExecutePartialClose();
            g_execution_manager.CheckAndHandleEmergency();
         }
         
         if(Enable_Trading)
         {
            // 신호 확인 및 실행
            SEntrySignal signal = g_strategy_selector.GetValidatedEntrySignal();
            if(signal.has_signal && signal.risk_validated)
            {
               bool execution_success = g_execution_manager.ExecuteSignal(signal);
               g_trading_stats.total_signals++;
               
               if(execution_success)
               {
                  g_trading_stats.executed_trades++;
                  g_trading_stats.last_trade_time = TimeCurrent();
                  LogInfo("거래 실행: " + signal.signal_reason);
               }
            }
         }
         else
         {
            // 거래 비활성화 - 신호만 카운트
            SEntrySignal signal = g_strategy_selector.GetEntrySignal();
            if(signal.has_signal)
            {
               g_trading_stats.total_signals++;
               if(LogLevel >= LOG_LEVEL_DEBUG)
               {
                  LogInfo("신호 감지: " + signal.signal_reason + 
                         " (" + (signal.signal_type == ORDER_TYPE_BUY ? "매수" : "매도") + ")");
               }
            }
         }
         
         // 거래 통계 업데이트 (백테스트/실거래 공통)
         UpdateTradingStats();
      }
      
      // 대시보드 업데이트
      if(Show_Dashboard) UpdateDashboard(current_regime);
      
      // 레짐 변경 마커
      if(Mark_Regime_Changes && g_last_regime != current_regime.dominant_regime)
      {
         MarkRegimeChange(current_regime);
         g_last_regime = current_regime.dominant_regime;
      }
   }
  }
}
//+------------------------------------------------------------------+
//| 대시보드 업데이트 함수                                           |
//+------------------------------------------------------------------+
void UpdateDashboard(SRegimeData &regime_data)
{
   ObjectsDeleteAll(0, "dashboard_");
   
   int panel_height = Show_Trading_Stats ? 200 : 140;
   CreatePanel("dashboard_panel", 10, 10, 250, panel_height, clrBlack, clrWhite);
   
   // 기본 정보
   CreateLabel("dashboard_title", "NAS100 레짐 감지", 20, 15, clrWhite, 10);
   CreateLabel("dashboard_regime", "레짐: " + GetRegimeNameStr(regime_data.dominant_regime), 20, 35, clrAqua, 9);
   CreateLabel("dashboard_confidence", "신뢰도: " + DoubleToString(regime_data.confidence * 100, 0) + "%", 20, 55, clrYellow, 9);
   
   // 현재 세션
   if(g_session_manager != NULL)
   {
      ESessionType current_session = g_session_manager.GetCurrentSession();
      CreateLabel("dashboard_session", "세션: " + GetSessionNameStr(current_session), 20, 75, clrWhite, 8);
   }
   
   // 현재 전략
   if(g_strategy_selector != NULL)
   {
      ENUM_STRATEGY_TYPE current_strategy = g_strategy_selector.GetCurrentStrategy();
      string strategy_name = g_strategy_selector.GetStrategyName(current_strategy);
      CreateLabel("dashboard_strategy", "전략: " + strategy_name, 20, 95, clrLightBlue, 8);
   }
   
   // 거래 통계 (활성화된 경우)
   if(Show_Trading_Stats)
   {
      CreateLabel("dashboard_stats_title", "--- 거래 통계 ---", 20, 115, clrGray, 8);
      CreateLabel("dashboard_signals", "신호: " + IntegerToString(g_trading_stats.total_signals), 20, 135, clrWhite, 8);
      
      if(g_execution_manager != NULL)
      {
         SPositionSummary pos_summary = g_execution_manager.GetPositionSummary();
         CreateLabel("dashboard_positions", "포지션: " + IntegerToString(pos_summary.total_positions), 20, 155, clrWhite, 8);
         
         if(pos_summary.total_positions > 0)
         {
            color profit_color = pos_summary.total_profit >= 0 ? clrLime : clrRed;
            CreateLabel("dashboard_profit", "손익: $" + DoubleToString(pos_summary.total_profit, 2), 20, 175, profit_color, 8);
         }
         else
         {
            CreateLabel("dashboard_executed", "실행: " + IntegerToString(g_trading_stats.executed_trades), 20, 175, clrWhite, 8);
         }
         
         // 거래 활성화 상태 표시
         string trading_status = Enable_Trading ? "거래: 활성" : "거래: 비활성";
         color status_color = Enable_Trading ? clrLime : clrOrange;
         CreateLabel("dashboard_trading_status", trading_status, 150, 155, status_color, 8);
      }
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| 패널 생성 함수                                                   |
//+------------------------------------------------------------------+
void CreatePanel(string name, int x, int y, int width, int height, color bg_color, color border_color)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border_color);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
//| 레이블 생성 함수                                                 |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color text_color, int font_size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
}

//+------------------------------------------------------------------+
//| 레짐 변경 마커 표시 함수                                         |
//+------------------------------------------------------------------+
void MarkRegimeChange(SRegimeData &regime_data)
{
   datetime current_time = TimeCurrent();
   double current_price = iClose(Symbol(), PERIOD_CURRENT, 0);
   
   color marker_color;
   int marker_code;
   
   switch(regime_data.dominant_regime)
   {
      case REGIME_STRONG_BULLISH:
         marker_color = clrGreen; marker_code = 233; break;
      case REGIME_STRONG_BEARISH:
         marker_color = clrRed; marker_code = 234; break;
      case REGIME_CONSOLIDATION:
         marker_color = clrBlue; marker_code = 110; break;
      case REGIME_VOLATILITY_EXPANSION:
         marker_color = clrMagenta; marker_code = 181; break;
      case REGIME_OVERNIGHT_DRIFT:
         marker_color = clrGray; marker_code = 168; break;
      case REGIME_GAP_TRADING:
         marker_color = clrYellow; marker_code = 162; break;
      case REGIME_TECHNICAL_REVERSAL:
         marker_color = clrOrange; marker_code = 174; break;
      default:
         marker_color = clrWhite; marker_code = 160;
   }
   
   string marker_name = "regime_marker_" + TimeToString(current_time, TIME_DATE|TIME_MINUTES);
   
   ObjectCreate(0, marker_name, OBJ_ARROW, 0, current_time, current_price);
   ObjectSetInteger(0, marker_name, OBJPROP_ARROWCODE, marker_code);
   ObjectSetInteger(0, marker_name, OBJPROP_COLOR, marker_color);
   ObjectSetInteger(0, marker_name, OBJPROP_WIDTH, 2);
   
   string tooltip = GetRegimeNameStr(regime_data.dominant_regime) + 
                   " (" + DoubleToString(regime_data.confidence * 100, 0) + "%)";
   ObjectSetString(0, marker_name, OBJPROP_TOOLTIP, tooltip);
   
   ChartRedraw(0);
}