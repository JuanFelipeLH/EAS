import axios from "axios";

const NEWS_API_URL = "https://newsapi.org/v2/everything";
const NEWS_API_KEY = process.env.NEWS_API_KEY;

/**
 * Normalized news article format.
 * @typedef {{ title: string, description: string, source: string, url: string, timestamp: string }} Article
 */

/**
 * Fetches news articles matching nuclear-related search terms.
 * Returns a normalized array of articles.
 * @returns {Promise<Article[]>}
 */
export async function fetchNuclearNews() {
  if (!NEWS_API_KEY) {
    throw new Error("NEWS_API_KEY environment variable is not set.");
  }

  const query =
    "nuclear explosion OR nuclear attack OR nuclear strike OR atomic bomb OR radiation detected";

  const response = await axios.get(NEWS_API_URL, {
    params: {
      q: query,
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

  return normalizeArticles(response.data.articles);
}

/**
 * Normalizes raw NewsAPI articles into the internal format.
 * Drops articles with missing critical fields.
 * @param {Array<object>} rawArticles
 * @returns {Article[]}
 */
function normalizeArticles(rawArticles) {
  return rawArticles
    .filter((a) => a.title && a.source?.name)
    .map((a) => ({
      title: a.title ?? "",
      description: a.description ?? "",
      source: a.source.name,
      url: a.url ?? "",
      timestamp: a.publishedAt ?? new Date().toISOString(),
    }));
}
