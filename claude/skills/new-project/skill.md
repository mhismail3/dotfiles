# New Project Portfolio Entry and Blog Post

Creates a complete portfolio project entry and accompanying blog post for a new project, following the established architecture and styling patterns.

## Overview

This skill automates the process of documenting a new project by:
1. Fetching project information from GitHub (if applicable)
2. Creating a portfolio project entry with proper frontmatter and markdown
3. Creating an accompanying blog post with narrative context
4. Ensuring full markdown styling parity (CodeBlocks, blockquotes, links, etc.)

## Usage

```bash
# Basic usage with GitHub repo
/new-project https://github.com/username/repo-name

# With additional context
/new-project https://github.com/username/repo-name --context "This project extends my previous work on X by adding Y"

# For non-GitHub projects
/new-project --title "Project Name" --summary "Brief description" --tags "tag1,tag2,tag3"
```

## Arguments

- **GitHub URL** (optional): Repository URL to fetch information from
- `--title`: Project title (fetched from repo if not provided)
- `--summary`: Brief project description for the portfolio card
- `--context`: Additional context for the blog post narrative
- `--tags`: Comma-separated list of technology tags
- `--status`: Project status (default: "🔄 Active")
- `--live`: Live demo URL if applicable
- `--date`: Publication date (default: today)

## Process

### 1. Information Gathering

- If GitHub URL provided:
  - Fetch repository description, topics, primary language
  - Check for README.md for additional context
  - Extract relevant technical details
- Prompt user for any missing required information:
  - Project summary (if not from GitHub)
  - Key technologies/tags
  - Status indicator
  - Live demo URL (if applicable)

### 2. Portfolio Project Entry Creation

**Location**: `public/projects/{slug}/project.md`

**Frontmatter Structure**:
```yaml
---
title: Project Name
slug: project-slug
date: YYYY-MM-DD
summary: Brief description for portfolio card
github: https://github.com/username/repo
live: https://demo-url.com (optional)
tags:
  - Technology 1
  - Technology 2
  - Technology 3
status: "🔄 Active"
cover: cover.png
gallery:
  - gallery-1.png
  - gallery-2.png
---
```

**Content Guidelines**:
- Start with the problem/motivation (personal pain point or learning goal)
- Explain the solution approach
- Use section headings (###) for major topics:
  - Architecture/Design
  - Key Features/Tools
  - Technical Details
  - Deployment/Distribution (if applicable)
- Include code examples with proper language tags:
  ```bash
  # Example commands
  ```
  ```javascript
  // Example code
  ```
- Link to related projects using internal links: `[Project Name](/portfolio/project-slug/)`
- Keep it technical but accessible
- Write in first person, conversational tone

### 3. Blog Post Creation

**Location**: `public/posts/{date}-{slug}/post.md`

**Frontmatter Structure**:
```yaml
---
title: "Descriptive Blog Post Title"
date: "YYYY-MM-DDTHH:MM:SS-08:00"
tags:
  - tag-1
  - tag-2
  - tag-3
---
```

**Content Guidelines**:
- Narrative style explaining the journey/evolution
- Connect to previous work or learning experiences
- Explain the "why" behind decisions
- Use section headings (###) for flow:
  - Context/Motivation
  - Approach/Philosophy
  - Implementation Details
  - Results/Learnings
- Include code examples matching the portfolio entry
- Link to:
  - Related projects: `[Project Name](/portfolio/project-slug/)`
  - Live demos: `[Demo](https://url.com)`
  - GitHub repo: `[repo-name](https://github.com/...)`
- End with reflection or future direction

### 4. Markdown Styling Verification

Ensure the following elements work correctly on both project and post pages:

**CodeBlock Components**:
- Verify code blocks are extracted and rendered with syntax highlighting
- Check copy and wrap buttons function properly
- Confirm proper spacing and shadow styling

**Blockquotes**:
- Test simple blockquotes with `>`
- Test attributed quotes if needed (with `.attributed-quote` class)
- Verify hover effects on desktop

**Inline Elements**:
- Links with underline hover effects
- Inline `code` styling with proper background and borders
- Lists (ul/ol) with correct spacing

**Structural Elements**:
- Headings (h2, h3) with proper hierarchy
- Paragraphs with comfortable line-height
- Horizontal rules (---) with diamond ornament

### 5. Asset Preparation

**Required Images**:
- `cover.png`: Main project thumbnail (used in portfolio grid)
- `gallery-1.png`, `gallery-2.png`, etc.: Screenshots for carousel

**Dimensions**:
- Cover: Optimized for portfolio card display
- Gallery: Full-width screenshots showing key features

**Location**: `public/projects/{slug}/`

### 6. Verification Steps

1. **Portfolio Page**:
   - Navigate to `/portfolio/{slug}`
   - Verify project header with title and links
   - Check all markdown elements render correctly
   - Test code blocks (syntax highlighting, copy/wrap buttons)
   - Verify carousel displays gallery images
   - Test lightbox functionality

2. **Blog Post**:
   - Navigate to `/posts/{date}-{slug}`
   - Verify post header and metadata
   - Check all markdown elements match project page styling
   - Verify internal links navigate correctly
   - Test code blocks function identically to project page

3. **Portfolio Grid**:
   - Navigate to `/portfolio`
   - Verify new project card appears
   - Check cover image displays correctly
   - Verify summary text is appropriate length
   - Test hover effects and navigation

4. **Blog Archive**:
   - Navigate to `/blog`
   - Verify new post appears in chronological order
   - Check post preview and metadata

## Technical Implementation Notes

### CodeBlock Integration

Both project and post pages must extract code blocks before parsing markdown:

**In `portfolioProjects.js` / `blogPosts.js`**:
```javascript
const extractCodeBlocks = (markdown) => {
  const codeBlocks = [];
  const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;

  const processedContent = markdown.replace(codeBlockRegex, (match, language, code) => {
    const index = codeBlocks.length;
    const lang = language || 'text';
    const trimmedCode = code.trim();

    codeBlocks.push({
      language: lang,
      code: trimmedCode,
    });

    return `<div data-codeblock="${index}" data-language="${lang}" data-code="${encodeURIComponent(trimmedCode)}"></div>`;
  });

  return { processedContent, codeBlocks };
};
```

**In React Components**:
```javascript
const ProjectContent = ({ html, codeBlocks }) => {
  // Parse HTML and replace placeholders with CodeBlock components
  const contentParts = useMemo(() => {
    // ... parsing logic to find data-codeblock attributes
    // Return array of {type: 'codeblock'|'html', ...} objects
  }, [html, codeBlocks]);

  return (
    <div className="project-description">
      {contentParts.map((part) =>
        part.type === 'codeblock'
          ? <CodeBlock key={part.key} code={part.code} language={part.language} />
          : <div key={part.key} dangerouslySetInnerHTML={{__html: part.content}} />
      )}
    </div>
  );
};
```

### CSS Styling Parity

Both `project.css` and `post.css` must include:

**CodeBlock Overrides**:
```css
.project-description .code-block {
  margin: 1rem 0 1.5rem 0;
}

.project-description .code-block pre {
  background: transparent;
  color: var(--ink);
  border: none;
  box-shadow: none;
  padding: var(--space-xl);
  border-radius: 0;
}
```

**Wrapper Transparency**:
```css
/* Make React wrapper divs transparent, except CodeBlock components */
.project-description > div:not(.code-block) {
  display: contents;
}
```

**All Markdown Elements**:
- Blockquotes (simple and attributed)
- Inline code
- Links with hover states
- Headings (h2, h3)
- Lists (ul, ol)
- Horizontal rules
- Paragraphs

## Example Output

After running this skill, you should have:

1. **Portfolio Project**: `public/projects/example-project/project.md`
2. **Blog Post**: `public/posts/2025-12-19-example-project/post.md`
3. **Assets**: `public/projects/example-project/{cover.png, gallery-*.png}`

Both files should be ready for commit with proper markdown, frontmatter, and styling support.

## Common Issues and Solutions

### Code Blocks Not Rendering
- **Symptom**: Code appears as plain text without syntax highlighting
- **Cause**: Code blocks not extracted before markdown parsing
- **Solution**: Ensure `extractCodeBlocks()` runs before `marked.parse()`

### No Styling on Project/Post Page
- **Symptom**: Plain unstyled text with no spacing or colors
- **Cause**: React wrapper divs blocking CSS cascade
- **Solution**: Add `.project-description > div:not(.code-block) { display: contents; }`

### CodeBlock Shadow Missing
- **Symptom**: Code blocks render but look different from other pages
- **Cause**: Missing CodeBlock-specific CSS overrides
- **Solution**: Add `.project-description .code-block` and `.code-block pre` rules

### Copy Button Not Visible
- **Symptom**: Code blocks have no copy/wrap buttons
- **Cause**: CodeBlock component not being rendered
- **Solution**: Verify ProjectContent/PostContent component properly extracts and renders CodeBlock components

## Post-Creation Checklist

- [ ] Portfolio project file created with complete frontmatter
- [ ] Blog post file created with narrative content
- [ ] Cover image and gallery images added
- [ ] All markdown elements render correctly (check both pages)
- [ ] Code blocks have syntax highlighting and working buttons
- [ ] Internal links navigate properly
- [ ] Project appears in portfolio grid
- [ ] Post appears in blog archive
- [ ] Git commit created with descriptive message
- [ ] Changes pushed to remote repository

## Related Documentation

- Architecture patterns: See existing projects in `public/projects/`
- Styling reference: `src/styles/pages/project.css` and `src/styles/pages/post.css`
- Component structure: `src/pages/ProjectPage.jsx` and `src/pages/PostPage.jsx`
- Data loading: `src/data/portfolioProjects.js` and `src/data/blogPosts.js`
