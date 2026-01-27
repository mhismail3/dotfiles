# Blog Post Plan: Tron Agent Journey

## Post Metadata
- **Title**: "From Claude Code Wrappers to Building My Own Agent"
- **Date**: `2026-01-21T16:50:00-08:00` (January 21st, 4:50pm Pacific)
- **Type**: long
- **Tags**: `[ai, agents, ios, swift, typescript, claude code]`
- **Location**: `/public/posts/2026-01-21-from-claude-code-wrappers-to-building-my-own-agent/post.md`

## Connection to Previous Posts
- This continues the narrative from the Dec 20th "Claude Moose" post
- Reference that earlier experiment as the starting point
- Show the evolution: Telegram/Discord wrapper → Agent SDK attempt → building from scratch

## Narrative Arc

### 1. Opening Hook (2-3 sentences)
Callback to the December experiment - the desire for mobile Claude Code access led somewhere unexpected: building a complete agent from scratch.

### 2. What Went Wrong with Wrappers (1 paragraph)
- Reference Claude Moose attempt (Telegram, Discord, Agent SDK)
- Core problem: couldn't achieve feature parity by reverse engineering
- Terminal output parsing was fundamentally fragile
- Realized the answer was to own the entire stack

### 3. The Decision to Build From Scratch (1 paragraph)
- Instead of wrapping Claude Code, build around the models directly
- Full control over architecture, no reverse engineering constraints
- Named it Tron

---

### 4. The Architecture (2-3 paragraphs with horizontal rule separator)

**Server (Mac mini)**:
- Always-on WebSocket server
- Event-sourced sessions (every action is an immutable event)
- Handles agent loops, tool execution, memory

**iOS App (primary client)**:
- Native SwiftUI for iOS 18+
- Real-time streaming from server
- Session management with fork/rewind
- Image attachments, voice transcription
- Designed with attention to polish and edge cases

### 5. The Thesis: Vibe Coding to 99% (1-2 paragraphs)
- Main message: vibe coding isn't just for prototypes
- With persistence, you can push from 85% to 99%
- Examples: event sourcing for crash safety, four-level memory, multi-model switching
- It's about iterating on the details

### 6. Closing (1-2 sentences)
- Link to GitHub repo
- Brief forward-looking note

## Style Guidelines (Based on Existing Posts)

- **Tone**: Conversational first-person ("I wanted", "I ran into", "I realized")
- **Structure**: Problem → attempt → pivot → solution (consistent with your other posts)
- **Length**: ~35-50 lines (similar to the Claude Moose post)
- **Section breaks**: Use `---` horizontal rules to separate major sections
- **Technical details**: Brief, accessible - no jargon overload
- **Lists**: Use bullet points to break up technical content
- **Links**: Inline links for references, GitHub repo link at the end
- **No excessive praise**: Matter-of-fact about what works and what didn't
- **Callbacks**: Reference the December Claude Moose post for continuity

## Key Content from Tron Repo to Highlight

1. **Event-sourced persistence**: Every action is an immutable event forming a tree (can fork/rewind)
2. **Four-level memory**: immediate → session → project → global
3. **WebSocket server**: Real-time streaming from server to any client
4. **iOS app polish**:
   - Real-time tool visualization
   - Thinking indicators
   - Session management with fork/rewind
   - Offline-first local database
5. **Multi-model support**: Switch between providers mid-session

## Files to Create
- `/public/posts/2026-01-21-from-claude-code-wrappers-to-building-my-own-agent/post.md`

## Verification
1. View the blog post in browser (dev server or via `dev-browser` skill)
2. Confirm post appears at top of posts list (newest date)
3. Verify GitHub link works
