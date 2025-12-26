# Tafsir Study Tool - Web App Conversion Plan

## Overview

Convert the CLI-based tafsir study tool into an elegant single-page web application with:
- **Backend**: FastAPI server with SSE streaming for Claude responses
- **Frontend**: React + Vite with design system inspired by mohsin-ismail
- **Features**: All CLI workflows (sources, study, iraab, roots, read, quran, cache)

## Architecture

```
tafsir-tool/
├── api/                      # FastAPI backend
│   ├── main.py              # App entry, CORS, routes
│   ├── routes/
│   │   ├── sources.py       # GET /api/sources
│   │   ├── tafsir.py        # GET /api/tafsir/{source}/{surah}/{ayah}
│   │   ├── quran.py         # GET /api/quran/{surah}/{ayah}
│   │   ├── study.py         # POST /api/study/* (streaming)
│   │   └── cache.py         # GET/DELETE /api/cache
│   └── streaming.py         # SSE helpers for Claude streaming
├── web/                      # React + Vite frontend
│   ├── src/
│   │   ├── components/
│   │   │   ├── layout/      # Header, PageLayout, Sidebar
│   │   │   ├── features/    # StudyPanel, SourceSelector, VerseInput
│   │   │   └── ui/          # Button, Card, Toast, LoadingSpinner
│   │   ├── contexts/        # ThemeContext, StudySessionContext
│   │   ├── hooks/           # useStreaming, useApi, useSources
│   │   ├── pages/           # Home, Study, Sources, About
│   │   ├── styles/          # tokens.css, base.css, components/
│   │   └── utils/           # api.js, markdown.js
│   ├── index.html
│   ├── vite.config.js
│   └── package.json
├── tafsir/                   # Existing Python modules (unchanged)
├── cli.py                    # Keep existing CLI
└── pyproject.toml           # Add FastAPI deps
```

---

## Phase 1: Backend API (FastAPI)

### 1.1 Dependencies
Add to `pyproject.toml`:
```toml
"fastapi>=0.115.0",
"uvicorn>=0.30.0",
"sse-starlette>=2.0.0",
```

### 1.2 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/sources` | GET | List all tafsir sources (with optional category filter) |
| `/api/tafsir/{source}/{surah}/{ayah}` | GET | Fetch Arabic tafsir text |
| `/api/quran/{surah}/{ayah}` | GET | Fetch Quranic verse text |
| `/api/study/start` | POST | Start study session, return intro (SSE stream) |
| `/api/study/attempt` | POST | Submit translation attempt (SSE stream) |
| `/api/study/hint` | POST | Request next hint (SSE stream) |
| `/api/study/iraab` | POST | Get grammatical analysis (SSE stream) |
| `/api/study/roots` | POST | Get root analysis (SSE stream) |
| `/api/study/reveal` | POST | Reveal full translation (SSE stream) |
| `/api/cache/stats` | GET | Get cache statistics |
| `/api/cache` | DELETE | Clear cache |
| `/api/surahs` | GET | List all 114 surahs with metadata |

### 1.3 Streaming Implementation

```python
# api/streaming.py
from sse_starlette.sse import EventSourceResponse

async def stream_claude_response(client, messages, system):
    """Generator that yields SSE events from Claude streaming."""
    with client.messages.stream(
        model="claude-sonnet-4-20250514",
        max_tokens=4000,
        system=system,
        messages=messages,
    ) as stream:
        for text in stream.text_stream:
            yield {"event": "message", "data": text}
    yield {"event": "done", "data": ""}
```

### 1.4 Session Management
- Store study sessions in-memory dict (keyed by session_id)
- Session includes: verse, source, hint_level, attempts, hints_given
- Session expires after 1 hour of inactivity

### 1.5 Error Handling
- Wrap all endpoints in try/except
- Return structured errors: `{"error": "message", "code": "ERROR_CODE"}`
- Error codes: `SOURCE_NOT_FOUND`, `VERSE_NOT_FOUND`, `API_ERROR`, `RATE_LIMITED`

---

## Phase 2: Frontend Foundation

### 2.1 Project Setup
```bash
cd tafsir-tool
npm create vite@latest web -- --template react
cd web && npm install
```

### 2.2 Design System (Inspired by mohsin-ismail)

**tokens.css** - CSS custom properties:
```css
/* Colors - Warm scholarly palette */
--color-bg: #faf6f0;           /* Warm cream (paper) */
--color-text: #1a1612;         /* Rich ink */
--color-primary: #2d5a4a;      /* Deep teal (Islamic geometric) */
--color-accent: #8b6914;       /* Warm gold */
--color-arabic: #1a1612;       /* For Arabic text */

/* Dark mode */
[data-theme="dark"] {
  --color-bg: #1a1612;
  --color-text: #e8e2d8;
  --color-surface: #2a2420;
}

/* Typography */
--font-arabic: 'Amiri', 'Traditional Arabic', serif;
--font-display: 'DM Serif Display', Georgia, serif;
--font-body: 'Newsreader', Georgia, serif;
--font-mono: 'JetBrains Mono', monospace;

/* Spacing (8px base) */
--space-1: 4px;
--space-2: 8px;
--space-3: 12px;
--space-4: 16px;
--space-6: 24px;
--space-8: 32px;

/* Animations */
--duration-fast: 150ms;
--duration-normal: 250ms;
--duration-slow: 400ms;
--ease-out: cubic-bezier(0.33, 1, 0.68, 1);
--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);

/* Shadows */
--shadow-card: 0 2px 8px rgba(26, 22, 18, 0.08),
               0 4px 16px rgba(26, 22, 18, 0.04);
--shadow-elevated: 0 8px 24px rgba(26, 22, 18, 0.12);
```

### 2.3 Component Hierarchy

```
App
├── ThemeProvider
├── Header
│   ├── Logo/Title
│   ├── Navigation (Sources, Study, About)
│   └── ThemeToggle
├── Main Content
│   ├── HomePage
│   │   ├── HeroSection (brief intro + quick start)
│   │   ├── WorkflowCards (study, iraab, roots, read)
│   │   └── QuickVerseInput
│   ├── StudyPage
│   │   ├── SourceSelector
│   │   ├── VerseInput
│   │   ├── StudyPanel
│   │   │   ├── ArabicTextDisplay (large, beautiful Arabic)
│   │   │   ├── ResponseStream (animated streaming text)
│   │   │   ├── CommandBar (hint, iraab, roots, reveal)
│   │   │   └── UserInput
│   │   └── ProgressIndicator (hint level, attempts)
│   ├── SourcesPage
│   │   ├── CategoryFilter (tafsir, grammar, lexicon)
│   │   └── SourceGrid
│   └── AboutPage
│       └── HowToUse instructions
└── Toast (notifications)
```

---

## Phase 3: Core UI Components

### 3.1 Arabic Text Display
```jsx
// Beautiful large Arabic text with proper RTL and font
<div className="arabic-text" dir="rtl" lang="ar">
  {arabicText}
</div>
```

CSS:
```css
.arabic-text {
  font-family: var(--font-arabic);
  font-size: clamp(1.4rem, 4vw, 2rem);
  line-height: 2.2;
  text-align: right;
  direction: rtl;
  padding: var(--space-6);
  background: var(--color-surface);
  border-radius: 12px;
  box-shadow: var(--shadow-card);
}
```

### 3.2 Streaming Response Component
```jsx
function ResponseStream({ sessionId, endpoint, onComplete }) {
  const [text, setText] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);

  useEffect(() => {
    const eventSource = new EventSource(`/api/study/${endpoint}`);
    setIsStreaming(true);

    eventSource.onmessage = (e) => {
      setText(prev => prev + e.data);
    };

    eventSource.addEventListener('done', () => {
      setIsStreaming(false);
      eventSource.close();
      onComplete?.();
    });

    return () => eventSource.close();
  }, [sessionId, endpoint]);

  return (
    <div className={`response ${isStreaming ? 'streaming' : ''}`}>
      <Markdown>{text}</Markdown>
      {isStreaming && <StreamingCursor />}
    </div>
  );
}
```

### 3.3 Command Bar
```jsx
function CommandBar({ onCommand, disabled }) {
  const commands = [
    { key: 'hint', label: 'Hint', icon: '💡', color: 'yellow' },
    { key: 'iraab', label: 'Grammar', icon: '📝', color: 'purple' },
    { key: 'roots', label: 'Roots', icon: '🌳', color: 'green' },
    { key: 'reveal', label: 'Reveal', icon: '👁️', color: 'blue' },
  ];

  return (
    <div className="command-bar">
      {commands.map(cmd => (
        <Button
          key={cmd.key}
          variant="outline"
          onClick={() => onCommand(cmd.key)}
          disabled={disabled}
        >
          {cmd.label}
        </Button>
      ))}
    </div>
  );
}
```

### 3.4 Verse Input
```jsx
function VerseInput({ onSubmit }) {
  const [surah, setSurah] = useState('');
  const [ayah, setAyah] = useState('');

  // Surah autocomplete with Arabic names
  // Validates range (1-114 for surah, appropriate max for ayah)
}
```

---

## Phase 4: Animations & Polish

### 4.1 Page Transitions
- Fade in/out on route change (via PageTransitionContext)
- Staggered content reveal

### 4.2 Streaming Text Animation
```css
.response.streaming .cursor {
  display: inline-block;
  width: 2px;
  height: 1.2em;
  background: var(--color-primary);
  animation: blink 1s step-end infinite;
}

@keyframes blink {
  50% { opacity: 0; }
}
```

### 4.3 Card Hover Effects
```css
.workflow-card {
  transition: transform var(--duration-normal) var(--ease-out),
              box-shadow var(--duration-normal) var(--ease-out);
}

.workflow-card:hover {
  transform: translateY(-4px);
  box-shadow: var(--shadow-elevated);
}
```

### 4.4 Arabic Text Shimmer (on load)
```css
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.arabic-text.loading {
  background: linear-gradient(
    90deg,
    var(--color-surface) 25%,
    var(--color-surface-elevated) 50%,
    var(--color-surface) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}
```

---

## Phase 5: Error Handling & Instructions

### 5.1 Error States
- Network errors: Show retry button with message
- API key missing: Show setup instructions
- Source not found: Suggest alternatives
- Rate limited: Show wait time

### 5.2 Instructions/Help Panel

**Home page hero section:**
```markdown
## Learn Arabic Through Tafsir

Study classical Islamic texts with guided instruction.
No instant translations - work for understanding with progressive hints.

### Workflows

**📖 Study Mode** - Interactive Socratic tutoring
**📝 Grammar (I'rab)** - Detailed grammatical analysis
**🌳 Root Analysis** - Vocabulary building through roots
**📜 Read** - Plain Arabic text display
```

**Study page sidebar:**
```markdown
### Commands

- Type your translation attempt and press Enter
- **hint** - Get progressive hints (roots → morphology → vocabulary)
- **iraab** - Full grammatical breakdown
- **roots** - Root letter analysis
- **reveal** - Show complete translation (use sparingly!)

### Hint Progression

1. Roots (الجذور) - Root letters
2. Morphology (الصرف) - Verb forms, patterns
3. Grammar (الإعراب) - Cases and roles
4. Vocabulary - Meaning hints
5. Structure - Sentence analysis
6. Partial - Fill in the blanks
7. Full - Complete translation
```

### 5.3 Toast Notifications
- Success: "Session started for Al-Baqara 255"
- Error: "Failed to fetch tafsir. Please try again."
- Info: "Hint level: MORPHOLOGY (3/7)"

---

## Phase 6: Implementation Order

### Step 1: Backend API
1. Create `api/main.py` with FastAPI app and CORS
2. Create `api/routes/sources.py` - sources endpoint
3. Create `api/routes/tafsir.py` - tafsir fetch endpoint
4. Create `api/routes/quran.py` - quran verse endpoint
5. Create `api/routes/study.py` - streaming study endpoints
6. Create `api/streaming.py` - SSE streaming helpers
7. Test all endpoints with curl

### Step 2: Frontend Foundation
1. Initialize Vite project in `web/`
2. Create `styles/tokens.css` design system
3. Create `styles/base.css` global styles
4. Create ThemeContext with dark mode
5. Create basic layout components (Header, PageLayout)

### Step 3: Core Features
1. Create SourceSelector component
2. Create VerseInput with surah autocomplete
3. Create ArabicTextDisplay component
4. Create ResponseStream with SSE
5. Create CommandBar
6. Wire up StudyPage with full flow

### Step 4: Additional Pages
1. HomePage with workflow cards
2. SourcesPage with filtering
3. AboutPage with instructions

### Step 5: Polish
1. Add animations and transitions
2. Add loading states and skeletons
3. Add error boundaries and error states
4. Add toast notifications
5. Test responsive design
6. Add keyboard shortcuts

---

## Files to Create

### Backend (6 files)
- `api/main.py`
- `api/routes/__init__.py`
- `api/routes/sources.py`
- `api/routes/tafsir.py`
- `api/routes/quran.py`
- `api/routes/study.py`
- `api/streaming.py`

### Frontend (~25 files)
- `web/package.json`
- `web/vite.config.js`
- `web/index.html`
- `web/src/main.jsx`
- `web/src/App.jsx`
- `web/src/styles/tokens.css`
- `web/src/styles/base.css`
- `web/src/styles/components/*.css`
- `web/src/contexts/ThemeContext.jsx`
- `web/src/contexts/StudyContext.jsx`
- `web/src/hooks/useApi.js`
- `web/src/hooks/useStreaming.js`
- `web/src/components/layout/Header.jsx`
- `web/src/components/layout/PageLayout.jsx`
- `web/src/components/ui/Button.jsx`
- `web/src/components/ui/Card.jsx`
- `web/src/components/ui/Toast.jsx`
- `web/src/components/features/SourceSelector.jsx`
- `web/src/components/features/VerseInput.jsx`
- `web/src/components/features/ArabicText.jsx`
- `web/src/components/features/ResponseStream.jsx`
- `web/src/components/features/CommandBar.jsx`
- `web/src/components/features/StudyPanel.jsx`
- `web/src/pages/Home.jsx`
- `web/src/pages/Study.jsx`
- `web/src/pages/Sources.jsx`
- `web/src/pages/About.jsx`

---

## Running the App

```bash
# Terminal 1: Backend
cd tafsir-tool
pip install fastapi uvicorn sse-starlette
uvicorn api.main:app --reload --port 8000

# Terminal 2: Frontend
cd tafsir-tool/web
npm install
npm run dev
```

Frontend proxies `/api/*` to backend via Vite config.
