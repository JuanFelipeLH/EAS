# EAS — Nuclear Alert System (Serverless + ESP32)

A completely serverless nuclear event monitoring system.  
No 24/7 server required — GitHub Actions runs the pipeline every 5 minutes.

---

## Architecture

```
GitHub Actions (cron */5 * * * *)
  → Node.js script
    → Fetch news (NewsAPI)
    → Filter: trusted sources
    → Filter: nuclear keywords
    → Validate: AI (Gemini)
    → Validate: multi-source (≥2 outlets)
    → Write data/status.json
      → ESP32 polls JSON via HTTP
        → Activates servo/buzzer if CONFIRMED
```

---

## Status Values

| Value       | Meaning                                               |
|-------------|------------------------------------------------------ |
| `NONE`      | Nothing detected                                      |
| `SUSPECTED` | Keywords found + AI agrees but confidence < 0.9      |
| `CONFIRMED` | All 4 gates passed — multiple sources, AI confidence ≥ 0.9, no ambiguity |

---

## Project Structure

```
.
├── src/
│   ├── monitor.js                  ← Entry point
│   ├── services/
│   │   ├── news.service.js         ← Fetches & normalises NewsAPI data
│   │   └── ai.service.js           ← Calls Gemini for event validation
│   └── validators/
│       ├── source.validator.js     ← Trusted-source filter
│       ├── keyword.validator.js    ← Nuclear keyword filter
│       └── multiSource.validator.js← Requires ≥2 independent sources
├── data/
│   ├── status.json                 ← Current alert status (public)
│   └── history.json                ← Last 100 status changes
├── esp32/
│   └── nuclear_alert/
│       └── nuclear_alert.ino       ← Arduino sketch for ESP32
├── .github/
│   └── workflows/
│       └── monitor.yml             ← GitHub Actions cron workflow
└── .env.example                    ← Required environment variables
```

---

## Setup

### 1. Clone and install

```bash
git clone https://github.com/YOUR_USER/YOUR_REPO.git
cd YOUR_REPO
npm install
```

### 2. Add Secrets to GitHub

Go to **Settings → Secrets and variables → Actions** and add:

| Secret name      | Value                           |
|------------------|---------------------------------|
| `NEWS_API_KEY`   | Your key from newsapi.org       |
| `GEMINI_API_KEY` | Your key from Google AI Studio  |

### 3. Enable GitHub Actions

Push to `main`. The workflow runs automatically every 5 minutes.  
You can also trigger it manually from the **Actions** tab → `nuclear-monitor` → **Run workflow**.

### 4. Make `data/` publicly accessible

Ensure your repository is **public**, or the ESP32 will not be able to read the raw JSON file.  
The ESP32 polls:

```
https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/data/status.json
```

---

## ESP32 Setup

### Libraries (Arduino Library Manager)

| Library        | Author              |
|----------------|---------------------|
| `ArduinoJson`  | Benoit Blanchon     |
| `ESP32Servo`   | Kevin Harrington    |

### Configuration

Open `esp32/nuclear_alert/nuclear_alert.ino` and edit:

```cpp
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
const char* STATUS_URL    = "https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/data/status.json";
const int   SERVO_PIN     = 18;   // Servo signal pin
const int   BUZZER_PIN    = 19;   // Buzzer pin
```

Flash to your ESP32. It will poll every 5 minutes and activate the servo + buzzer if status is `CONFIRMED`.

---

## Local Development

```bash
cp .env.example .env
# Fill in your keys in .env

node src/monitor.js
```

---

## Security Notes

- API keys are stored only as GitHub Actions secrets — never committed.
- The alert requires **all four** conditions simultaneously: trusted source + keywords + AI confidence ≥ 0.9 + multiple independent outlets. A single failing gate keeps status at `NONE`.
- The AI service returns a safe default (`is_real_event: false`) on any parse failure.
- `[skip ci]` is appended to automated commits to prevent recursive workflow triggers.
