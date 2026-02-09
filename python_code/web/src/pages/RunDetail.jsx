import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { API_BASE } from '../App';

function LogLine({ log: l }) {
  const levelColor = l.Level === 'Error' ? '#f4212e' : l.Level === 'Warning' ? '#ffad1f' : '#71767b';
  return (
    <div style={{ display: 'flex', gap: '0.5rem', padding: '0.35rem 0', borderBottom: '1px solid #2f3336', fontSize: '0.8rem', fontFamily: 'monospace' }}>
      <span style={{ color: '#71767b', flexShrink: 0 }}>{new Date(l.LogAt).toLocaleTimeString()}</span>
      <span style={{ color: levelColor, fontWeight: l.Level === 'Error' ? 600 : 400, minWidth: 48 }}>{l.Level}</span>
      {l.StepNumber != null && <span style={{ color: '#1d9bf0' }}>Step{l.StepNumber}</span>}
      <span style={{ color: '#e7e9ea' }}>{l.Message}</span>
      {l.Details && <span style={{ color: '#71767b' }} title={l.Details}>{l.Details.length > 60 ? l.Details.slice(0, 60) + '…' : l.Details}</span>}
    </div>
  );
}

function statusColor(s) {
  if (s === 'Success') return '#00ba7c';
  if (s === 'Failed') return '#f4212e';
  if (s === 'Running') return '#1d9bf0';
  return '#71767b';
}

function StepBlock({ step, isRunning }) {
  const duration =
    step.StartedAt && step.FinishedAt
      ? ((new Date(step.FinishedAt) - new Date(step.StartedAt)) / 1000).toFixed(1) + 's'
      : null;
  return (
    <div
      style={{
        flex: 1,
        minWidth: 140,
        padding: '1rem',
        borderRadius: 8,
        background: isRunning ? 'rgba(29,155,240,0.15)' : '#16181c',
        border: `2px solid ${step.Status === 'Failed' ? '#f4212e' : isRunning ? '#1d9bf0' : '#2f3336'}`,
        textAlign: 'center'
      }}
    >
      <div style={{ fontWeight: 600, marginBottom: '0.25rem' }}>
        {step.StepNumber} — {step.StepName}
      </div>
      <div style={{ color: statusColor(step.Status), fontSize: '0.875rem', marginBottom: '0.25rem' }}>
        {step.Status}
      </div>
      {step.RowsAffected != null && (
        <div style={{ color: '#71767b', fontSize: '0.8rem' }}>{step.RowsAffected} rows</div>
      )}
      {duration && <div style={{ color: '#71767b', fontSize: '0.8rem' }}>{duration}</div>}
      {step.ErrorMessage && (
        <div style={{ marginTop: '0.5rem', fontSize: '0.75rem', color: '#f4212e', wordBreak: 'break-word' }}>
          {step.ErrorMessage}
        </div>
      )}
    </div>
  );
}

export default function RunDetail() {
  const { runId } = useParams();
  const [run, setRun] = useState(null);
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const isRunning = run?.Status === 'Running';
  const refreshInterval = isRunning ? 2000 : 0; // poll every 2s when running so step status updates in real time

  useEffect(() => {
    function load() {
      fetch(`${API_BASE}/runs/${runId}`)
        .then((r) => (r.ok ? r.json() : null))
        .then(setRun)
        .finally(() => setLoading(false));
    }
    load();
    if (refreshInterval) {
      const id = setInterval(load, refreshInterval);
      return () => clearInterval(id);
    }
  }, [runId, refreshInterval]);

  // Load logs; when run is in progress, refresh logs every 2s so user sees live output
  useEffect(() => {
    function loadLogs() {
      fetch(`${API_BASE}/runs/${runId}/logs`)
        .then((r) => (r.ok ? r.json() : []))
        .then((data) => setLogs(Array.isArray(data) ? data : []))
        .catch(() => setLogs([]));
    }
    loadLogs();
    if (isRunning) {
      const id = setInterval(loadLogs, 2000);
      return () => clearInterval(id);
    }
  }, [runId, isRunning]);

  if (loading) return <p>Loading run…</p>;
  if (!run) return <p>Run not found. <Link to="/">Back to list</Link></p>;

  const steps = run.steps || [];
  const stepsOrdered = [1, 2, 3, 4].map((n) => steps.find((s) => s.StepNumber === n)).filter(Boolean);

  return (
    <>
      <p><Link to="/">← Back to runs</Link></p>
      <div style={{ marginBottom: '1.5rem' }}>
        <h2 style={{ margin: '0 0 0.25rem' }}>{run.PipelineName}</h2>
        <p style={{ margin: 0, color: '#71767b', fontSize: '0.8rem' }}>
          {run.RunNumber != null && <span style={{ fontWeight: 600, marginRight: '0.5rem' }}>#{run.RunNumber}</span>}
          <span style={{ fontFamily: 'monospace' }}>{run.RunId}</span>
        </p>
        <p style={{ margin: '0.5rem 0 0' }}>
          Status: <span style={{ color: statusColor(run.Status), fontWeight: 600 }}>{run.Status}</span>
          {' · '}
          Started: {run.StartedAt ? new Date(run.StartedAt).toLocaleString() : '—'}
          {run.FinishedAt && ` · Finished: ${new Date(run.FinishedAt).toLocaleString()}`}
        </p>
      </div>

      <h3 style={{ marginBottom: '0.75rem', fontSize: '1rem' }}>Four steps</h3>
      <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap', alignItems: 'stretch' }}>
        {stepsOrdered.length ? (
          stepsOrdered.map((step) => (
            <StepBlock key={step.StepRunId} step={step} isRunning={step.Status === 'Running'} />
          ))
        ) : (
          [1, 2, 3, 4].map((n) => (
            <StepBlock
              key={n}
              step={{ StepNumber: n, StepName: n === 1 ? 'Data Pull' : n === 2 ? 'Extract (SP)' : n === 3 ? 'Transform (SP)' : 'Migrate (SP)', Status: 'Pending' }}
              isRunning={false}
            />
          ))
        )}
      </div>
      {isRunning && (
        <p style={{ marginTop: '1rem', color: '#71767b', fontSize: '0.875rem' }}>
          Running in background — status and logs refresh automatically (every 2s).
        </p>
      )}

      <h3 style={{ marginTop: '1.5rem', marginBottom: '0.5rem', fontSize: '1rem' }}>Logs</h3>
      <div style={{ background: '#16181c', border: '1px solid #2f3336', borderRadius: 8, padding: '0.5rem', maxHeight: 320, overflowY: 'auto' }}>
        {logs.length === 0 ? (
          <p style={{ color: '#71767b', margin: 0, fontSize: '0.875rem' }}>No logs for this run yet.</p>
        ) : (
          logs.map((l) => <LogLine key={l.LogId} log={l} />)
        )}
      </div>
    </>
  );
}
