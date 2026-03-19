#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# EAS Mac Monitor — Main Daemon
# Polls status.json every 5 minutes. Plays EAS alert if CONFIRMED.
# ─────────────────────────────────────────────────────────────────────────────

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/config.sh"

# Full raw JSON from last status fetch (used for AI message generation)
LAST_RAW_JSON=""

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"

  # Rotate log if too long
  local lines
  lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$lines" -gt "$LOG_MAX_LINES" ]; then
    tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    log "Log rotated."
  fi
}

# ── Fetch status from GitHub ───────────────────────────────────────────────────
fetch_status() {
  local response
  response=$(curl -s \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Cache-Control: no-cache" \
    "$STATUS_URL" 2>/dev/null)

  if [ -z "$response" ]; then
    log "ERROR: Empty response from GitHub. Check token and network."
    LAST_RAW_JSON=""
    echo "ERROR"
    return
  fi

  LAST_RAW_JSON="$response"

  # Parse status field using Python (always available on macOS)
  local status
  status=$(python3 -c "
import json, sys
try:
    data = json.loads('''$response''')
    print(data.get('status', 'NONE'))
except Exception as e:
    print('PARSE_ERROR')
" 2>/dev/null)

  echo "$status"
}

# ── Generate AI broadcast message from event data ────────────────────────────
# Returns a JSON string: {"en": "...English screen msg...", "es": "...Spanish voice msg..."}
generate_ai_message() {
  local json_data="$1"
  local result
  result=$(EAS_JSON="$json_data" EAS_KEY="$OPENROUTER_API_KEY" EAS_MODEL="$OPENROUTER_MODEL" python3 -c "
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
    sys.stderr.write(str(e) + '\n')
    print('')
" 2>/dev/null)
  echo "$result"
}

# ── Play alert sound + TTS announcement ──────────────────────────────────────
# $1 = English message for screen display
# $2 = Spanish message for voice (say)
play_alert() {
  local screen_msg="$1"
  local voice_msg="$2"
  log "🚨 PLAYING ALERT SOUND + TTS + SCREEN"
  log "SCREEN: $screen_msg"
  log "VOICE:  $voice_msg"

  # Write English message so alert_screen can display it
  echo "$screen_msg" > "$DIR/current_alert_msg.txt"

  # Launch fullscreen EAS display in background
  bash "$DIR/alert_screen.sh" "$screen_msg" &
  local screen_pid=$!

  if [ -f "$ALERT_SOUND" ]; then
    for i in 1 2 3; do
      afplay -v 2 "$ALERT_SOUND" &
      local alarm_pid=$!
      sleep 1.5
      say -v Juan -r 175 "$voice_msg" 2>/dev/null || true
      say -v Juan -r 175 "$voice_msg" 2>/dev/null || true
      wait "$alarm_pid" 2>/dev/null
      sleep 1
    done
  else
    log "WARNING: EAS MP3 not found at $ALERT_SOUND. Using system fallback."
    for i in 1 2 3; do
      afplay -v 2 "$FALLBACK_SOUND" &
      local alarm_pid=$!
      sleep 1.5
      say -v Juan -r 175 "$voice_msg" 2>/dev/null || true
      say -v Juan -r 175 "$voice_msg" 2>/dev/null || true
      wait "$alarm_pid" 2>/dev/null
      sleep 0.5
    done
  fi

  # Close the screen after audio finishes
  kill "$screen_pid" 2>/dev/null || true
  rm -f "$DIR/current_alert_msg.txt"
}

# ── Mac notification ──────────────────────────────────────────────────────────
send_notification() {
  local title="$1"
  local message="$2"
  osascript -e "display notification \"$message\" with title \"$title\" sound name \"Sosumi\""
}

# ── Main loop ─────────────────────────────────────────────────────────────────
log "========================================="
log "EAS Monitor started. Polling every ${POLL_INTERVAL}s."
log "========================================="

LAST_STATUS=""

while true; do
  STATUS=$(fetch_status)
  log "Status: $STATUS"

  case "$STATUS" in
    CONFIRMED)
      log "🚨🚨🚨 CONFIRMED NUCLEAR EVENT DETECTED 🚨🚨🚨"
      send_notification "⚠️ EAS ALERT" "CONFIRMED NUCLEAR EVENT — CHECK STATUS"
      log "Generating AI broadcast message..."
      AI_JSON=$(generate_ai_message "$LAST_RAW_JSON")
      SCREEN_MSG=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('en',''))" <<< "$AI_JSON" 2>/dev/null)
      VOICE_MSG=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('es',''))" <<< "$AI_JSON" 2>/dev/null)
      if [ -z "$SCREEN_MSG" ]; then
        SCREEN_MSG="ATTENTION. THIS IS AN EMERGENCY ALERT SYSTEM BROADCAST. A nuclear event has been confirmed by multiple intelligence sources. Please stay tuned to official news channels for further information."
        log "AI screen message failed, using fallback."
      fi
      if [ -z "$VOICE_MSG" ]; then
        VOICE_MSG="ATENCION. ATENCION. El Sistema de Alertas de Emergencia ha confirmado un posible evento nuclear. Manténgase informado a través de sus canales de noticias habituales."
        log "AI voice message failed, using fallback."
      fi
      play_alert "$SCREEN_MSG" "$VOICE_MSG"
      # Keep alerting every poll cycle while CONFIRMED
      ;;
    SUSPECTED)
      if [ "$LAST_STATUS" != "SUSPECTED" ]; then
        log "⚠️  Status changed to SUSPECTED"
        send_notification "EAS Monitor" "Status: SUSPECTED — monitoring closely"
      fi
      ;;
    NONE)
      if [ "$LAST_STATUS" = "CONFIRMED" ] || [ "$LAST_STATUS" = "SUSPECTED" ]; then
        log "✅ Status returned to NONE"
        send_notification "EAS Monitor" "All clear — status back to NONE"
      fi
      ;;
    ERROR|PARSE_ERROR)
      log "WARNING: Could not read status. Will retry next cycle."
      ;;
    *)
      log "WARNING: Unknown status value: '$STATUS'"
      ;;
  esac

  LAST_STATUS="$STATUS"
  sleep "$POLL_INTERVAL"
done
