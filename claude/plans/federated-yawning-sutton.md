# Islamic Q&A Research Skill Plan

## Research Summary

### islamqa.info
- **API**: None available
- **Scraping**: Allowed per robots.txt (only `/_next/` blocked)
- **URL Patterns**:
  - Search: `https://islamqa.info/en/search?q={query}`
  - Answer: `https://islamqa.info/en/answers/{id}`
- **Tech Stack**: Next.js with React Server Components
- **Structure**: Clean HTML with Schema.org QAPage markup
- **Selectors**:
  - Question: `section.tw-bg-paperQuestion`
  - Answer: `article#single-post-content`

### seekersguidance.org
- **API**: None available
- **Direct access**: Returns 403 (bot protection)
- **Access method**: Requires browser automation or web search

---

## Implementation Plan

### Part 1: Claude Code Skill (`/islamic-qa`)

**Location**: `~/.claude/skills/islamic-qa/SKILL.md`

**Workflow**:
1. User invokes `/islamic-qa <question>`
2. Skill uses WebSearch to find relevant answers from both sites
3. For islamqa.info results: Use WebFetch to extract full answer
4. For seekersguidance.org results: Use Playwright MCP to navigate and extract
5. Synthesize findings and provide answer with citations

**SKILL.md structure**:
```markdown
---
trigger: /islamic-qa
description: Search Islamic Q&A resources for answers
---

# Islamic Q&A Research Skill

When the user asks an Islamic question...
[Instructions for Claude to search and extract]
```

### Part 2: Standalone Python Script (`islamic_qa.py`)

**Location**: `/Users/moose/Downloads/projects/test/islamic_qa.py`

**Features**:
- CLI interface: `python islamic_qa.py "What is the ruling on..."`
- Search both sites
- Extract and display answers
- Cache results locally (optional)

**Dependencies**:
- `requests` - HTTP client
- `beautifulsoup4` - HTML parsing
- `rich` - Terminal output formatting
- `playwright` - Browser automation for seekersguidance.org

**Structure**:
```python
islamic_qa.py
├── IslamQAClient      # Scraper for islamqa.info
├── SeekersClient      # Browser automation for seekersguidance.org
├── search()           # Search both sources
├── get_answer()       # Extract full answer by URL
└── main()             # CLI entrypoint
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `~/.claude/skills/islamic-qa/SKILL.md` | Claude Code skill definition |
| `./islamic_qa.py` | Standalone Python script |
| `./requirements.txt` | Python dependencies |

## Implementation Steps

1. **Create the Claude Code skill**
   - Write SKILL.md with search/extraction instructions
   - Test with sample questions

2. **Create the Python script**
   - Implement `IslamQAClient` class for islamqa.info
   - Implement `SeekersClient` class with Playwright for seekersguidance.org
   - Add CLI interface with argparse
   - Add rich terminal output

3. **Test both implementations**
   - Test with various Islamic questions
   - Verify extraction accuracy
   - Handle edge cases (no results, timeouts, etc.)
