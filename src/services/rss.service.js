import Parser from "rss-parser";

const parser = new Parser({ timeout: 10000 });

/**
 * RSS feeds from tier-1 sources — no API key required, unlimited.
 * Each entry maps the feed's source name exactly to what source.validator.js expects.
 */
const RSS_FEEDS = [
  { name: "Reuters", url: "https://feeds.reuters.com/reuters/worldNews" },
  { name: "Reuters", url: "https://feeds.reuters.com/Reuters/worldNews?format=xml" },
  { name: "BBC News", url: "https://feeds.bbci.co.uk/news/world/rss.xml" },
  { name: "Al Jazeera English", url: "https://www.aljazeera.com/xml/rss/all.xml" },
  { name: "Associated Press", url: "https://rsshub.app/ap/topics/apf-intlnews" },
];

/**
 * Fetches and normalizes articles from all configured RSS feeds.
 * Failures on individual feeds are caught and skipped so one dead feed
 * doesn't abort the entire run.
 * @returns {Promise<Array<{ title: string, description: string, source: string, url: string, timestamp: string }>>}
 */
export async function fetchRSSNews() {
  const results = await Promise.allSettled(
    RSS_FEEDS.map((feed) => fetchFeed(feed))
  );

  const articles = [];
  for (const result of results) {
    if (result.status === "fulfilled") {
      articles.push(...result.value);
    } else {
      console.warn("[RSS] Feed failed:", result.reason?.message ?? result.reason);
    }
  }

  return articles;
}

/**
 * @param {{ name: string, url: string }} feed
 * @returns {Promise<Array>}
 */
async function fetchFeed({ name, url }) {
  const feed = await parser.parseURL(url);
  return (feed.items ?? [])
    .filter((item) => item.title)
    .map((item) => ({
      title: item.title ?? "",
      description: item.contentSnippet ?? item.summary ?? item.content ?? "",
      source: name,
      url: item.link ?? "",
      timestamp: item.isoDate ?? item.pubDate ?? new Date().toISOString(),
    }));
}
