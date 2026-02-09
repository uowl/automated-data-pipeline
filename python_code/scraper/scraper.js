import { chromium } from 'playwright';

/**
 * Run headless Chrome: navigate to url, optionally click, then extract text by selectors.
 * Returns object with keys = selector names, values = extracted text or arrays.
 */
export async function runScrape(options) {
  const { url, selectors = {}, clickSelector } = options;
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    if (clickSelector) {
      await page.click(clickSelector, { timeout: 5000 }).catch(() => {});
    }
    const result = {};
    for (const [name, selector] of Object.entries(selectors)) {
      if (!selector) continue;
      const count = await page.locator(selector).count();
      if (count === 0) {
        result[name] = null;
      } else if (count === 1) {
        result[name] = await page.locator(selector).first().innerText().catch(() => null);
      } else {
        result[name] = await page.locator(selector).allInnerTexts();
      }
    }
    // If no selectors, return title and url as default
    if (Object.keys(result).length === 0) {
      result.title = await page.title();
      result.url = page.url();
    }
    return result;
  } finally {
    await browser.close();
  }
}
