//+------------------------------------------------------------------+
//|                                       ServiceContainer.mqh       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"
#property strict

// 필요한 클래스들 include
#include "../Utils/SessionManager.mqh"
#include "../TimeFrames/MultiTimeframeManager.mqh"
#include "../RegimeDetection/RegimeDetector.mqh"
#include "../Trading/RiskManager.mqh"
#include "../Trading/StrategySelector.mqh"
#include "../Trading/ExecutionManager.mqh"

class CServiceContainer
{
private:
   static CServiceContainer* m_instance;
   
   CSessionManager*       m_session_manager;
   CMultiTimeframeManager* m_mtf_manager;
   CRegimeDetector*       m_regime_detector;
   CRiskManager*          m_risk_manager;
   CStrategySelector*     m_strategy_selector;
   CExecutionManager*     m_execution_manager;
   
   bool m_initialized;

public:
   CServiceContainer()
   {
      m_session_manager = NULL;
      m_mtf_manager = NULL;
      m_regime_detector = NULL;
      m_risk_manager = NULL;
      m_strategy_selector = NULL;
      m_execution_manager = NULL;
      m_initialized = false;
   }
   
   ~CServiceContainer()
   {
      if(m_execution_manager) { delete m_execution_manager; m_execution_manager = NULL; }
      if(m_strategy_selector) { delete m_strategy_selector; m_strategy_selector = NULL; }
      if(m_risk_manager) { delete m_risk_manager; m_risk_manager = NULL; }
      if(m_regime_detector) { delete m_regime_detector; m_regime_detector = NULL; }
      if(m_mtf_manager) { delete m_mtf_manager; m_mtf_manager = NULL; }
      if(m_session_manager) { delete m_session_manager; m_session_manager = NULL; }
   }
   
   static CServiceContainer* GetInstance()
   {
      if(m_instance == NULL)
         m_instance = new CServiceContainer();
      return m_instance;
   }
   
   // 🔥 여기 안에 넣어야 함!
   bool RegisterServices(string symbol, ulong magic_number)
   {
      if(m_initialized) return true;
      
      m_session_manager = new CSessionManager();
      if(m_session_manager == NULL) return false;
      
      m_risk_manager = new CRiskManager(symbol);
      if(m_risk_manager == NULL || !m_risk_manager.Initialize()) return false;
      
      m_mtf_manager = new CMultiTimeframeManager(symbol, m_session_manager);
      if(m_mtf_manager == NULL || !m_mtf_manager.Initialize()) return false;
      
      m_regime_detector = new CRegimeDetector(symbol, m_mtf_manager, m_session_manager);
      if(m_regime_detector == NULL || !m_regime_detector.Initialize()) return false;
      
      m_initialized = true;
      return true;
   }
   
   CSessionManager* GetSessionManager() { return m_session_manager; }
   CRiskManager* GetRiskManager() { return m_risk_manager; } 
   CRegimeDetector* GetRegimeDetector() { return m_regime_detector; }
};

// 정적 변수 초기화
CServiceContainer* CServiceContainer::m_instance = NULL;