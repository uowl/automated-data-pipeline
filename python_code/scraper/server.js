import express from 'express';
import { runScrape } from './scraper.js';

const app = express();
app.use(express.json());
const PORT = process.env.SCRAPER_PORT || 3080;

// Health check (ADF or load balancer)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'pipeline-scraper' });
});

/**
 * POST /scrape
 * Body: { url: string, selectors?: { title?: string, list?: string }, clickSelector?: string }
 * Returns: { success, data, error? }
 * In production, would also write to Blob or SQL (using RunId from body).
 */
app.post('/scrape', async (req, res) => {
  const { url, selectors = {}, clickSelector } = req.body;
  if (!url) {
    return res.status(400).json({ success: false, error: 'url is required' });
  }
  try {
    const data = await runScrape({ url, selectors, clickSelector });
    res.json({ success: true, data });
  } catch (err) {
    console.error('Scrape error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Scraper API listening on http://localhost:${PORT}`);
});
