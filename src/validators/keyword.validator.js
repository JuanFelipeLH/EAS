export const KEYWORDS = [
  // High-confidence attack events
  "nuclear explosion",
  "nuclear attack",
  "nuclear strike",
  "nuclear detonation",
  "nuclear blast",
  "atomic bomb",
  "nuclear warhead",
  "nuclear missile launched",
  "radiation detected",
  "dirty bomb",
  // Broader catch — AI decides if it's a real threat
  "nuclear weapon",
  "nuclear bomb",
  "nuclear-capable",
  "nuclear launch",
  "nuclear test",
  "nuclear threat",
  "nuclear arsenal",
  "nuclear incident",
  "radioactive release",
  "ballistic missile"
];

/**
 * Checks whether a news article contains nuclear-related keywords.
 * Searches within title + description combined.
 * @param {{ title: string, description: string }} news
 * @returns {boolean}
 */
export function containsKeywords(news) {
  const text = `${news.title} ${news.description}`.toLowerCase();
  return KEYWORDS.some((keyword) => text.includes(keyword.toLowerCase()));
}
