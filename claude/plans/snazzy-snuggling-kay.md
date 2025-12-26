# Tafsir.app Query Tool - Implementation Plan

## Overview
Create a CLI tool + Claude Code skill to query tafsir.app's internal API and translate Arabic tafsir content to English using Claude AI.

## API Discovery Summary
tafsir.app has no official public API, but exposes internal endpoints:
- **Tafsir content:** `GET https://tafsir.app/get.php?src={source}&s={surah}&a={ayah}&ver=1`
- **Source metadata:** `GET https://tafsir.app/sources/sources.json`
- **Quran text:** `GET https://tafsir.app/sources/quran.json`

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  CLI / Skill    │────▶│  tafsir-client   │────▶│  tafsir.app     │
│                 │     │  (Python lib)    │     │  (internal API) │
└─────────────────┘     └────────┬─────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌──────────────────┐
                        │  Claude API      │
                        │  (translation)   │
                        └──────────────────┘
```

## Implementation Steps

### Step 1: Create Project Structure
```
/Users/moose/Downloads/projects/tafsir-tool/
├── tafsir/
│   ├── __init__.py
│   ├── client.py          # API client for tafsir.app
│   ├── translator.py      # Claude translation wrapper
│   ├── models.py          # Data models (Source, Verse, Tafsir)
│   └── cache.py           # Local caching for API responses
├── cli.py                 # CLI entry point
├── requirements.txt
├── pyproject.toml
└── README.md
```

### Step 2: Core API Client (`tafsir/client.py`)
- Fetch and parse sources.json on init
- Methods:
  - `get_sources()` - list all 24+ tafsir sources with metadata
  - `get_tafsir(source_id, surah, ayah)` - fetch specific tafsir
  - `get_quran_text(surah, ayah)` - fetch Arabic verse text
  - `search(query)` - search across sources (if supported)
- Error handling for network failures
- Rate limiting (respectful scraping)

### Step 3: Translation Layer (`tafsir/translator.py`)
- Use Anthropic SDK to call Claude API
- System prompt optimized for Islamic scholarly translation:
  - Preserve Arabic terms with transliteration (e.g., "tawakkul (trust in Allah)")
  - Handle Quranic references properly
  - Maintain scholarly tone
- Caching of translations to reduce API costs
- Batch translation support for efficiency

### Step 4: CLI Implementation (`cli.py`)
Commands:
```bash
# List all available sources
tafsir sources

# Get tafsir with translation
tafsir get 2:255 --source ibn-kathir
tafsir get 1:1-7 --source tabari    # Range of verses

# Compare multiple tafasir
tafsir compare 2:255 --sources ibn-kathir,tabari,saadi

# Search (if supported)
tafsir search "الكرسي" --source tabari

# Output formats
tafsir get 2:255 --format json|markdown|plain

# Cache management
tafsir cache clear
tafsir cache stats
```

### Step 5: Claude Code Skill (`SKILL.md`)
Location: `~/.claude/skills/tafsir/SKILL.md`

Trigger phrases:
- `/tafsir 2:255` - Quick lookup
- `/tafsir compare 1:1` - Multi-source comparison
- `/tafsir sources` - List sources

The skill will invoke the CLI internally and format output for conversation.

### Step 6: Caching Strategy
- SQLite database for local cache
- Cache structure:
  - `sources` table (refreshed weekly)
  - `tafsir_arabic` table (permanent, keyed by source+surah+ayah)
  - `tafsir_english` table (translations, keyed by hash of Arabic)
- Cache invalidation: manual or time-based

## Key Files to Create

| File | Purpose |
|------|---------|
| `/Users/moose/Downloads/projects/tafsir-tool/tafsir/client.py` | HTTP client for tafsir.app API |
| `/Users/moose/Downloads/projects/tafsir-tool/tafsir/translator.py` | Claude API translation wrapper |
| `/Users/moose/Downloads/projects/tafsir-tool/tafsir/models.py` | Pydantic models for type safety |
| `/Users/moose/Downloads/projects/tafsir-tool/tafsir/cache.py` | SQLite caching layer |
| `/Users/moose/Downloads/projects/tafsir-tool/cli.py` | Click-based CLI |
| `/Users/moose/Downloads/projects/tafsir-tool/pyproject.toml` | Package config with dependencies |
| `~/.claude/skills/tafsir/SKILL.md` | Claude Code skill definition |

## Dependencies
```
httpx          # Async HTTP client
click          # CLI framework
rich           # Beautiful terminal output
anthropic      # Claude API SDK
pydantic       # Data validation
sqlite-utils   # SQLite helper
```

## Translation Prompt Strategy

```
You are translating classical Islamic tafsir (Quranic exegesis) from Arabic to English.

Guidelines:
1. Preserve Arabic Islamic terms with transliteration and meaning:
   - "التوحيد (tawhid - monotheism)"
   - "الرحمن (Ar-Rahman - The Most Merciful)"

2. Translate hadith citations clearly, noting narrator chains

3. Maintain scholarly tone - these are academic religious texts

4. For poetry (شعر), preserve meter indication

5. Explain historical/cultural context when relevant

6. Format with clear sections for:
   - Main interpretation
   - Supporting evidence (hadith, other verses)
   - Scholarly opinions (if multiple views presented)
```

## Verification
- Test with known verses (Al-Fatiha, Ayat al-Kursi)
- Verify translation quality with sample comparisons
- Test all 24+ sources return data correctly
- Benchmark translation costs

## Ethical Considerations
- Rate limit requests (1 req/sec max)
- Cache aggressively to minimize server load
- Include attribution to tafsir.app in output
- This is for personal scholarly use only
