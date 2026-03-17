import axios from "axios";

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions";

// Free default model on OpenRouter.
// arcee-ai/trinity-large-preview:free  → large non-reasoning model, ideal for JSON output
// Other free options:
//   openrouter/hunter-alpha              (1T params, logs prompts)
//   nvidia/nemotron-3-super-120b-a12b:free (reasoning model — needs max_tokens ≥ 2048)
//   stepfun/step-3.5-flash:free          (reasoning model)
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL ?? "arcee-ai/trinity-large-preview:free";

/**
 * @typedef {{ is_real_event: boolean, confidence: number, ambiguity: boolean }} AIResult
 */

/**
 * Builds the strict verification prompt sent to OpenRouter.
 * The model must return a JSON object — nothing else.
 * @param {Array<{ title: string, description: string, source: string, url: string }>} articles
 * @returns {string}
 */
function buildPrompt(articles) {
  const articleLines = articles
    .map(
      (a, i) =>
        `Article ${i + 1}:\n  Source: ${a.source}\n  Title: ${a.title}\n  Description: ${a.description}\n  URL: ${a.url}`
    )
    .join("\n\n");

  return `You are a strict nuclear event verification system. Your only job is to evaluate whether the articles below describe a REAL, confirmed nuclear detonation, nuclear attack, or equivalent event.

Return ONLY a raw JSON object with NO markdown, NO explanation, NO extra text. Do NOT wrap it in backticks or code blocks.

Format:
{
  "is_real_event": boolean,
  "confidence": number(0-1),
  "ambiguity": boolean
}

Rules:
- is_real_event is TRUE only if there is a confirmed real-world nuclear detonation or attack.
- Set confidence between 0 and 1.
- ambiguity is TRUE if the event could be a test, simulation, exercise, drill, or fictional/hypothetical scenario.
- Ignore rumors, speculation, political threats, or historical events.
- Ignore nuclear energy plant incidents unless they involve a weapon-grade nuclear explosion.

Articles to evaluate:
${articleLines}`;
}

/**
 * Calls OpenRouter with the filtered articles and parses the response.
 * Uses the OpenAI-compatible chat completions endpoint.
 * @param {Array<object>} articles
 * @returns {Promise<AIResult>}
 */
export async function validateWithAI(articles) {
  if (!OPENROUTER_API_KEY) {
    throw new Error("OPENROUTER_API_KEY environment variable is not set.");
  }

  const prompt = buildPrompt(articles);

  const payload = {
    model: OPENROUTER_MODEL,
    messages: [
      {
        role: "user",
        content: prompt,
      },
    ],
    temperature: 0.0,
    // 2048 gives reasoning models enough budget to think + produce output.
    // Non-reasoning models will simply stop after the JSON.
    max_tokens: 2048,
  };

  const response = await axios.post(OPENROUTER_API_URL, payload, {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
      "HTTP-Referer": "https://github.com/nuclear-alert-system",
      "X-Title": "Nuclear Alert System",
    },
    timeout: 15000,
  });

  const rawText =
    response.data?.choices?.[0]?.message?.content ?? "";

  return parseAIResponse(rawText);
}

/**
 * Parses and validates the raw text returned by Gemini.
 * Strips any accidental markdown fencing before parsing.
 * @param {string} rawText
 * @returns {AIResult}
 */
function parseAIResponse(rawText) {
  // Strip optional ```json ... ``` or ``` ... ``` wrapping
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();

  let parsed;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    console.error("[AI] Failed to parse OpenRouter response:", rawText);
    // Return a safe default — do NOT confirm the event on a parse failure
    return { is_real_event: false, confidence: 0, ambiguity: true };
  }

  return {
    is_real_event: Boolean(parsed.is_real_event),
    confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0,
    ambiguity: Boolean(parsed.ambiguity),
  };
}
