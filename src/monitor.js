import { readFileSync, writeFileSync, existsSync } from "fs";
import { fetchNuclearNews } from "./services/news.service.js";
import { validateWithAI } from "./services/ai.service.js";
import { isTrustedSource } from "./validators/source.validator.js";
import { containsKeywords } from "./validators/keyword.validator.js";
import { hasMultipleSources } from "./validators/multiSource.validator.js";

const STATUS_PATH = "data/status.json";
const HISTORY_PATH = "data/history.json";
const LOG_PATH = "data/processing_log.json";

// Log entries older than this are purged automatically
const LOG_MAX_AGE_HOURS = 48;

const AI_CONFIDENCE_THRESHOLD = 0.9;

/**
 * Reads and parses a JSON file. Returns a default value if the file is missing.
 * @template T
 * @param {string} path
 * @param {T} defaultValue
 * @returns {T}
 */
function readJSON(path, defaultValue) {
  if (!existsSync(path)) return defaultValue;
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return defaultValue;
  }
}

/**
 * Writes an object to a JSON file with readable formatting.
 * @param {string} path
 * @param {object} data
 */
function writeJSON(path, data) {
  writeFileSync(path, JSON.stringify(data, null, 2), "utf-8");
}

/**
 * Appends a record to history.json.
 * Keeps only the last 100 entries to avoid unlimited growth.
 * @param {object} record
 */
function appendHistory(record) {
  const history = readJSON(HISTORY_PATH, []);
  history.unshift(record);
  if (history.length > 100) history.length = 100;
  writeJSON(HISTORY_PATH, history);
}

/**
 * Saves one full processing run to processing_log.json.
 * Auto-purges entries older than LOG_MAX_AGE_HOURS.
 *
 * Each run entry:
 * {
 *   run_at: ISO string,
 *   discarded_untrusted: [{ title, source, url }],
 *   discarded_no_keywords: [{ title, source, url }],
 *   passed_filters: [{ title, source, url }],
 *   ai_result: { is_real_event, confidence, ambiguity } | null,
 *   final_status: "NONE" | "SUSPECTED" | "CONFIRMED"
 * }
 *
 * @param {object} entry
 */
function appendProcessingLog(entry) {
  const log = readJSON(LOG_PATH, []);

  // Purge old entries
  const cutoff = Date.now() - LOG_MAX_AGE_HOURS * 60 * 60 * 1000;
  const pruned = log.filter((e) => new Date(e.run_at).getTime() > cutoff);

  pruned.unshift(entry);
  writeJSON(LOG_PATH, pruned);
}

/**
 * Core monitoring routine. Runs the full pipeline:
 * fetch → filter → AI validate → save.
 */
async function run() {
  const now = new Date().toISOString();
  console.log(`[${now}] Nuclear monitor started.`);

  // Processing log entry built up throughout the run
  const logEntry = {
    run_at: now,
    discarded_untrusted: [],
    discarded_no_keywords: [],
    passed_filters: [],
    ai_result: null,
    final_status: "NONE",
  };

  const previous = readJSON(STATUS_PATH, {
    status: "NONE",
    confidence: 0,
    sources: [],
    last_checked: null,
    last_updated: null,
  });

  // ── Step 1: Fetch news ──────────────────────────────────────────────────────
  let allArticles;
  try {
    allArticles = await fetchNuclearNews();
    console.log(`[Monitor] Fetched ${allArticles.length} articles.`);
  } catch (err) {
    console.error("[Monitor] Failed to fetch news:", err.message);
    writeJSON(STATUS_PATH, { ...previous, last_checked: now });
    process.exit(1);
  }

  // ── Step 2: Filter by trusted source ────────────────────────────────────────
  const fromTrusted = [];
  for (const article of allArticles) {
    if (isTrustedSource(article)) {
      fromTrusted.push(article);
    } else {
      logEntry.discarded_untrusted.push({
        title: article.title,
        source: article.source,
        url: article.url,
      });
    }
  }
  console.log(`[Monitor] Articles from trusted sources: ${fromTrusted.length}`);
  console.log(`[Monitor] Discarded (untrusted source): ${logEntry.discarded_untrusted.length}`);

  // ── Step 3: Filter by keywords ──────────────────────────────────────────────
  const withKeywords = [];
  for (const article of fromTrusted) {
    if (containsKeywords(article)) {
      withKeywords.push(article);
    } else {
      logEntry.discarded_no_keywords.push({
        title: article.title,
        source: article.source,
        url: article.url,
      });
    }
  }
  logEntry.passed_filters = withKeywords.map((a) => ({
    title: a.title,
    source: a.source,
    url: a.url,
  }));
  console.log(`[Monitor] Articles with nuclear keywords: ${withKeywords.length}`);
  console.log(`[Monitor] Discarded (no keywords): ${logEntry.discarded_no_keywords.length}`);

  // ── Step 4: Early exit — no keyword matches means no AI call needed ─────────
  if (withKeywords.length === 0) {
    console.log("[Monitor] No keyword matches. Status remains NONE.");
    logEntry.final_status = "NONE";
    appendProcessingLog(logEntry);
    writeJSON(STATUS_PATH, {
      status: "NONE",
      confidence: 0,
      sources: [],
      last_checked: now,
      last_updated: previous.status !== "NONE" ? now : previous.last_updated,
    });
    process.exit(0);
  }

  // ── Step 5: Multi-source check ──────────────────────────────────────────────
  const multiSource = hasMultipleSources(withKeywords);
  console.log(`[Monitor] Multi-source check passed: ${multiSource}`);

  // ── Step 6: AI validation ───────────────────────────────────────────────────
  let aiResult;
  try {
    aiResult = await validateWithAI(withKeywords);
    logEntry.ai_result = aiResult;
    console.log("[Monitor] AI result:", aiResult);
  } catch (err) {
    console.error("[Monitor] AI validation failed:", err.message);
    appendProcessingLog(logEntry);
    writeJSON(STATUS_PATH, { ...previous, last_checked: now });
    process.exit(1);
  }

  // ── Step 7: Determine final status ─────────────────────────────────────────
  let newStatus;

  const isConfirmed =
    multiSource &&
    aiResult.is_real_event &&
    aiResult.confidence >= AI_CONFIDENCE_THRESHOLD &&
    !aiResult.ambiguity;

  const isSuspected =
    withKeywords.length >= 1 &&
    aiResult.is_real_event &&
    aiResult.confidence >= 0.5 &&
    !isConfirmed;

  if (isConfirmed) {
    newStatus = "CONFIRMED";
  } else if (isSuspected) {
    newStatus = "SUSPECTED";
  } else {
    newStatus = "NONE";
  }

  console.log(`[Monitor] Determined status: ${newStatus}`);

  const sourceNames = [...new Set(withKeywords.map((a) => a.source))];

  const newStatusRecord = {
    status: newStatus,
    confidence: aiResult.confidence,
    sources: sourceNames,
    last_checked: now,
    last_updated: newStatus !== previous.status ? now : previous.last_updated,
  };

  // ── Step 8: Save processing log ────────────────────────────────────────────
  logEntry.final_status = newStatus;
  appendProcessingLog(logEntry);

  // ── Step 9: Save status and history only if status changed ─────────────────
  if (newStatus !== previous.status) {
    console.log(
      `[Monitor] Status changed: ${previous.status} → ${newStatus}. Saving.`
    );
    writeJSON(STATUS_PATH, newStatusRecord);
    appendHistory({
      ...newStatusRecord,
      articles: withKeywords.map((a) => ({ title: a.title, source: a.source, url: a.url })),
    });
  } else {
    console.log(`[Monitor] Status unchanged (${newStatus}). Updating last_checked only.`);
    writeJSON(STATUS_PATH, newStatusRecord);
  }

  console.log("[Monitor] Done.");
}

run().catch((err) => {
  console.error("[Monitor] Unhandled error:", err);
  process.exit(1);
});
