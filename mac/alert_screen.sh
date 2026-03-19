#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# EAS Alert Screen — genera HTML estilo EAS y lo abre en Safari fullscreen
# Se queda corriendo hasta que el proceso padre lo mate (kill $screen_pid)
# ─────────────────────────────────────────────────────────────────────────────
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MSG="${1:-}"
if [ -z "$MSG" ] && [ -f "$DIR/current_alert_msg.txt" ]; then
  MSG=$(cat "$DIR/current_alert_msg.txt")
fi

HTML_FILE="/tmp/eas_alert_$(date +%s).html"

# Escapar caracteres HTML especiales
MSG_SAFE=$(echo "$MSG" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

cat > "$HTML_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>EMERGENCY ALERT SYSTEM</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=VT323&family=Share+Tech+Mono&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  @keyframes blink-cursor {
    0%, 49% { opacity: 1; }
    50%, 99% { opacity: 0; }
  }
  @keyframes fade-in {
    from { opacity: 0; }
    to   { opacity: 1; }
  }
  @keyframes ticker-scroll {
    0%   { transform: translateX(100vw); }
    100% { transform: translateX(-100%); }
  }

  html, body {
    width: 100%; height: 100%;
    background: #000;
    color: #fff;
    overflow: hidden;
  }

  /* CRT scanlines */
  body::after {
    content: '';
    position: fixed; inset: 0;
    background: repeating-linear-gradient(
      to bottom,
      transparent 0px,
      transparent 3px,
      rgba(0,0,0,0.18) 3px,
      rgba(0,0,0,0.18) 4px
    );
    pointer-events: none;
    z-index: 999;
  }

  /* Static white border — no pulse */
  .border-frame {
    position: fixed; inset: 0;
    border: 5px solid #fff;
    pointer-events: none;
    z-index: 998;
  }

  /* Red EAS header bar */
  .eas-header-bar {
    position: fixed;
    top: 0; left: 0; right: 0;
    background: #c0392b;
    padding: 10px 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
  }
  .eas-header-bar-text {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(1.6rem, 2.8vw, 2.4rem);
    letter-spacing: 0.3em;
    color: #fff;
  }

  /* Layout */
  .screen {
    position: absolute; inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 80px 60px 72px;
    animation: fade-in 0.15s steps(1) forwards;
  }

  .header {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(2.6rem, 5vw, 4.4rem);
    letter-spacing: 0.22em;
    color: #fff;
    text-align: center;
    line-height: 1;
    margin-bottom: 8px;
  }

  .divider {
    width: 90%;
    max-width: 820px;
    border: none;
    border-top: 2px solid #fff;
    margin: 0 auto 24px;
  }

  .issued-by {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(1.2rem, 2vw, 1.7rem);
    letter-spacing: 0.08em;
    color: #ccc;
    text-align: center;
    line-height: 2;
    margin-bottom: 8px;
  }

  .action-title {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(2rem, 3.8vw, 3.2rem);
    font-weight: normal;
    letter-spacing: 0.12em;
    color: #fff;
    text-align: center;
    line-height: 1.25;
    margin-bottom: 32px;
  }

  .message-box {
    width: 90%;
    max-width: 820px;
    border-top: 2px solid #fff;
    padding-top: 20px;
    text-align: left;
  }

  .message-label {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(0.9rem, 1.4vw, 1.1rem);
    letter-spacing: 0.2em;
    color: #888;
    margin-bottom: 10px;
  }

  #typewriter {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(1.4rem, 2.2vw, 1.85rem);
    line-height: 1.65;
    color: #fff;
    letter-spacing: 0.04em;
    white-space: pre-wrap;
  }

  .cursor {
    display: inline-block;
    width: 0.6ch;
    height: 1.1em;
    background: #fff;
    vertical-align: text-bottom;
    animation: blink-cursor 0.7s step-end infinite;
    margin-left: 2px;
  }

  /* Scrolling ticker at bottom */
  .ticker {
    position: fixed;
    bottom: 0; left: 0; right: 0;
    background: #c0392b;
    padding: 8px 0;
    overflow: hidden;
    z-index: 100;
  }
  .ticker-track {
    display: inline-block;
    white-space: nowrap;
    animation: ticker-scroll 35s linear infinite;
  }
  .ticker-text {
    font-family: 'VT323', 'Share Tech Mono', monospace;
    font-size: clamp(1.2rem, 1.8vw, 1.5rem);
    letter-spacing: 0.12em;
    color: #fff;
    padding-right: 80px;
  }

  .timestamp {
    position: fixed;
    bottom: 52px;
    right: 36px;
    font-family: Helvetica, Arial, sans-serif;
    font-size: clamp(0.85rem, 1.2vw, 1rem);
    font-weight: 400;
    color: #888;
    letter-spacing: 0.05em;
  }
</style>
</head>
<body>
<div class="border-frame"></div>

<div class="eas-header-bar">
  <span class="eas-header-bar-text">&#9654;&nbsp; EMERGENCY ALERT SYSTEM &nbsp;&#9654;</span>
</div>

<div class="screen">
  <div class="header">EMERGENCY ALERT SYSTEM</div>

  <hr class="divider">

  <div class="issued-by">
    THE FOLLOWING MESSAGE IS TRANSMITTED AT THE REQUEST OF<br>
    THE FEDERAL EMERGENCY MANAGEMENT AGENCY
  </div>

  <div class="action-title">
    EMERGENCY ACTION NOTIFICATION
  </div>

  <div class="message-box">
    <div class="message-label">// OFFICIAL MESSAGE //</div>
    <div id="typewriter"></div><span class="cursor"></span>
  </div>
</div>

<div class="timestamp" id="ts"></div>

<div class="ticker">
  <div class="ticker-track">
    <span class="ticker-text" id="ticker-text">EMERGENCY ALERT SYSTEM &#9654; EMERGENCY ACTION NOTIFICATION &#9654; THIS IS NOT A TEST &#9654; STAY TUNED TO OFFICIAL CHANNELS &#9654;</span>
  </div>
</div>

<script>
  function padZ(n) { return String(n).padStart(2,'0'); }
  function tick() {
    const d = new Date();
    document.getElementById('ts').textContent =
      padZ(d.getMonth()+1) + '/' + padZ(d.getDate()) + '/' + d.getFullYear() +
      '  ' + padZ(d.getHours()) + ':' + padZ(d.getMinutes()) + ':' + padZ(d.getSeconds());
  }
  tick();
  setInterval(tick, 1000);

  const msg = "$MSG_SAFE";
  const el  = document.getElementById('typewriter');
  let i = 0;
  setTimeout(function type() {
    if (i <= msg.length) {
      el.textContent = msg.slice(0, i);
      i++;
      setTimeout(type, 28);
    }
  }, 900);

  if (msg) {
    document.getElementById('ticker-text').textContent =
      'EMERGENCY ALERT SYSTEM \u25BA ' + msg.toUpperCase() + ' \u25BA STAY TUNED TO OFFICIAL CHANNELS \u25BA ';
  }
</script>
</body>
</html>
HTMLEOF

# ── Cleanup al salir (cuando monitor.sh mata este proceso) ────────────────────
cleanup() {
  osascript -e 'tell application "Safari"
    try
      close (every tab of every window whose URL contains "eas_alert")
    end try
  end tell' 2>/dev/null || true
  rm -f "$HTML_FILE"
}
trap cleanup EXIT INT TERM

# ── Abrir en el navegador predeterminado ─────────────────────────────────────
open "$HTML_FILE"
sleep 1

# Intentar fullscreen con CMD+CTRL+F (funciona en Safari y Chrome)
osascript << APPLESCRIPT 2>/dev/null || true
delay 0.8
tell application "System Events"
  key code 3 using {command down, control down}
end tell
APPLESCRIPT

# Mantenerse vivo hasta que el padre lo mate
while true; do sleep 1; done
