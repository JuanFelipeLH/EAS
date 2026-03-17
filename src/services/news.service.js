import axios from "axios";
import { fetchRSSNews } from "./rss.service.js";

const NEWS_API_URL = "https://newsapi.org/v2/everything";
const NEWS_API_KEY = process.env.NEWS_API_KEY;

const NEWSDATA_API_URL = "https://newsdata.io/api/1/news";
const NEWSDATA_API_KEY = process.env.NEWSDATA_API_KEY; // optional — free 200 req/day at newsdata.io

/**
 * Normalized news article format.
 * @typedef {{ title: string, description: string, source: string, url: string, timestamp: string }} Article
 */

const NUCLEAR_QUERY =
  "nuclear explosion OR nuclear attack OR nuclear strike OR atomic bomb OR radiation detected OR nuclear weapon OR ballistic missile OR nuclear test";

/**
 * Aggregates articles from all configured sources:
 *   1. NewsAPI  (keyed, every run)
 *   2. RSS feeds (Reuters, BBC, AP, Al Jazeera — free, every run)
 *   3. NewsData.io (keyed, only if useNewsData=true — caller controls 10-min throttle)
 *
 * Deduplicates by URL before returning.
 * @param {{ useNewsData?: boolean }} opts
 * @returns {Promise<Article[]>}
 */
export async function fetchNuclearNews({ useNewsData = false } = {}) {
  const tasks = [fetchFromNewsAPI(), fetchFromRSS()];
  if (NEWSDATA_API_KEY && useNewsData) tasks.push(fetchFromNewsData());

  const results = await Promise.allSettled(tasks);

  const all = [];
  const labels = ["NewsAPI", "RSS", "NewsData"];
  for (let i = 0; i < results.length; i++) {
    if (results[i].status === "fulfilled") {
      const articles = results[i].value;
      console.log(`[News] ${labels[i]}: ${articles.length} articles`);
      all.push(...articles);
    } else {
      console.warn(`[News] ${labels[i]} failed:`, results[i].reason?.message ?? results[i].reason);
    }
  }

  // Deduplicate by URL
  const seen = new Set();
  return all.filter((a) => {
    if (!a.url || seen.has(a.url)) return false;
    seen.add(a.url);
    return true;
  });
}

// ── Source fetchers ────────────────────────────────────────────────────────────

async function fetchFromNewsAPI() {
  if (!NEWS_API_KEY) {
    console.warn("[News] NEWS_API_KEY not set — skipping NewsAPI.");
    return [];
  }

  const response = await axios.get(NEWS_API_URL, {
    params: {
      q: NUCLEAR_QUERY,
      language: "en",
      sortBy: "publishedAt",
      pageSize: 20,
      apiKey: NEWS_API_KEY,
    },
    timeout: 10000,
  });

  if (response.data.status !== "ok") {
    throw new Error(`NewsAPI error: ${response.data.message}`);
  }

  return response.data.articles
    .filter((a) => a.title && a.source?.name)
    .map((a) => ({
      title: a.title ?? "",
      description: a.description ?? "",
      source: a.source.name,
      url: a.url ?? "",
      timestamp: a.publishedAt ?? new Date().toISOString(),
    }));
}

async function fetchFromRSS() {
  return fetchRSSNews();
}

async function fetchFromNewsData() {
  const response = await axios.get(NEWSDATA_API_URL, {
    params: {
      apikey: NEWSDATA_API_KEY,
      q: "nuclear attack OR nuclear explosion OR nuclear strike OR atomic bomb",
      language: "en",
    },
    timeout: 10000,
  });

  if (response.data.status !== "success") {
    throw new Error(`NewsData error: ${response.data.message}`);
  }

  return (response.data.results ?? [])
    .filter((a) => a.title && a.source_id)
    .map((a) => ({
      title: a.title ?? "",
      description: a.description ?? a.content ?? "",
      source: a.source_id ?? "",
      url: a.link ?? "",
      timestamp: a.pubDate ?? new Date().toISOString(),
    }));
}
