#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# EAS Mac Monitor — Test Script
# Simulates a CONFIRMED alert to verify sound and notification work correctly.
# ─────────────────────────────────────────────────────────────────────────────

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/config.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      EAS MONITOR — TEST MODE         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Test 1: Network + GitHub token ────────────────────────────────────────────
echo "→ Test 1: Fetching status.json from GitHub..."
RESPONSE=$(curl -s \
  -w "\n__HTTP_STATUS__%{http_code}" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Cache-Control: no-cache" \
  "$STATUS_URL")

HTTP_CODE=$(echo "$RESPONSE" | grep "__HTTP_STATUS__" | sed 's/__HTTP_STATUS__//')
BODY=$(echo "$RESPONSE" | grep -v "__HTTP_STATUS__")

if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ GitHub connection OK (HTTP 200)"
  STATUS=$(python3 -c "
import json
try:
    data = json.loads('''$BODY''')
    print(data.get('status','?'))
except:
    print('PARSE ERROR')
")
  echo "   Current status: $STATUS"
  CONFIDENCE=$(python3 -c "
import json
try:
    data = json.loads('''$BODY''')
    print(data.get('confidence', 0))
except:
    print('?')
")
  echo "   Confidence:      $CONFIDENCE"
  LAST_CHECKED=$(python3 -c "
import json
try:
    data = json.loads('''$BODY''')
    print(data.get('last_checked','?'))
except:
    print('?')
")
  echo "   Last checked:    $LAST_CHECKED"
else
  echo "   ❌ GitHub connection FAILED (HTTP $HTTP_CODE)"
  echo "   Check GITHUB_TOKEN in config.sh"
  exit 1
fi

echo ""

# ── Test 2: macOS notification ────────────────────────────────────────────────
echo "→ Test 2: Sending macOS notification..."
osascript -e 'display notification "EAS test — system alert is working ✅" with title "⚠️ EAS ALERT TEST" sound name "Sosumi"'
echo "   ✅ Notification sent (check top-right corner)"
echo ""

# ── Test 3: Sound + AI-generated TTS ─────────────────────────────────────────
echo "→ Test 3: Generating AI broadcast message + playing with alarm..."

# Simulate a real CONFIRMED event with fake sources
FAKE_JSON='{"status":"CONFIRMED","confidence":0.96,"sources":["BBC News","Al Jazeera English","Reuters"],"last_updated":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","last_checked":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'

echo "   Calling OpenRouter to generate personalized message..."
AI_JSON=$(EAS_JSON="$FAKE_JSON" EAS_KEY="$OPENROUTER_API_KEY" EAS_MODEL="$OPENROUTER_MODEL" python3 -c "
import json, os, urllib.request

raw = os.environ.get('EAS_JSON', '{}')
api_key = os.environ.get('EAS_KEY', '')
model = os.environ.get('EAS_MODEL', 'arcee-ai/trinity-large-preview:free')

try:
    data = json.loads(raw)
    confidence_pct = int(data.get('confidence', 0) * 100)
    sources = data.get('sources', [])
    last_updated = data.get('last_updated', 'unknown time')
    sources_text = ', '.join(sources) if sources else 'multiple international sources'

    prompt = (
        'You are a broadcaster for an Emergency Alert System (EAS). '
        'Generate a JSON object with exactly two keys: '
        '\"en\": an English EAS-style broadcast message, max 4 sentences, serious and informative. '
        'Always start with: ATTENTION. THIS IS AN EMERGENCY ALERT SYSTEM BROADCAST. '
        'Mention the specific news sources reporting the event. '
        'Instruct listeners to stay tuned to official channels. '
        '\"es\": the same information in neutral Colombian Spanish. '
        'Always start with: ATENCION. ATENCION. '
        'Do not advise seeking physical shelter. Keep population informed. '
        f'Event data: system confidence {confidence_pct}%, '
        f'reported by: {sources_text}, detected at: {last_updated}. '
        'Reply with ONLY the raw JSON object. No markdown, no code fences.'
    )

    payload = json.dumps({
        'model': model,
        'max_tokens': 400,
        'messages': [{'role': 'user', 'content': prompt}]
    }).encode()

    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions',
        data=payload,
        headers={
            'Authorization': 'Bearer ' + api_key,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/JuanFelipeLH/EAS',
            'X-Title': 'EAS Monitor'
        }
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
        text = result['choices'][0]['message']['content'].strip()
        if text.startswith('\`\`\`'):
            text = text.split('\n', 1)[1].rsplit('\`\`\`', 1)[0].strip()
        parsed = json.loads(text)
        print(json.dumps({'en': parsed.get('en', ''), 'es': parsed.get('es', '')}))
except Exception as e:
    import sys
    sys.stderr.write('AI error: ' + str(e) + '\n')
    print('')
" 2>/dev/null)

SCREEN_MSG=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('en',''))" <<< "$AI_JSON" 2>/dev/null)
VOICE_MSG=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('es',''))" <<< "$AI_JSON" 2>/dev/null)

if [ -z "$SCREEN_MSG" ]; then
  SCREEN_MSG="ATTENTION. THIS IS AN EMERGENCY ALERT SYSTEM BROADCAST. A nuclear event has been confirmed by multiple intelligence sources. Please stay tuned to official news channels for further information."
  echo "   ⚠️  AI screen message failed — using fallback"
else
  echo "   ✅ AI messages generated:"
  echo "   [EN] \"$SCREEN_MSG\""
fi
if [ -z "$VOICE_MSG" ]; then
  VOICE_MSG="ATENCION. ATENCION. El Sistema de Alertas de Emergencia ha confirmado un posible evento nuclear. Manténgase informado a través de sus canales de noticias habituales."
  echo "   ⚠️  AI voice message failed — using fallback"
else
  echo "   [ES] \"$VOICE_MSG\""
fi

echo ""
echo "→ Playing alarm + screen + TTS..."
echo "$SCREEN_MSG" > ~/eas-monitor/current_alert_msg.txt
bash ~/eas-monitor/alert_screen.sh "$SCREEN_MSG" &
SCREEN_PID=$!
if [ -f "$ALERT_SOUND" ]; then
  afplay -v 2 "$ALERT_SOUND" &
  ALARM_PID=$!
  sleep 1.5
  say -v Juan -r 175 "$VOICE_MSG" 2>/dev/null || true
  say -v Juan -r 175 "$VOICE_MSG" 2>/dev/null || true
  wait "$ALARM_PID" 2>/dev/null
  echo "   ✅ EAS sound + AI TTS played"
else
  echo "   ⚠️  MP3 not found — using system fallback"
  afplay -v 2 "$FALLBACK_SOUND" &
  ALARM_PID=$!
  sleep 1.5
  say -v Juan -r 175 "$VOICE_MSG" 2>/dev/null || true
  say -v Juan -r 175 "$VOICE_MSG" 2>/dev/null || true
  wait "$ALARM_PID" 2>/dev/null
  echo "   ✅ Fallback sound + AI TTS played"
fi
kill "$SCREEN_PID" 2>/dev/null || true
rm -f ~/eas-monitor/current_alert_msg.txt

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  All tests passed. System is ready.  ║"
echo "╚══════════════════════════════════════╝"
echo ""
