/**
 * Checks whether there are at least 2 independent articles matching the event.
 * This prevents false positives from a single misreported story.
 * @param {Array<object>} events - Filtered news articles that passed all other validators
 * @param {number} [minSources=2]
 * @returns {boolean}
 */
export function hasMultipleSources(events, minSources = 2) {
  const uniqueSources = new Set(events.map((e) => e.source.toLowerCase()));
  return uniqueSources.size >= minSources;
}
