//+------------------------------------------------------------------+
//|                                                  Logger.mqh      |
//|                                      NAS100 MTF Regime System    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// 로그 레벨 상수 정의
enum ENUM_LOG_LEVEL {
   LOG_LEVEL_NONE = 0,       // 로깅 없음
   LOG_LEVEL_ERROR = 1,      // 오류만 로깅
   LOG_LEVEL_WARNING = 2,    // 경고 및 오류 로깅
   LOG_LEVEL_INFO = 3,       // 정보, 경고 및 오류 로깅
   LOG_LEVEL_DEBUG = 4,      // 디버그, 정보, 경고 및 오류 로깅
   LOG_LEVEL_TRACE = 5       // 모든 항목 로깅 (가장 상세)
};

// 로그 모드 상수 정의
enum ENUM_LOG_MODE {
   LOG_MODE_CONSOLE = 1,     // 콘솔에만 출력
   LOG_MODE_FILE = 2,        // 파일에만 출력
   LOG_MODE_BOTH = 3         // 콘솔과 파일 모두 출력
};

//+------------------------------------------------------------------+
//| 로거 클래스                                                      |
//+------------------------------------------------------------------+
class CLogger {
private:
   static CLogger*    m_instance;         // 싱글톤 인스턴스
   ENUM_LOG_LEVEL     m_current_level;    // 현재 로그 레벨
   ENUM_LOG_MODE      m_log_mode;         // 로그 출력 모드
   int                m_file_handle;      // 로그 파일 핸들
   string             m_log_filename;     // 로그 파일 이름
   bool               m_include_timestamp; // 타임스탬프 포함 여부
   bool               m_include_log_level; // 로그 레벨 포함 여부
   bool               m_initialized;       // 초기화 여부

   // 싱글톤 패턴을 위한 기본 생성자 (private)
   CLogger() {
      m_current_level = LOG_LEVEL_INFO;    // 기본 로그 레벨
      m_log_mode = LOG_MODE_CONSOLE;      // 기본 로그 모드
      m_file_handle = INVALID_HANDLE;
      m_log_filename = "NAS100_MTF_System.log";
      m_include_timestamp = true;
      m_include_log_level = true;
      m_initialized = false;
   }

   // 로그 파일 열기 (내부 메서드)
   bool OpenLogFile() {
      if(m_file_handle != INVALID_HANDLE) return true;
      
      int flags = FILE_WRITE | FILE_TXT;
      // 파일이 이미 존재하는 경우 추가 모드로 열기
      if(FileIsExist(m_log_filename)) flags |= FILE_READ;
      
      m_file_handle = FileOpen(m_log_filename, flags);
      
      if(m_file_handle == INVALID_HANDLE) {
         Print("로그 파일을 열 수 없음: ", m_log_filename, ", 오류: ", GetLastError());
         return false;
      }
      
      // 파일이 이미 존재하는 경우 파일 끝으로 이동
      if(FileIsExist(m_log_filename)) {
         FileSeek(m_file_handle, 0, SEEK_END);
      } else {
         // 새 파일에 헤더 추가
         string header = "=== NAS100 다중 타임프레임 레짐 감지 시스템 로그 ===\n";
         header += "시작 시간: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n\n";
         FileWriteString(m_file_handle, header);
      }
      
      return true;
   }
   
   // 타임스탬프 생성
   string GetTimestamp() {
      if(!m_include_timestamp) return "";
      return "[" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "] ";
   }
   
   // 로그 레벨 텍스트 반환
   string GetLevelText(ENUM_LOG_LEVEL level) {
      if(!m_include_log_level) return "";
      
      switch(level) {
         case LOG_LEVEL_ERROR:   return "[오류] ";
         case LOG_LEVEL_WARNING: return "[경고] ";
         case LOG_LEVEL_INFO:    return "[정보] ";
         case LOG_LEVEL_DEBUG:   return "[디버그] ";
         case LOG_LEVEL_TRACE:   return "[추적] ";
         default:                return "";
      }
   }
   
   // 로그 메시지 출력 (내부 메서드)
   void WriteLog(ENUM_LOG_LEVEL level, string message) {
      // 현재 설정된 레벨보다 높은 레벨은 출력하지 않음
      if(level > m_current_level) return;
      
      // 타임스탬프와 레벨 텍스트 추가
      string formatted_msg = GetTimestamp() + GetLevelText(level) + message;
      
      // 설정된 모드에 따라 출력
      if(m_log_mode == LOG_MODE_CONSOLE || m_log_mode == LOG_MODE_BOTH) {
         Print(formatted_msg);
      }
      
      if((m_log_mode == LOG_MODE_FILE || m_log_mode == LOG_MODE_BOTH) && m_file_handle != INVALID_HANDLE) {
         FileWriteString(m_file_handle, formatted_msg + "\n");
         FileFlush(m_file_handle); // 즉시 파일에 기록
      }
   }

public:
   // 소멸자
   ~CLogger() {
      if(m_file_handle != INVALID_HANDLE) {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
   }
   
   // 싱글톤 인스턴스 가져오기
   static CLogger* GetInstance() {
      if(m_instance == NULL) {
         m_instance = new CLogger();
      }
      return m_instance;
   }
   
   // 로거 초기화
   bool Initialize(ENUM_LOG_LEVEL level = LOG_LEVEL_INFO, ENUM_LOG_MODE mode = LOG_MODE_CONSOLE, string filename = "") {
      m_current_level = level;
      m_log_mode = mode;
      
      if(filename != "") m_log_filename = filename;
      
      // 파일 로깅이 필요한 경우 파일 열기
      if(mode == LOG_MODE_FILE || mode == LOG_MODE_BOTH) {
         if(!OpenLogFile()) return false;
      }
      
      m_initialized = true;
      return true;
   }
   
   // 설정 변경 메서드
   void SetLogLevel(ENUM_LOG_LEVEL level) { m_current_level = level; }
   void SetLogMode(ENUM_LOG_MODE mode) { 
      m_log_mode = mode; 
      // 파일 모드가 추가된 경우 파일 열기
      if((mode == LOG_MODE_FILE || mode == LOG_MODE_BOTH) && m_file_handle == INVALID_HANDLE) {
         OpenLogFile();
      }
   }
   void SetLogFilename(string filename) { 
      // 파일이 이미 열려있으면 닫기
      if(m_file_handle != INVALID_HANDLE) {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
      m_log_filename = filename;
      // 파일 모드인 경우 새 이름으로 파일 열기
      if(m_log_mode == LOG_MODE_FILE || m_log_mode == LOG_MODE_BOTH) {
         OpenLogFile();
      }
   }
   void SetIncludeTimestamp(bool include) { m_include_timestamp = include; }
   void SetIncludeLogLevel(bool include) { m_include_log_level = include; }
   
   // 현재 설정 가져오기
   ENUM_LOG_LEVEL GetLogLevel() const { return m_current_level; }
   ENUM_LOG_MODE GetLogMode() const { return m_log_mode; }
   string GetLogFilename() const { return m_log_filename; }
   bool IsInitialized() const { return m_initialized; }
   
   // 로그 레벨별 출력 메서드
   void Error(string message) { WriteLog(LOG_LEVEL_ERROR, message); }
   void Warning(string message) { WriteLog(LOG_LEVEL_WARNING, message); }
   void Info(string message) { WriteLog(LOG_LEVEL_INFO, message); }
   void Debug(string message) { WriteLog(LOG_LEVEL_DEBUG, message); }
   void Trace(string message) { WriteLog(LOG_LEVEL_TRACE, message); }
   
   // 일반 로그 출력 (레벨 지정)
   void Log(ENUM_LOG_LEVEL level, string message) { WriteLog(level, message); }
   
   // 로거 종료 (파일 닫기)
   void Shutdown() {
      if(m_file_handle != INVALID_HANDLE) {
         string footer = "\n=== 로깅 종료: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " ===\n";
         FileWriteString(m_file_handle, footer);
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }
};

// 정적 인스턴스 초기화
CLogger* CLogger::m_instance = NULL;

//+------------------------------------------------------------------+
//| 간편한 전역 로깅 함수                                            |
//+------------------------------------------------------------------+
// 로거 초기화
bool LoggerInit(ENUM_LOG_LEVEL level = LOG_LEVEL_INFO, ENUM_LOG_MODE mode = LOG_MODE_CONSOLE, string filename = "") {
   return CLogger::GetInstance().Initialize(level, mode, filename);
}

// 로그 레벨 설정
void LoggerSetLevel(ENUM_LOG_LEVEL level) {
   CLogger::GetInstance().SetLogLevel(level);
}

// 로그 메시지 출력 (레벨 지정)
void LoggerWrite(ENUM_LOG_LEVEL level, string message) {
   CLogger::GetInstance().Log(level, message);
}

// 레벨별 로그 함수
void LogError(string message) { CLogger::GetInstance().Error(message); }
void LogWarning(string message) { CLogger::GetInstance().Warning(message); }
void LogInfo(string message) { CLogger::GetInstance().Info(message); }
void LogDebug(string message) { CLogger::GetInstance().Debug(message); }
void LogTrace(string message) { CLogger::GetInstance().Trace(message); }

// 로거 종료
void LoggerShutdown() {
   CLogger::GetInstance().Shutdown();
}