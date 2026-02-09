import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { API_BASE } from '../App';

function levelColor(level) {
  if (level === 'Error') return '#f4212e';
  if (level === 'Warning') return '#ffad1f';
  return '#71767b';
}

export default function Logs() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState({ level: '', limit: '200' });

  useEffect(() => {
    let url = `${API_BASE}/logs?limit=${filter.limit}`;
    if (filter.level) url += `&level=${encodeURIComponent(filter.level)}`;
    fetch(url)
      .then((r) => r.json())
      .then((data) => setLogs(Array.isArray(data) ? data.reverse() : []))
      .catch(() => setLogs([]))
      .finally(() => setLoading(false));
  }, [filter.level, filter.limit]);

  return (
    <>
      <p><Link to="/">← Back to runs</Link></p>
      <h2 style={{ margin: '0 0 1rem' }}>All pipeline logs</h2>
      <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem', alignItems: 'center', flexWrap: 'wrap' }}>
        <select
          value={filter.level}
          onChange={(e) => setFilter((f) => ({ ...f, level: e.target.value }))}
          style={{ padding: '0.5rem', background: '#2f3336', border: '1px solid #2f3336', borderRadius: 4, color: '#e7e9ea' }}
        >
          <option value="">All levels</option>
          <option value="Info">Info</option>
          <option value="Warning">Warning</option>
          <option value="Error">Error</option>
        </select>
        <select
          value={filter.limit}
          onChange={(e) => setFilter((f) => ({ ...f, limit: e.target.value }))}
          style={{ padding: '0.5rem', background: '#2f3336', border: '1px solid #2f3336', borderRadius: 4, color: '#e7e9ea' }}
        >
          <option value="100">Last 100</option>
          <option value="200">Last 200</option>
          <option value="500">Last 500</option>
        </select>
      </div>
      <div style={{ background: '#16181c', border: '1px solid #2f3336', borderRadius: 8, padding: '0.5rem', maxHeight: '70vh', overflowY: 'auto' }}>
        {loading ? (
          <p style={{ color: '#71767b' }}>Loading logs…</p>
        ) : logs.length === 0 ? (
          <p style={{ color: '#71767b' }}>No logs found. Run a pipeline to see logs.</p>
        ) : (
          logs.map((l) => (
            <div
              key={l.LogId}
              style={{
                display: 'flex',
                gap: '0.5rem',
                padding: '0.35rem 0',
                borderBottom: '1px solid #2f3336',
                fontSize: '0.8rem',
                fontFamily: 'monospace',
                flexWrap: 'wrap'
              }}
            >
              <span style={{ color: '#71767b', flexShrink: 0 }}>{new Date(l.LogAt).toLocaleString()}</span>
              <span style={{ color: levelColor(l.Level), fontWeight: l.Level === 'Error' ? 600 : 400, minWidth: 48 }}>{l.Level}</span>
              <Link to={`/runs/${l.RunId}`} style={{ color: '#1d9bf0', flexShrink: 0 }} title={l.RunId}>
                {l.PipelineName || l.RunId?.slice(0, 8)}…
              </Link>
              {l.StepNumber != null && <span style={{ color: '#1d9bf0' }}>Step{l.StepNumber}</span>}
              <span style={{ color: '#e7e9ea' }}>{l.Message}</span>
              {l.Details && <span style={{ color: '#71767b' }} title={l.Details}>{l.Details.length > 80 ? l.Details.slice(0, 80) + '…' : l.Details}</span>}
            </div>
          ))
        )}
      </div>
    </>
  );
}
