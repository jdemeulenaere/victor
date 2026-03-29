import React, { useState } from 'react';

const App: React.FC = () => {
  const [eventLog, setEventLog] = useState<string[]>([]);
  const [inputVal, setInputVal] = useState<string>("");

  const handleWakeEvent = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputVal.trim()) return;
    setEventLog((prev: string[]) => [`=> System Override: "${inputVal}"`, ...prev]);
    setInputVal("");
    // TODO: Emit protobuf Event over gRPC to backend here
  };


  return (
    <div className="dashboard-container">
      <header className="header">
        <div className="status-indicator active" />
        <h1 className="title">V.I.C.T.O.R</h1>
        <span className="subtitle">Core Process: Online</span>
      </header>
      
      <main className="main-content">
        <section className="terminal">
          <div className="terminal-header">Active Event Stream</div>
          <div className="terminal-body">
            {eventLog.length === 0 ? (
              <div className="log-entry system">Standing by. Waiting for wake events...</div>
            ) : (
              eventLog.map((log, i) => (
                <div key={i} className="log-entry user">{log}</div>
              ))
            )}
          </div>
        </section>

        <section className="controls">
          <form onSubmit={handleWakeEvent} className="input-form">
            <input 
              type="text" 
              className="event-input" 
              placeholder="Inject Manual Wake Event... (e.g. 'Read latest emails')" 
              value={inputVal}
              onChange={(e) => setInputVal(e.target.value)}
            />
            <button type="submit" className="glass-btn pulse">SEND EVENT</button>
          </form>
        </section>
      </main>
    </div>
  );
}

export default App;
