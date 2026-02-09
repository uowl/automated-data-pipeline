import { BrowserRouter, Routes, Route, Link } from 'react-router-dom';
import RunList from './pages/RunList';
import RunDetail from './pages/RunDetail';
import Logs from './pages/Logs';

const API_BASE = import.meta.env.VITE_API_URL || '/api';

export { API_BASE };

export default function App() {
  return (
    <BrowserRouter>
      <div style={{ padding: '1rem 2rem', maxWidth: 1200, margin: '0 auto' }}>
        <header style={{ marginBottom: '1.5rem', borderBottom: '1px solid #2f3336', paddingBottom: '0.75rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
            <h1 style={{ margin: 0, fontSize: '1.25rem' }}>Pipeline Monitor</h1>
            <Link to="/" style={{ fontSize: '0.875rem' }}>Runs</Link>
            <Link to="/logs" style={{ fontSize: '0.875rem' }}>All logs</Link>
          </div>
          <p style={{ margin: '0.25rem 0 0', color: '#71767b', fontSize: '0.875rem' }}>
            Automated Data Pipeline — 4 steps: Data Pull → Extract → Transform → Migrate
          </p>
        </header>
        <Routes>
          <Route path="/" element={<RunList />} />
          <Route path="/runs/:runId" element={<RunDetail />} />
          <Route path="/logs" element={<Logs />} />
        </Routes>
      </div>
    </BrowserRouter>
  );
}
