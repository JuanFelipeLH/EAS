export const TRUSTED_SOURCES = [
  // Tier 1 — wire services
  "Reuters",
  "Associated Press",
  // Tier 1 — international broadcasters
  "BBC News",
  "CNN",
  "Al Jazeera English",
  // Tier 2 — major newspapers
  "The New York Times",
  "The Guardian",
  "The Washington Post",
  "The Times of India",
  // Tier 2 — major TV/web outlets
  "ABC News",
  "NBC News",
  "CBS News",
  "Fox News",
  "Sky News",
  // Tier 2 — regional majors
  "CNA",
  "Euronews",
  "South China Morning Post",
  "Hurriyet Daily News",
  // Tier 2 — security/defence
  "Defense News",
  "Help Net Security",
  "Globalsecurity.org"
];

/**
 * Checks whether a news article comes from a trusted source.
 * @param {{ source: string }} news
 * @returns {boolean}
 */
export function isTrustedSource(news) {
  return TRUSTED_SOURCES.some(
    (trusted) => news.source.toLowerCase() === trusted.toLowerCase()
  );
}
