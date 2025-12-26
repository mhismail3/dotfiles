# Islamic Q&A Research Skill

Research and answer Islamic questions using authoritative scholarly sources.

## Sources

This skill searches two authoritative Islamic Q&A websites:
1. **islamqa.info** - Extensive database of Islamic rulings and answers
2. **seekersguidance.org** - Answers from qualified Islamic scholars

## Workflow

When the user asks an Islamic question:

### Step 1: Search for Relevant Answers

Use WebSearch to find relevant Q&A from both sites:

```
WebSearch: site:islamqa.info OR site:seekersguidance.org {user's question}
```

### Step 2: Extract Full Answers

For promising results from **islamqa.info**:
- Use WebFetch to retrieve the full answer page
- The URL pattern is: `https://islamqa.info/en/answers/{id}`
- Extract the question from `section.tw-bg-paperQuestion`
- Extract the answer from `article#single-post-content`

For results from **seekersguidance.org**:
- Use Playwright MCP tools (browser automation) since direct fetch returns 403
- Navigate to the answer URL
- Use `mcp__plugin_playwright_playwright__browser_snapshot` to capture content
- Extract the relevant Q&A content

### Step 3: Synthesize and Present

Present findings in this format:

```
## Answer Summary
[Concise synthesis of the scholarly answers found]

## Sources Consulted

### From IslamQA.info
- [Title](URL) - Brief excerpt

### From SeekersGuidance
- [Title](URL) - Brief excerpt

## Key Points
- Point 1
- Point 2
- Point 3

## Note
This answer is based on scholarly opinions from the sources above.
For personal rulings, consult a qualified local scholar.
```

## Important Guidelines

1. **Always cite sources** - Provide links to the original answers
2. **Present multiple perspectives** - If scholars differ, present the range of opinions
3. **Be accurate** - Only present what the sources actually say
4. **Respect copyright** - Summarize rather than copy large sections verbatim
5. **Acknowledge limitations** - If no relevant answers are found, say so clearly

## Example Usage

User: "What is the ruling on combining prayers while traveling?"

Response should:
1. Search both sites for relevant answers
2. Extract the scholarly rulings
3. Present a clear summary with citations
4. Note any differences in scholarly opinion

## Fallback Behavior

If direct access to seekersguidance.org fails:
- Rely on web search results which may include cached/indexed content
- Focus on islamqa.info results which are directly accessible
- Inform the user if one source was unavailable
