//+------------------------------------------------------------------+
//|                                       RegimeDetection_POC.mq5     |
//|                                              NAS100 MTF System    |
//+------------------------------------------------------------------+
#property copyright "NAS100 MTF System"
#property version   "1.00"
#property script_show_inputs

// 레짐 정의를 위한 열거형
enum ENUM_MARKET_REGIME
{
   REGIME_UNKNOWN = -1,         // 알 수 없음
   REGIME_STRONG_BULLISH = 0,   // 강한 상승 모멘텀
   REGIME_STRONG_BEARISH = 1,   // 강한 하락 모멘텀
   REGIME_CONSOLIDATION = 2,    // 통합 레인지
   REGIME_VOLATILITY_EXPANSION = 3, // 변동성 확장
   REGIME_OVERNIGHT_DRIFT = 4,  // 오버나이트 드리프트
   REGIME_GAP_PATTERN = 5,      // 갭 트레이딩 패턴
   REGIME_TECHNICAL_REVERSAL = 6 // 기술적 되돌림
};

// 세션 유형 열거형
enum ENUM_SESSION_TYPE
{
   SESSION_UNKNOWN = 0,  // 알 수 없음
   SESSION_ASIA,         // 아시아 세션
   SESSION_EUROPE,       // 유럽 세션
   SESSION_US            // 미국 세션
};

// 지지/저항 레벨 구조체
struct SSupportResistanceLevel
{
   double price;         // 레벨 가격
   int strength;         // 레벨 강도 (터치 횟수)
   bool is_resistance;   // true = 저항, false = 지지
   datetime first_touch; // 첫 터치 시간
   datetime last_touch;  // 마지막 터치 시간
};

// 타임프레임 데이터 구조체
struct STimeframeData {
   ENUM_TIMEFRAMES timeframe;     // 타임프레임
   MqlRates rates[];              // 가격 데이터 배열
   int bars_count;                // 저장된 봉 개수
   datetime last_update;          // 마지막 업데이트 시간
   ENUM_MARKET_REGIME regime;     // 이 타임프레임의 레짐
   double regime_confidence;      // 레짐 신뢰도 (0.0 ~ 1.0)
};

// 타임프레임 조합 구조체
struct STimeframeCombo {
   ENUM_TIMEFRAMES primary_tf;    // 주 타임프레임 (진입/청산용, 보통 M5)
   ENUM_TIMEFRAMES confirm_tf;    // 확인 타임프레임 (방향/패턴 확인용, 보통 M30)
   ENUM_TIMEFRAMES filter_tf;     // 필터 타임프레임 (큰 그림/추세 확인용, 보통 H4)
   double weights[3];             // 각 타임프레임 가중치 [주, 확인, 필터]
};

// 입력 파라미터
input int ADX_Period = 14;      // ADX 기간
input int ATR_Period = 14;      // ATR 기간
input int RSI_Period = 14;      // RSI 기간
input int BB_Period = 20;       // 볼린저 밴드 기간
input double BB_Deviation = 2.0; // 볼린저 밴드 표준편차
input int Lookback = 100;       // 분석할 봉 개수

// 레짐에 대한 문자열 설명 반환
string GetRegimeDescription(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_STRONG_BULLISH: return "강한 상승 모멘텀";
      case REGIME_STRONG_BEARISH: return "강한 하락 모멘텀";
      case REGIME_CONSOLIDATION: return "통합 레인지";
      case REGIME_VOLATILITY_EXPANSION: return "변동성 확장";
      case REGIME_OVERNIGHT_DRIFT: return "오버나이트 드리프트";
      case REGIME_GAP_PATTERN: return "갭 트레이딩 패턴";
      case REGIME_TECHNICAL_REVERSAL: return "기술적 되돌림";
      default: return "알 수 없음";
   }
}

// 타임프레임별 적절한 봉 개수 계산 함수
int CalculateOptimalBars(ENUM_TIMEFRAMES timeframe, int base_lookback = 100)
{
   // 기준 타임프레임(M5)에 대한 비율 계산
   double ratio = 1.0;
   
   switch(timeframe)
   {
      case PERIOD_M1:  ratio = 5.0; break;  // M5의 5배
      case PERIOD_M5:  ratio = 1.0; break;  // 기준
      case PERIOD_M15: ratio = 0.6; break;  // M5의 60%
      case PERIOD_M30: ratio = 0.4; break;  // M5의 40%
      case PERIOD_H1:  ratio = 0.3; break;  // M5의 30%
      case PERIOD_H4:  ratio = 0.2; break;  // M5의 20%
      case PERIOD_D1:  ratio = 0.1; break;  // M5의 10%
      default: ratio = 1.0;
   }
   
   // 최소 봉 개수 보장 (너무 적은 경우 방지)
   int optimal_bars = (int)(base_lookback * ratio);
   return MathMax(optimal_bars, 20);  // 최소 20개 봉 보장
}

// 타임프레임 데이터 초기화 함수
bool InitializeTimeframeData(STimeframeData &tf_data, ENUM_TIMEFRAMES timeframe, int lookback)
{
   // 구조체 초기화
   tf_data.timeframe = timeframe;
   tf_data.bars_count = 0;
   tf_data.last_update = 0;
   tf_data.regime = REGIME_UNKNOWN;
   tf_data.regime_confidence = 0.0;
   
   // 최적 봉 개수 계산
   int optimal_bars = CalculateOptimalBars(timeframe, lookback);
   
   // 가격 데이터 로드
   ArraySetAsSeries(tf_data.rates, true);
   int copied = CopyRates(Symbol(), timeframe, 0, optimal_bars, tf_data.rates);
   
   if(copied <= 0) {
      Print("InitializeTimeframeData: ", EnumToString(timeframe), " 데이터 복사 실패 - ", GetLastError());
      return false;
   }
   
   tf_data.bars_count = copied;
   tf_data.last_update = TimeCurrent();
   
   Print("InitializeTimeframeData: ", EnumToString(timeframe), " 데이터 ", copied, "봉 로드 완료");
   return true;
}

// 타임프레임 데이터 업데이트 함수
bool UpdateTimeframeData(STimeframeData &tf_data, int lookback)
{
   // 최적 봉 개수 계산
   int optimal_bars = CalculateOptimalBars(tf_data.timeframe, lookback);
   
   // 가격 데이터 업데이트
   ArraySetAsSeries(tf_data.rates, true);
   int copied = CopyRates(Symbol(), tf_data.timeframe, 0, optimal_bars, tf_data.rates);
   
   if(copied <= 0) {
      Print("UpdateTimeframeData: ", EnumToString(tf_data.timeframe), " 데이터 복사 실패 - ", GetLastError());
      return false;
   }
   
   tf_data.bars_count = copied;
   tf_data.last_update = TimeCurrent();
   
   return true;
}

// 타임프레임별 레짐 감지 함수
bool DetectRegimeForTimeframe(STimeframeData &tf_data, 
                           int adx_period, int atr_period, int rsi_period, 
                           int bb_period, double bb_deviation)
{
   // 지표 핸들 생성
   int adx_handle = iADX(Symbol(), tf_data.timeframe, adx_period);
   int atr_handle = iATR(Symbol(), tf_data.timeframe, atr_period);
   int rsi_handle = iRSI(Symbol(), tf_data.timeframe, rsi_period, PRICE_CLOSE);
   int bb_handle = iBands(Symbol(), tf_data.timeframe, bb_period, bb_deviation, 0, PRICE_CLOSE);
   
   // 핸들이 유효한지 확인
   if(adx_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || 
      rsi_handle == INVALID_HANDLE || bb_handle == INVALID_HANDLE)
   {
      Print("DetectRegimeForTimeframe: 지표 핸들 생성 실패 - ", GetLastError());
      return false;
   }
   
   // 데이터 버퍼 준비
   double adx_buf[], di_plus_buf[], di_minus_buf[];
   double atr_buf[], atr_prev_buf[];
   double rsi_buf[];
   double bb_upper[], bb_lower[], bb_middle[];
   
   // 배열을 시계열 순서로 설정
   ArraySetAsSeries(adx_buf, true);
   ArraySetAsSeries(di_plus_buf, true);
   ArraySetAsSeries(di_minus_buf, true);
   ArraySetAsSeries(atr_buf, true);
   ArraySetAsSeries(atr_prev_buf, true);
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);
   
   // 분석에 필요한 데이터 수 결정 (최소 30개)
   int lookback = MathMax(30, MathMin(tf_data.bars_count, 100));
   
   // 데이터 복사
   if(CopyBuffer(adx_handle, 0, 0, lookback, adx_buf) <= 0 ||
      CopyBuffer(adx_handle, 1, 0, lookback, di_plus_buf) <= 0 ||
      CopyBuffer(adx_handle, 2, 0, lookback, di_minus_buf) <= 0 ||
      CopyBuffer(atr_handle, 0, 0, lookback, atr_buf) <= 0 ||
      CopyBuffer(atr_handle, 0, lookback, lookback, atr_prev_buf) <= 0 ||
      CopyBuffer(rsi_handle, 0, 0, lookback, rsi_buf) <= 0 ||
      CopyBuffer(bb_handle, 0, 0, lookback, bb_middle) <= 0 ||
      CopyBuffer(bb_handle, 1, 0, lookback, bb_upper) <= 0 ||
      CopyBuffer(bb_handle, 2, 0, lookback, bb_lower) <= 0)
   {
      Print("DetectRegimeForTimeframe: 지표 데이터 복사 실패 - ", GetLastError());
      
      // 핸들 해제
      IndicatorRelease(adx_handle);
      IndicatorRelease(atr_handle);
      IndicatorRelease(rsi_handle);
      IndicatorRelease(bb_handle);
      
      return false;
   }
   
   // 레짐 점수 저장용 배열
   double regime_scores[8] = {0}; // REGIME_UNKNOWN부터 모든 레짐 포함
   
   // === 각 레짐 점수 계산 (현재 봉 기준) ===
   
   // 1. 강한 상승 모멘텀 점수
   if(adx_buf[0] > 25 && di_plus_buf[0] > di_minus_buf[0] && rsi_buf[0] > 60)
   {
      double score_strength = MathMin(1.0, (adx_buf[0] - 25) / 25); // 25-50 ADX 범위를 0-1로 정규화
      regime_scores[REGIME_STRONG_BULLISH] = 0.5 + score_strength * 0.5; // 0.5-1.0 범위의 점수
   }
   
   // 2. 강한 하락 모멘텀 점수
   if(adx_buf[0] > 25 && di_minus_buf[0] > di_plus_buf[0] && rsi_buf[0] < 40)
   {
      double score_strength = MathMin(1.0, (adx_buf[0] - 25) / 25);
      regime_scores[REGIME_STRONG_BEARISH] = 0.5 + score_strength * 0.5;
   }
   
   // 3. 통합 레인지 점수
   double bb_width = (bb_upper[0] - bb_lower[0]) / bb_middle[0]; // 상대적 밴드 폭
   
   if(adx_buf[0] < 20 && rsi_buf[0] > 40 && rsi_buf[0] < 60)
   {
      double narrow_band_factor = MathMax(0, 1.0 - bb_width * 100); // 좁은 밴드일수록 높은 점수
      regime_scores[REGIME_CONSOLIDATION] = 0.3 + narrow_band_factor * 0.7;
   }
   
   // 4. 변동성 확장 점수
   double atr_change = (atr_buf[0] / MathMax(atr_prev_buf[0], 0.00001) - 1.0) * 100;
   
   if(atr_change > 10)
   {
      double expansion_factor = MathMin(1.0, atr_change / 30); // 10-30% ATR 증가를 0-1로 정규화
      regime_scores[REGIME_VOLATILITY_EXPANSION] = 0.3 + expansion_factor * 0.7;
   }
   
   // 5. 갭 트레이딩 패턴 점수 (시가-전봉종가 갭 확인)
   bool has_gap = false;
   double gap_size = 0;
   
   if(tf_data.bars_count >= 2)
   {
      gap_size = MathAbs(tf_data.rates[0].open - tf_data.rates[1].close);
      double avg_range = 0;
      
      // 평균 캔들 범위 계산
      for(int i = 0; i < MathMin(5, tf_data.bars_count); i++)
      {
         avg_range += (tf_data.rates[i].high - tf_data.rates[i].low);
      }
      avg_range /= MathMin(5, tf_data.bars_count);
      
      // 갭이 평균 범위의 30% 이상이면 점수 계산
      if(gap_size > avg_range * 0.3)
      {
         has_gap = true;
         double gap_factor = MathMin(1.0, gap_size / (avg_range * 1.5));
         regime_scores[REGIME_GAP_PATTERN] = 0.3 + gap_factor * 0.7;
      }
   }
   
   // 6. 기술적 되돌림 점수 (RSI 다이버전스 단순화)
   if((rsi_buf[1] < 30 && rsi_buf[0] > rsi_buf[1] && tf_data.rates[0].close > tf_data.rates[1].close) || 
      (rsi_buf[1] > 70 && rsi_buf[0] < rsi_buf[1] && tf_data.rates[0].close < tf_data.rates[1].close))
   {
      double strength = 0;
      
      if(rsi_buf[1] < 30) // 과매도에서 반등
      {
         strength = MathMin(1.0, (30 - rsi_buf[1]) / 15); // 15-30 RSI 범위를 1.0-0으로 정규화
      }
      else // 과매수에서 반락
      {
         strength = MathMin(1.0, (rsi_buf[1] - 70) / 15); // 70-85 RSI 범위를 0-1.0으로 정규화
      }
      
      regime_scores[REGIME_TECHNICAL_REVERSAL] = 0.4 + strength * 0.6;
   }
   
   // 7. 오버나이트 드리프트 점수
   MqlDateTime dt;
   TimeToStruct(tf_data.rates[0].time, dt);
   
   // 아시아 세션 시간대 (GMT 0-8시)인지 확인
   bool is_overnight = (dt.hour >= 0 && dt.hour < 8);
   
   if(is_overnight && adx_buf[0] < 20) // 낮은 방향성
   {
      // ATR과 캔들 크기로 낮은 변동성 확인
      double overnight_avg_atr = 0;
      for(int i = 0; i < MathMin(20, lookback); i++)
      {
         overnight_avg_atr += atr_buf[i];
      }
      overnight_avg_atr /= MathMin(20, lookback);
      
      // 현재 ATR이 평균보다 낮으면 점수 계산
      if(atr_buf[0] < overnight_avg_atr * 0.8)
      {
         double drift_factor = MathMax(0, 1.0 - atr_buf[0] / overnight_avg_atr);
         regime_scores[REGIME_OVERNIGHT_DRIFT] = 0.2 + drift_factor * 0.6;
      }
   }
   
   // 최대 점수를 가진 레짐 찾기
   int max_regime_idx = ArrayMaximum(regime_scores, 0, 8);
   double max_score = regime_scores[max_regime_idx];
   
   // 점수가 0.4 이상인 경우에만 유효한 레짐으로 간주
   if(max_score >= 0.4)
   {
      tf_data.regime = (ENUM_MARKET_REGIME)max_regime_idx;
      tf_data.regime_confidence = max_score;
   }
   else
   {
      tf_data.regime = REGIME_UNKNOWN;
      tf_data.regime_confidence = 0.0;
   }
   
   // 결과 출력
   Print("타임프레임 ", EnumToString(tf_data.timeframe), " 레짐 감지: ", 
         GetRegimeDescription(tf_data.regime), " (신뢰도: ", 
         DoubleToString(tf_data.regime_confidence, 2), ")");
   
   // 핸들 해제
   IndicatorRelease(adx_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(bb_handle);
   
   return true;
}

// 다중 타임프레임 레짐 통합 함수
ENUM_MARKET_REGIME IntegrateTimeframeRegimes(const STimeframeData &primary_tf, 
                                          const STimeframeData &confirm_tf, 
                                          const STimeframeData &filter_tf,
                                          STimeframeCombo &combo,
                                          double &integrated_confidence)
{
   // 레짐 점수 통합 배열 (각 레짐에 대한 가중 평균 점수)
   double integrated_scores[8] = {0}; // REGIME_UNKNOWN 포함 모든 레짐
   
   // 각 타임프레임의 레짐 신뢰도를 해당 레짐 점수로 사용
   // 만약 레짐이 감지되지 않았다면 (REGIME_UNKNOWN) 해당 레짐 점수는 0
   
   // 주 타임프레임 레짐 반영
   if(primary_tf.regime != REGIME_UNKNOWN)
   {
      integrated_scores[primary_tf.regime] += primary_tf.regime_confidence * combo.weights[0];
   }
   
   // 확인 타임프레임 레짐 반영
   if(confirm_tf.regime != REGIME_UNKNOWN)
   {
      integrated_scores[confirm_tf.regime] += confirm_tf.regime_confidence * combo.weights[1];
   }
   
   // 필터 타임프레임 레짐 반영
   if(filter_tf.regime != REGIME_UNKNOWN)
   {
      integrated_scores[filter_tf.regime] += filter_tf.regime_confidence * combo.weights[2];
   }
   
   // 최대 점수를 가진 레짐 찾기
   int max_regime_idx = ArrayMaximum(integrated_scores, 0, 8);
   double max_score = integrated_scores[max_regime_idx];
   
   // 타임프레임 일치 보너스
   int agreement_count = 0;
   
   // 각 타임프레임 쌍 비교
   if(primary_tf.regime == confirm_tf.regime && primary_tf.regime != REGIME_UNKNOWN) agreement_count++;
   if(confirm_tf.regime == filter_tf.regime && confirm_tf.regime != REGIME_UNKNOWN) agreement_count++;
   if(primary_tf.regime == filter_tf.regime && primary_tf.regime != REGIME_UNKNOWN) agreement_count++;
   
   // 완전 일치 시 추가 보너스
   if(agreement_count == 3) // 모든 타임프레임이 동일한 레짐
   {
      max_score *= 1.5; // 50% 보너스
   }
   else if(agreement_count > 0) // 부분 일치
   {
      max_score *= (1.0 + 0.1 * agreement_count); // 10%씩 보너스
   }
   
   // 신뢰도 계산 (최대 1.0)
   integrated_confidence = MathMin(max_score, 1.0);
   
   // 일정 신뢰도(0.3) 이상일 때만 레짐 반환, 그 외에는 UNKNOWN
   if(integrated_confidence >= 0.3)
   {
      return (ENUM_MARKET_REGIME)max_regime_idx;
   }
   else
   {
      return REGIME_UNKNOWN;
   }
}

// 현재 세션 감지 함수
ENUM_SESSION_TYPE DetectCurrentSession()
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   
   // GMT 기준 시간 (서버 시간 오프셋이 있다면 조정 필요)
   int hour = dt.hour;
   
   // 간단한 세션 판별 (GMT 기준)
   if(hour >= 0 && hour < 8) return SESSION_ASIA;
   if(hour >= 8 && hour < 16) return SESSION_EUROPE;
   if(hour >= 16 && hour < 24) return SESSION_US;
   
   return SESSION_UNKNOWN;
}

// 단순화된 레이블 생성 함수 - 색상 개선 버전
void CreateRegimeLabels(const ENUM_MARKET_REGIME &regimes[], const datetime &times[], const MqlRates &rates[], int count)
{
   // 기존 레이블 삭제
   ObjectsDeleteAll(0, "regime_");
   
   // 최근 레짐 변화만 표시 (최대 3개)
   int displayed = 0;
   
   for(int i = 0; i < count && displayed < 3; i++)
   {
      // 레짐이 변경된 경우에만 표시
      if(i == 0 || regimes[i] != regimes[i-1])
      {
         string label_name = "regime_" + IntegerToString(displayed);
         string regime_text = GetRegimeDescription(regimes[i]);
         
         // 단순 텍스트 레이블만 생성 - 모두 흰색으로
         ObjectCreate(0, label_name, OBJ_TEXT, 0, times[i], rates[i].low);
         ObjectSetString(0, label_name, OBJPROP_TEXT, regime_text);
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrWhite); // 모든 텍스트 흰색으로
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
         
         displayed++;
      }
   }
   
   // 차트 리프레시
   ChartRedraw(0);
}

// 간소화된 레짐 표시 함수
void ShowSimplifiedRegimes(const STimeframeData &primary, 
                          const STimeframeData &confirm, 
                          const STimeframeData &filter,
                          ENUM_MARKET_REGIME integrated_regime,
                          double integrated_confidence)
{
   // 기존 표시 삭제
   ObjectsDeleteAll(0, "mtf_");
   
   // 반투명 배경 패널 (선택사항)
   ObjectCreate(0, "mtf_panel", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_XDISTANCE, 5);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_YSIZE, 140);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_BACK, false);
   ObjectSetInteger(0, "mtf_panel", OBJPROP_ZORDER, 0);
   
   int y_offset = 20;
   
   // 현재 세션 간단히 표시
   ENUM_SESSION_TYPE current_session = DetectCurrentSession();
   string session_name = "SESSION: ";
   switch(current_session)
   {
      case SESSION_ASIA: session_name += "ASIA"; break;
      case SESSION_EUROPE: session_name += "EUROPE"; break;
      case SESSION_US: session_name += "US"; break;
      default: session_name += "UNKNOWN";
   }
   
   ObjectCreate(0, "mtf_session", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_session", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_session", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_session", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_session", OBJPROP_TEXT, session_name);
   ObjectSetInteger(0, "mtf_session", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "mtf_session", OBJPROP_FONTSIZE, 9);
   y_offset += 25;
   
   // 간소화된 통합 레짐 표시
   string regime_text = "INTEGRATED REGIME: " + GetRegimeDescription(integrated_regime) + 
                      " (" + DoubleToString(integrated_confidence * 100, 0) + "%)";
   
   ObjectCreate(0, "mtf_regime", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_regime", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_regime", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_regime", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_regime", OBJPROP_TEXT, regime_text);
   ObjectSetInteger(0, "mtf_regime", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "mtf_regime", OBJPROP_FONTSIZE, 9);
   y_offset += 25;
   
   // 타임프레임별 간략 정보
   ObjectCreate(0, "mtf_m5", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_m5", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_m5", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_m5", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_m5", OBJPROP_TEXT, "M5: " + GetRegimeDescription(primary.regime) + 
                  " (" + DoubleToString(primary.regime_confidence * 100, 0) + "%)");
   ObjectSetInteger(0, "mtf_m5", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "mtf_m5", OBJPROP_FONTSIZE, 9);
   y_offset += 20;
   
   ObjectCreate(0, "mtf_m30", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_m30", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_m30", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_m30", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_m30", OBJPROP_TEXT, "M30: " + GetRegimeDescription(confirm.regime) + 
                  " (" + DoubleToString(confirm.regime_confidence * 100, 0) + "%)");
   ObjectSetInteger(0, "mtf_m30", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "mtf_m30", OBJPROP_FONTSIZE, 9);
   y_offset += 20;
   
   ObjectCreate(0, "mtf_h4", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_h4", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_h4", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_h4", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_h4", OBJPROP_TEXT, "H4: " + GetRegimeDescription(filter.regime) + 
                  " (" + DoubleToString(filter.regime_confidence * 100, 0) + "%)");
   ObjectSetInteger(0, "mtf_h4", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "mtf_h4", OBJPROP_FONTSIZE, 9);
   y_offset += 20;
   
   // 일치도 표시
   int agreement_count = 0;
   if(primary.regime == confirm.regime && primary.regime != REGIME_UNKNOWN) agreement_count++;
   if(confirm.regime == filter.regime && confirm.regime != REGIME_UNKNOWN) agreement_count++;
   if(primary.regime == filter.regime && primary.regime != REGIME_UNKNOWN) agreement_count++;
   
   string match_text = "MATCH: " + IntegerToString(agreement_count) + "/3";
   color match_color;
   switch(agreement_count)
   {
      case 3: match_color = clrLime; break;
      case 2: match_color = clrYellow; break;
      case 1: match_color = clrOrange; break;
      default: match_color = clrRed;
   }
   
   ObjectCreate(0, "mtf_match", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_match", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_match", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_match", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_match", OBJPROP_TEXT, match_text);
   ObjectSetInteger(0, "mtf_match", OBJPROP_COLOR, match_color);
   ObjectSetInteger(0, "mtf_match", OBJPROP_FONTSIZE, 9);
   
   ChartRedraw(0);
}

// 다중 타임프레임 레짐 시각화 함수 (개선 버전 - 텍스트 겹침 수정)
void ShowDetailedTimeframeRegimes(const STimeframeData &primary, 
                                 const STimeframeData &confirm, 
                                 const STimeframeData &filter,
                                 ENUM_MARKET_REGIME integrated_regime,
                                 double integrated_confidence)
{
   // 기존 표시 삭제
   ObjectsDeleteAll(0, "mtf_");
   
   // 현재 세션 감지
   ENUM_SESSION_TYPE current_session = DetectCurrentSession();
   string session_name;
   
   // 세션 정보 설정
   switch(current_session)
   {
      case SESSION_ASIA:
         session_name = "ASIA";
         break;
      case SESSION_EUROPE:
         session_name = "EUROPE";
         break;
      case SESSION_US:
         session_name = "US";
         break;
      default:
         session_name = "UNKNOWN";
   }
   
   // y 좌표 시작점 설정
   int y_offset = 20;
   
   // 세션 표시
   ObjectCreate(0, "mtf_session", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_session", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_session", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_session", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_session", OBJPROP_TEXT, "SESSION: " + session_name);
   ObjectSetInteger(0, "mtf_session", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "mtf_session", OBJPROP_FONTSIZE, 9);
   y_offset += 30; // 간격 증가
   
   // 통합 레짐 표시
   string integrated_text = "INTEGRATED REGIME:";
   ObjectCreate(0, "mtf_integrated_header", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_integrated_header", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_integrated_header", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_integrated_header", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_integrated_header", OBJPROP_TEXT, integrated_text);
   ObjectSetInteger(0, "mtf_integrated_header", OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, "mtf_integrated_header", OBJPROP_FONTSIZE, 9);
   y_offset += 20;
   
   // 통합 레짐 값 (같은 라인의 오른쪽으로 약간 들여쓰기)
   string regime_value = GetRegimeDescription(integrated_regime) + 
                       " (" + DoubleToString(integrated_confidence * 100, 0) + "%)";
   ObjectCreate(0, "mtf_integrated_value", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_integrated_value", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_integrated_value", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, "mtf_integrated_value", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_integrated_value", OBJPROP_TEXT, regime_value);
   ObjectSetInteger(0, "mtf_integrated_value", OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, "mtf_integrated_value", OBJPROP_FONTSIZE, 9);
   y_offset += 30; // 추가 간격
   
   // 타임프레임 헤더
   ObjectCreate(0, "mtf_tf_header", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_tf_header", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_tf_header", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_tf_header", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_tf_header", OBJPROP_TEXT, "TIMEFRAME REGIMES:");
   ObjectSetInteger(0, "mtf_tf_header", OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, "mtf_tf_header", OBJPROP_FONTSIZE, 9);
   y_offset += 20;
   
   // 타임프레임 정보 배열
   ENUM_TIMEFRAMES tf_timeframes[3];
   ENUM_MARKET_REGIME tf_regimes[3];
   double tf_confidences[3];
   
   // 정보 복사
   tf_timeframes[0] = primary.timeframe;
   tf_regimes[0] = primary.regime;
   tf_confidences[0] = primary.regime_confidence;
   
   tf_timeframes[1] = confirm.timeframe;
   tf_regimes[1] = confirm.regime;
   tf_confidences[1] = confirm.regime_confidence;
   
   tf_timeframes[2] = filter.timeframe;
   tf_regimes[2] = filter.regime;
   tf_confidences[2] = filter.regime_confidence;
   
   // 각 타임프레임별 정보 표시 (간격 더 넓게)
   for(int i = 0; i < 3; i++)
   {
      // 타임프레임 이름과 레짐 정보
      string label = EnumToString(tf_timeframes[i]) + ": " + GetRegimeDescription(tf_regimes[i]) + 
                    " (" + DoubleToString(tf_confidences[i] * 100, 0) + "%)";
      string obj_name = "mtf_tf_" + IntegerToString(i);
      
      ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y_offset);
      ObjectSetString(0, obj_name, OBJPROP_TEXT, label);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 9);
      
      y_offset += 25; // 간격 증가
   }
   
   // 일치도 계산 및 표시 (추가 간격)
   y_offset += 5;
   int agreement_count = 0;
   if(primary.regime == confirm.regime && primary.regime != REGIME_UNKNOWN) agreement_count++;
   if(confirm.regime == filter.regime && confirm.regime != REGIME_UNKNOWN) agreement_count++;
   if(primary.regime == filter.regime && primary.regime != REGIME_UNKNOWN) agreement_count++;
   
   // 일치도를 통일된 형식으로 표시
   string agreement_label = "MATCH: " + IntegerToString(agreement_count) + "/3";
   ObjectCreate(0, "mtf_agreement", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "mtf_agreement", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "mtf_agreement", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "mtf_agreement", OBJPROP_YDISTANCE, y_offset);
   ObjectSetString(0, "mtf_agreement", OBJPROP_TEXT, agreement_label);
   
   // 일치도에 따른 색상 설정
   color agreement_color;
   switch(agreement_count)
   {
      case 3: agreement_color = clrLime; break;    // 완전 일치
      case 2: agreement_color = clrYellow; break;  // 2개 일치
      case 1: agreement_color = clrOrange; break;  // 1개만 일치
      default: agreement_color = clrRed;           // 일치 없음
   }
   
   ObjectSetInteger(0, "mtf_agreement", OBJPROP_COLOR, agreement_color);
   ObjectSetInteger(0, "mtf_agreement", OBJPROP_FONTSIZE, 9);
   
   // 차트 리프레시
   ChartRedraw(0);
}

// 단순화된 세션 정보 표시 함수
void ShowSessionInfo()
{
   // 기존 표시 삭제
   ObjectsDeleteAll(0, "session_");
   
   // 현재 세션 감지
   ENUM_SESSION_TYPE current_session = DetectCurrentSession();
   string session_name;
   color session_color;
   
   // 세션 정보 설정
   switch(current_session)
   {
      case SESSION_ASIA:
         session_name = "ASIA";
         session_color = clrDarkOrchid;
         break;
      case SESSION_EUROPE:
         session_name = "EUROPE";
         session_color = clrDarkBlue;
         break;
      case SESSION_US:
         session_name = "US";
         session_color = clrDarkGreen;
         break;
      default:
         session_name = "UNKNOWN";
         session_color = clrGray;
   }
   
   // 세션 이름만 간단하게 표시
   ObjectCreate(0, "session_label", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "session_label", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "session_label", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "session_label", OBJPROP_YDISTANCE, 20);
   ObjectSetString(0, "session_label", OBJPROP_TEXT, session_name);
   ObjectSetInteger(0, "session_label", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "session_label", OBJPROP_FONTSIZE, 9);
   
   // 차트 리프레시
   ChartRedraw(0);
}


// 지지/저항 레벨 감지 함수
void DetectAndShowReducedSupportResistanceLevels(int lookback = 200, int min_touches = 2, int max_levels = 5)
{
   // 기존 레벨 삭제
   ObjectsDeleteAll(0, "sr_level_");
   
   // 가격 데이터 가져오기
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), Period(), 0, lookback, rates);
   
   if(copied <= 0) return;
   
   // 피봇 고점/저점 찾기
   double pivot_highs[], pivot_lows[];
   int pivot_high_count = 0, pivot_low_count = 0;
   
   // 간단한 피봇 감지 (좌우 2개 봉과 비교)
   for(int i = 2; i < copied - 2; i++)
   {
      // 피봇 고점
      if(rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high &&
         rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high)
      {
         ArrayResize(pivot_highs, pivot_high_count + 1);
         pivot_highs[pivot_high_count++] = rates[i].high;
      }
      
      // 피봇 저점
      if(rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low &&
         rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low)
      {
         ArrayResize(pivot_lows, pivot_low_count + 1);
         pivot_lows[pivot_low_count++] = rates[i].low;
      }
   }
   
   // 피봇 점들을 지지/저항 레벨로 클러스터링
   const double cluster_range = 0.0005 * SymbolInfoDouble(Symbol(), SYMBOL_ASK); // 가격의 0.05%
   
   // 저항 레벨 클러스터링
   SSupportResistanceLevel resistance_levels[];
   int resistance_count = 0;
   
   for(int i = 0; i < pivot_high_count; i++)
   {
      bool found_cluster = false;
      
      // 기존 클러스터에 추가 가능한지 확인
      for(int j = 0; j < resistance_count; j++)
      {
         if(MathAbs(pivot_highs[i] - resistance_levels[j].price) < cluster_range)
         {
            // 기존 클러스터에 추가
            resistance_levels[j].price = (resistance_levels[j].price * resistance_levels[j].strength + pivot_highs[i]) / (resistance_levels[j].strength + 1);
            resistance_levels[j].strength++;
            found_cluster = true;
            break;
         }
      }
      
      // 새 클러스터 생성
      if(!found_cluster)
      {
         ArrayResize(resistance_levels, resistance_count + 1);
         resistance_levels[resistance_count].price = pivot_highs[i];
         resistance_levels[resistance_count].strength = 1;
         resistance_levels[resistance_count].is_resistance = true;
         resistance_count++;
      }
   }
   // 지지 레벨 클러스터링 (저항과 유사한 로직)
   SSupportResistanceLevel support_levels[];
   int support_count = 0;
   
   for(int i = 0; i < pivot_low_count; i++)
   {
      bool found_cluster = false;
      
      for(int j = 0; j < support_count; j++)
      {
         if(MathAbs(pivot_lows[i] - support_levels[j].price) < cluster_range)
         {
            support_levels[j].price = (support_levels[j].price * support_levels[j].strength + pivot_lows[i]) / (support_levels[j].strength + 1);
            support_levels[j].strength++;
            found_cluster = true;
            break;
         }
      }
      
      if(!found_cluster)
      {
         ArrayResize(support_levels, support_count + 1);
         support_levels[support_count].price = pivot_lows[i];
         support_levels[support_count].strength = 1;
         support_levels[support_count].is_resistance = false;
         support_count++;
      }
   }
   
   // 강한 레벨만 표시 (min_touches 이상)
   for(int i = 0; i < resistance_count; i++)
   {
      if(resistance_levels[i].strength >= min_touches)
      {
         string level_name = "sr_level_r_" + IntegerToString(i);
         
         // 수평선 생성
         ObjectCreate(0, level_name, OBJ_HLINE, 0, 0, resistance_levels[i].price);
         ObjectSetInteger(0, level_name, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, level_name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(0, level_name, OBJPROP_WIDTH, resistance_levels[i].strength > 3 ? 2 : 1);
         
         // 레이블 추가
         string label_name = "sr_level_r_label_" + IntegerToString(i);
         ObjectCreate(0, label_name, OBJ_TEXT, 0, rates[0].time, resistance_levels[i].price);
         ObjectSetString(0, label_name, OBJPROP_TEXT, "R (" + IntegerToString(resistance_levels[i].strength) + ")");
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
      }
   }
   
   for(int i = 0; i < support_count; i++)
   {
      if(support_levels[i].strength >= min_touches)
      {
         string level_name = "sr_level_s_" + IntegerToString(i);
         
         // 수평선 생성
         ObjectCreate(0, level_name, OBJ_HLINE, 0, 0, support_levels[i].price);
         ObjectSetInteger(0, level_name, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, level_name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(0, level_name, OBJPROP_WIDTH, support_levels[i].strength > 3 ? 2 : 1);
         
         // 레이블 추가
         string label_name = "sr_level_s_label_" + IntegerToString(i);
         ObjectCreate(0, label_name, OBJ_TEXT, 0, rates[0].time, support_levels[i].price);
         ObjectSetString(0, label_name, OBJPROP_TEXT, "S (" + IntegerToString(support_levels[i].strength) + ")");
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
      }
   }
   
   // 차트 리프레시
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| 스크립트 프로그램 시작 함수                                        |
//+------------------------------------------------------------------+
void OnStart()
{
   // 다중 타임프레임 설정
   ENUM_TIMEFRAMES primary_tf = PERIOD_M5;   // 주 타임프레임
   ENUM_TIMEFRAMES confirm_tf = PERIOD_M30;  // 확인 타임프레임
   ENUM_TIMEFRAMES filter_tf = PERIOD_H4;    // 필터 타임프레임
   
   // 타임프레임 조합 설정
   STimeframeCombo combo;
   combo.primary_tf = primary_tf;
   combo.confirm_tf = confirm_tf;
   combo.filter_tf = filter_tf;
   combo.weights[0] = 0.5;  // 주 타임프레임 가중치
   combo.weights[1] = 0.3;  // 확인 타임프레임 가중치
   combo.weights[2] = 0.2;  // 필터 타임프레임 가중치
   
   // 타임프레임별 데이터 초기화
   STimeframeData tf_primary, tf_confirm, tf_filter;
   
   Print("=== 다중 타임프레임 레짐 감지 시스템 ===");
   Print("심볼: ", Symbol());
   Print("타임프레임: ", EnumToString(primary_tf), ", ", 
                         EnumToString(confirm_tf), ", ", 
                         EnumToString(filter_tf));
   
   // 각 타임프레임 데이터 초기화
   if(!InitializeTimeframeData(tf_primary, primary_tf, Lookback))
   {
      Print("주 타임프레임 데이터 초기화 실패");
      return;
   }
   
   if(!InitializeTimeframeData(tf_confirm, confirm_tf, Lookback))
   {
      Print("확인 타임프레임 데이터 초기화 실패");
      return;
   }
   
   if(!InitializeTimeframeData(tf_filter, filter_tf, Lookback))
   {
      Print("필터 타임프레임 데이터 초기화 실패");
      return;
   }
   
   // 각 타임프레임에 대한 레짐 감지
   if(!DetectRegimeForTimeframe(tf_primary, ADX_Period, ATR_Period, RSI_Period, BB_Period, BB_Deviation))
   {
      Print("주 타임프레임 레짐 감지 실패");
      return;
   }
   
   if(!DetectRegimeForTimeframe(tf_confirm, ADX_Period, ATR_Period, RSI_Period, BB_Period, BB_Deviation))
   {
      Print("확인 타임프레임 레짐 감지 실패");
      return;
   }
   
   if(!DetectRegimeForTimeframe(tf_filter, ADX_Period, ATR_Period, RSI_Period, BB_Period, BB_Deviation))
   {
      Print("필터 타임프레임 레짐 감지 실패");
      return;
   }
   
   // 다중 타임프레임 레짐 통합
   double integrated_confidence = 0.0;
   ENUM_MARKET_REGIME integrated_regime = IntegrateTimeframeRegimes(
      tf_primary, tf_confirm, tf_filter, combo, integrated_confidence);
   
   Print("통합 레짐: ", GetRegimeDescription(integrated_regime), 
         " (신뢰도: ", DoubleToString(integrated_confidence, 2), ")");
   
   // 원래 코드를 사용한 레짐 감지 (단일 타임프레임, 비교용)
   // 지표 핸들 생성
   int adx_handle = iADX(Symbol(), Period(), ADX_Period);
   int atr_handle = iATR(Symbol(), Period(), ATR_Period);
   int rsi_handle = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE);
   int bb_handle = iBands(Symbol(), Period(), BB_Period, BB_Deviation, 0, PRICE_CLOSE);
   
   // 핸들이 유효한지 확인
   if(adx_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || 
      rsi_handle == INVALID_HANDLE || bb_handle == INVALID_HANDLE)
   {
      Print("오류: 지표 핸들을 생성할 수 없습니다!");
      return;
   }
   
// 데이터 버퍼 준비
   double adx_buf[], di_plus_buf[], di_minus_buf[];
   double atr_buf[], atr_prev_buf[];
   double rsi_buf[];
   double bb_upper[], bb_lower[], bb_middle[];
   
   // 배열을 시계열 순서로 설정 (최신 데이터가 0번 인덱스)
   ArraySetAsSeries(adx_buf, true);
   ArraySetAsSeries(di_plus_buf, true);
   ArraySetAsSeries(di_minus_buf, true);
   ArraySetAsSeries(atr_buf, true);
   ArraySetAsSeries(atr_prev_buf, true);
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);
   
   // 데이터 복사
   CopyBuffer(adx_handle, 0, 0, Lookback, adx_buf);
   CopyBuffer(adx_handle, 1, 0, Lookback, di_plus_buf);
   CopyBuffer(adx_handle, 2, 0, Lookback, di_minus_buf);
   CopyBuffer(atr_handle, 0, 0, Lookback, atr_buf);
   CopyBuffer(atr_handle, 0, Lookback, Lookback, atr_prev_buf); // 이전 구간 ATR
   CopyBuffer(rsi_handle, 0, 0, Lookback, rsi_buf);
   CopyBuffer(bb_handle, 0, 0, Lookback, bb_middle);
   CopyBuffer(bb_handle, 1, 0, Lookback, bb_upper);
   CopyBuffer(bb_handle, 2, 0, Lookback, bb_lower);
   
   // 가격 데이터 가져오기
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(Symbol(), Period(), 0, Lookback, rates);
   
   // 레짐 감지 결과를 저장할 배열
   ENUM_MARKET_REGIME regimes[];
   ArrayResize(regimes, Lookback);
   
   // 각 봉마다 레짐 감지
   for(int i = 1; i < Lookback - 1; i++) // 1부터 시작 (이전 봉과 비교 필요)
   {
      // 기본값은 '알 수 없음'
      regimes[i] = REGIME_UNKNOWN;
      
      // === 1. 강한 상승 모멘텀 확인 ===
      if(adx_buf[i] > 25 && di_plus_buf[i] > di_minus_buf[i] && rsi_buf[i] > 60)
      {
         regimes[i] = REGIME_STRONG_BULLISH;
         continue;
      }
      
      // === 2. 강한 하락 모멘텀 확인 ===
      if(adx_buf[i] > 25 && di_minus_buf[i] > di_plus_buf[i] && rsi_buf[i] < 40)
      {
         regimes[i] = REGIME_STRONG_BEARISH;
         continue;
      }
      
      // === 3. 통합 레인지 확인 ===
      double bb_width = (bb_upper[i] - bb_lower[i]) / bb_middle[i]; // 상대적 밴드 폭
      
      if(adx_buf[i] < 20 && rsi_buf[i] > 40 && rsi_buf[i] < 60 && 
         bb_width < 0.03) // 좁은 볼린저 밴드
      {
         regimes[i] = REGIME_CONSOLIDATION;
         continue;
      }
      
      // === 4. 변동성 확장 확인 ===
      double atr_change = ((atr_buf[i] - atr_prev_buf[i]) / atr_prev_buf[i]) * 100;
      
      if(atr_change > 20 && bb_width > 0.05) // ATR 20% 이상 증가, 넓은 밴드
      {
         regimes[i] = REGIME_VOLATILITY_EXPANSION;
         continue;
      }
      
      // === 5. 갭 트레이딩 패턴 확인 ===
      double gap = rates[i].open - rates[i+1].close;
      double avg_body = 0;
      
      // 최근 5개 봉의 평균 몸통 크기 계산
      for(int j = i; j < i + 5 && j < Lookback; j++)
      {
         avg_body += MathAbs(rates[j].close - rates[j].open);
      }
      avg_body /= 5;
      
      if(MathAbs(gap) > avg_body * 1.5) // 평균 몸통의 1.5배 이상 갭
      {
         regimes[i] = REGIME_GAP_PATTERN;
         continue;
      }
      
      // === 6. 기술적 되돌림 확인 ===
      // RSI 다이버전스 등 복잡한 기술적 패턴은 여기서는 단순화
      if((rsi_buf[i+1] < 30 && rsi_buf[i] > rsi_buf[i+1] && rates[i].close > rates[i+1].close) || 
         (rsi_buf[i+1] > 70 && rsi_buf[i] < rsi_buf[i+1] && rates[i].close < rates[i+1].close))
      {
         regimes[i] = REGIME_TECHNICAL_REVERSAL;
         continue;
      }
      
      // === 7. 오버나이트 드리프트 확인 ===
      // 오버나이트 시간대에 낮은 변동성과 점진적 움직임 확인
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      
      // 아시아 세션 시작 시간대 (보통 GMT 0-8시)인지 확인
      bool is_overnight = (dt.hour >= 0 && dt.hour < 8);
      
      // 낮은 ATR (평균보다 30% 이하), 낮은 거래량, 작은 캔들 바디 확인
      double overnight_avg_atr = 0;
      for(int j = 0; j < 20 && j < Lookback; j++)
      {
         overnight_avg_atr += atr_buf[j];
      }
      overnight_avg_atr /= MathMin(20, Lookback);
      
      double candle_body = MathAbs(rates[i].close - rates[i].open);
      double overnight_avg_body = 0;
      for(int j = 0; j < 20 && j < Lookback; j++)
      {
         overnight_avg_body += MathAbs(rates[j].close - rates[j].open);
      }
      overnight_avg_body /= MathMin(20, Lookback);
      
      // 오버나이트 드리프트 조건:
      // 1. 아시아 세션 시간대
      // 2. ATR이 평균보다 낮음 (낮은 변동성)
      // 3. 캔들 바디가 평균보다 작음 (낮은 활동성)
      // 4. ADX가 낮음 (약한 방향성)
      if(is_overnight && atr_buf[i] < overnight_avg_atr * 0.7 && 
         candle_body < overnight_avg_body * 0.7 && adx_buf[i] < 20)
      {
         regimes[i] = REGIME_OVERNIGHT_DRIFT;
         continue;
      }
   }
   
// 필요한 데이터 준비
   datetime time_arr[];
   ArraySetAsSeries(time_arr, true);
   CopyTime(Symbol(), Period(), 0, 20, time_arr);
   
   // 시각화 함수 호출
   
   // 1. 원래 레짐 레이블 표시 (단일 타임프레임 비교용)
   Print("=== 단일 타임프레임 레짐 감지 결과 (비교용) ===");
   CreateRegimeLabels(regimes, time_arr, rates, MathMin(20, Lookback));
   
   // 2. 다중 타임프레임 레짐 정보 표시 (개선된 시각화)
   ShowSimplifiedRegimes(tf_primary, tf_confirm, tf_filter, integrated_regime, integrated_confidence);
   
   // 3. 세션 정보 표시
   ShowSessionInfo();
   
   // 4. 지지/저항 레벨 표시
   DetectAndShowReducedSupportResistanceLevels(200, 2, 6); // 최대 6개 레벨만 표시
   
   // 상세 감지 결과 출력 (최근 20개 봉)
   Print("=== 상세 레짐 감지 결과 (단일 타임프레임) ===");
   
   for(int i = 0; i < 20; i++)
   {
      string time_str = TimeToString(time_arr[i]);
      
      // 레짐이 변경된 경우에만 표시
      if(i == 0 || regimes[i] != regimes[i-1])
      {
         Print(time_str, " - 레짐: ", GetRegimeDescription(regimes[i]));
      }
   }
   
   // 핸들 해제
   IndicatorRelease(adx_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(bb_handle);
   
   Print("=== 다중 타임프레임 레짐 감지 시스템 테스트 완료 ===");
}

//+------------------------------------------------------------------+