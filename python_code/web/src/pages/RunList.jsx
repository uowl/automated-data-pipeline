import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { API_BASE } from '../App';

function statusColor(s) {
  if (s === 'Success') return '#00ba7c';
  if (s === 'Failed') return '#f4212e';
  if (s === 'Running') return '#1d9bf0';
  return '#71767b';
}

export default function RunList() {
  const navigate = useNavigate();
  const fileInputRef = useRef(null);
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState({ pipeline: '', status: '' });
  const [triggering, setTriggering] = useState(false);
  const [triggerError, setTriggerError] = useState('');

  const handleTrigger = async (e) => {
    e.preventDefault();
    const file = fileInputRef.current?.files?.[0];
    if (!file) {
      setTriggerError('Please select a CSV or JSON file.');
      return;
    }
    setTriggerError('');
    setTriggering(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const res = await fetch(`${API_BASE}/pipeline/trigger`, {
        method: 'POST',
        body: formData
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || 'Trigger failed');
      navigate(`/runs/${data.runId}`);
    } catch (err) {
      setTriggerError(err.message || 'Failed to trigger pipeline');
    } finally {
      setTriggering(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  useEffect(() => {
    let url = `${API_BASE}/runs?`;
    if (filter.pipeline) url += `pipeline=${encodeURIComponent(filter.pipeline)}&`;
    if (filter.status) url += `status=${encodeURIComponent(filter.status)}&`;
    fetch(url)
      .then((r) => r.json())
      .then((data) => {
        setRuns(Array.isArray(data) ? data : []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, [filter.pipeline, filter.status]);

  return (
    <>
      <div style={{ marginBottom: '1.5rem', padding: '1rem', background: '#16181c', borderRadius: 8, border: '1px solid #2f3336' }}>
        <h3 style={{ margin: '0 0 0.5rem', fontSize: '1rem' }}>Trigger pipeline with CSV or JSON</h3>
        <form onSubmit={handleTrigger} style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <input
            ref={fileInputRef}
            type="file"
            accept=".csv,.json"
            style={{ color: '#e7e9ea' }}
          />
          <button type="submit" disabled={triggering} style={{ padding: '0.5rem 1rem', background: '#1d9bf0', border: 'none', borderRadius: 4, color: '#fff', cursor: triggering ? 'not-allowed' : 'pointer' }}>
            {triggering ? 'Running…' : 'Run pipeline'}
          </button>
        </form>
        {triggerError && <p style={{ margin: '0.5rem 0 0', color: '#f4212e', fontSize: '0.875rem' }}>{triggerError}</p>}
        <p style={{ margin: '0.5rem 0 0', color: '#71767b', fontSize: '0.8rem' }}>
          File must have columns: OrderId, CustomerId, Amount, OrderDate (see sample in <code style={{ background: '#2f3336', padding: '0 0.25rem' }}>data/landing/</code>).
        </p>
      </div>
      <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem', alignItems: 'center' }}>
        <input
          placeholder="Filter by pipeline name"
          value={filter.pipeline}
          onChange={(e) => setFilter((f) => ({ ...f, pipeline: e.target.value }))}
          style={{ padding: '0.5rem', background: '#2f3336', border: '1px solid #2f3336', borderRadius: 4, color: '#e7e9ea' }}
        />
        <select
          value={filter.status}
          onChange={(e) => setFilter((f) => ({ ...f, status: e.target.value }))}
          style={{ padding: '0.5rem', background: '#2f3336', border: '1px solid #2f3336', borderRadius: 4, color: '#e7e9ea' }}
        >
          <option value="">All statuses</option>
          <option value="Running">Running</option>
          <option value="Success">Success</option>
          <option value="Failed">Failed</option>
        </select>
      </div>
      {loading ? (
        <p>Loading runs…</p>
      ) : runs.length === 0 ? (
        <p style={{ color: '#71767b' }}>No runs found. Run the orchestrator to create a pipeline run.</p>
      ) : (
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid #2f3336', textAlign: 'left' }}>
              <th style={{ padding: '0.75rem' }}>#</th>
              <th style={{ padding: '0.75rem' }}>Pipeline</th>
              <th style={{ padding: '0.75rem' }}>Run ID</th>
              <th style={{ padding: '0.75rem' }}>Status</th>
              <th style={{ padding: '0.75rem' }}>Started</th>
              <th style={{ padding: '0.75rem' }}>Finished</th>
              <th style={{ padding: '0.75rem' }}></th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.RunId} style={{ borderBottom: '1px solid #2f3336' }}>
                <td style={{ padding: '0.75rem', fontWeight: 600, color: '#71767b' }}>#{r.RunNumber ?? '—'}</td>
                <td style={{ padding: '0.75rem' }}>{r.PipelineName}</td>
                <td style={{ padding: '0.75rem', fontFamily: 'monospace', fontSize: '0.8rem' }}>{r.RunId}</td>
                <td style={{ padding: '0.75rem' }}>
                  <span style={{ color: statusColor(r.Status), fontWeight: 600 }}>{r.Status}</span>
                </td>
                <td style={{ padding: '0.75rem', color: '#71767b', fontSize: '0.875rem' }}>
                  {r.StartedAt ? new Date(r.StartedAt).toLocaleString() : '—'}
                </td>
                <td style={{ padding: '0.75rem', color: '#71767b', fontSize: '0.875rem' }}>
                  {r.FinishedAt ? new Date(r.FinishedAt).toLocaleString() : '—'}
                </td>
                <td style={{ padding: '0.75rem' }}>
                  <Link to={`/runs/${r.RunId}`}>View steps</Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}
