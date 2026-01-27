# Plan: Add Image/File Attachment Support to OpenAI and Gemini Providers

## Summary

Add robust support for images, PDFs, and text-based files to the OpenAI and Gemini providers. Currently, both providers silently drop non-text content.

**Supported file types:**
- **Images**: jpeg, png, gif, webp (+ heic/heif/bmp/tiff for some providers)
- **PDFs**: application/pdf
- **Text files**: .txt, .md, .json, .csv, .html, .xml, .yaml (decoded and sent as text)
- **Office docs**: .docx, .xlsx, .pptx - warn and skip (no new dependencies)

---

## Part 1: Text File Support in Attachments

**File**: `packages/agent/src/rpc/attachments.ts`

### 1.1 Add Text Content Block Type

```typescript
export interface TextContentBlock {
  type: 'text';
  text: string;
}

export type ContentBlock = ImageContentBlock | DocumentContentBlock | TextContentBlock;
```

### 1.2 Add Supported Text Types

```typescript
const SUPPORTED_TEXT_TYPES = new Set([
  'text/plain',
  'text/markdown',
  'text/csv',
  'text/html',
  'text/xml',
  'application/json',
  'application/xml',
  'text/yaml',
  'application/x-yaml',
]);

function isTextType(mimeType: string): boolean {
  return SUPPORTED_TEXT_TYPES.has(mimeType);
}
```

### 1.3 Update `isSupportedType` and Conversion Logic

```typescript
function isSupportedType(mimeType: string): boolean {
  return isImageType(mimeType) || isDocumentType(mimeType) || isTextType(mimeType);
}
```

In the conversion loop, add:
```typescript
} else if (isTextType(mimeType)) {
  // Decode base64 text content
  const text = Buffer.from(data, 'base64').toString('utf-8');
  contentBlocks.push({
    type: 'text',
    text: fileName ? `[File: ${fileName}]\n${text}` : text,
  });
}
```

### 1.4 Add Warning for Unsupported Types

```typescript
import { logger } from '../utils/logger';

// In the loop, before `continue`:
if (!isSupportedType(mimeType)) {
  logger.warn('Skipping unsupported attachment type', { mimeType, fileName });
  continue;
}
```

---

## Part 2: OpenAI Provider Updates

**File**: `packages/agent/src/providers/openai.ts`

### 2.1 Add Type Definitions (after line ~62)

```typescript
type OpenAIContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string; detail?: 'auto' | 'low' | 'high' } };
```

### 2.2 Add Helper Method (before `convertMessages`)

```typescript
private convertUserContentToOpenAI(
  content: (TextContent | ImageContent | DocumentContent)[]
): string | OpenAIContentPart[] {
  const parts: OpenAIContentPart[] = [];

  for (const c of content) {
    if (c.type === 'text') {
      parts.push({ type: 'text', text: c.text });
    } else if (c.type === 'image') {
      // OpenAI expects data URI format
      parts.push({
        type: 'image_url',
        image_url: { url: `data:${c.mimeType};base64,${c.data}`, detail: 'auto' }
      });
    } else if (c.type === 'document' && c.mimeType === 'application/pdf') {
      // OpenAI supports PDFs via same image_url format
      parts.push({
        type: 'image_url',
        image_url: { url: `data:${c.mimeType};base64,${c.data}` }
      });
    } else {
      logger.warn('Unsupported content type for OpenAI', { type: c.type, mimeType: (c as any).mimeType });
    }
  }

  // Optimize: use string for text-only messages (better compatibility)
  if (parts.length > 0 && parts.every(p => p.type === 'text')) {
    return parts.map(p => (p as { type: 'text'; text: string }).text).join('\n');
  }
  return parts.length > 0 ? parts : '';
}
```

### 2.3 Update User Message Conversion (lines 574-587)

Replace:
```typescript
if (msg.role === 'user') {
  const content = typeof msg.content === 'string'
    ? msg.content
    : msg.content
        .filter(c => c.type === 'text')
        .map(c => (c as TextContent).text)
        .join('\n');
  if (content) {
    messages.push({ role: 'user', content });
  }
}
```

With:
```typescript
if (msg.role === 'user') {
  const content = typeof msg.content === 'string'
    ? msg.content
    : this.convertUserContentToOpenAI(msg.content);

  if (content && (typeof content === 'string' ? content.length > 0 : content.length > 0)) {
    messages.push({ role: 'user', content });
  }
}
```

### 2.4 Update Tool Result Handling (lines 610-622)

Add warning for dropped image content:
```typescript
} else if (msg.role === 'toolResult') {
  let content: string;
  if (typeof msg.content === 'string') {
    content = msg.content;
  } else {
    const textParts: string[] = [];
    for (const c of msg.content) {
      if (c.type === 'text') {
        textParts.push(c.text);
      } else {
        logger.warn('OpenAI tool results only support text, dropping content', { type: c.type });
      }
    }
    content = textParts.join('\n');
  }
  messages.push({ role: 'tool', tool_call_id: idMapping.get(msg.toolCallId) ?? msg.toolCallId, content });
}
```

---

## Part 3: Gemini Provider Updates

**File**: `packages/agent/src/providers/google.ts`

### 3.1 Update GeminiPart Type (lines 148-151)

Add `inlineData` variant:
```typescript
type GeminiPart =
  | { text: string; thought?: boolean; thoughtSignature?: string }
  | { functionCall: { name: string; args: Record<string, unknown> }; thoughtSignature?: string }
  | { functionResponse: { name: string; response: Record<string, unknown> } }
  | { inlineData: { mimeType: string; data: string } };
```

### 3.2 Update User Message Conversion (lines 1064-1070)

Replace:
```typescript
for (const c of msg.content) {
  if (c.type === 'text') {
    parts.push({ text: c.text });
  }
  // Note: Image handling would go here for multimodal
}
```

With:
```typescript
for (const c of msg.content) {
  if (c.type === 'text') {
    parts.push({ text: c.text });
  } else if (c.type === 'image') {
    parts.push({ inlineData: { mimeType: c.mimeType, data: c.data } });
  } else if (c.type === 'document' && c.mimeType === 'application/pdf') {
    parts.push({ inlineData: { mimeType: c.mimeType, data: c.data } });
  } else {
    logger.warn('Unsupported content type for Gemini', { type: c.type, mimeType: (c as any).mimeType });
  }
}
```

### 3.3 Update Tool Result Handling (lines 1097-1103)

Add warning for dropped content:
```typescript
} else if (msg.role === 'toolResult') {
  const textParts: string[] = [];
  if (typeof msg.content === 'string') {
    textParts.push(msg.content);
  } else {
    for (const c of msg.content) {
      if (c.type === 'text') {
        textParts.push(c.text);
      } else {
        logger.warn('Gemini function responses only support text, dropping content', { type: c.type });
      }
    }
  }
  contents.push({
    role: 'user',
    parts: [{
      functionResponse: {
        name: 'tool_result',
        response: { result: textParts.join('\n'), tool_call_id: idMapping.get(msg.toolCallId) ?? msg.toolCallId }
      }
    }]
  });
}
```

---

## Part 4: Tests

### New Test Files

| File | Purpose |
|------|---------|
| `packages/agent/src/rpc/__tests__/attachments.test.ts` | Update existing tests for text files |
| `packages/agent/src/providers/__tests__/openai-multimodal.test.ts` | New: OpenAI image/PDF handling |
| `packages/agent/src/providers/__tests__/google-multimodal.test.ts` | New: Gemini image/PDF handling |

### Test Categories

**Attachment Tests:**
- Text file (.txt) decoding from base64
- Markdown file with filename prefix
- JSON file handling
- Unsupported type warning (e.g., .docx)

**OpenAI Tests:**
- Text-only content uses string format
- Mixed text + image uses array format
- Image to data URI conversion
- PDF to data URI conversion
- Unsupported content warning

**Gemini Tests:**
- Text content to text part
- Image to inlineData
- PDF to inlineData
- Mixed content messages
- Unsupported content warning

---

## Files to Modify

| File | Changes |
|------|---------|
| `packages/agent/src/rpc/attachments.ts` | Add text file support, warnings |
| `packages/agent/src/providers/openai.ts` | Add types, helper method, update conversions |
| `packages/agent/src/providers/google.ts` | Update GeminiPart type, update conversions |
| `packages/agent/src/rpc/__tests__/attachments.test.ts` | Add text file tests |
| `packages/agent/src/providers/__tests__/openai-multimodal.test.ts` | New test file |
| `packages/agent/src/providers/__tests__/google-multimodal.test.ts` | New test file |

---

## Verification

1. **Build**: `bun run build`
2. **Run all tests**: `bun run test`
3. **Manual testing**:
   - Attach a .png image and verify it displays in OpenAI/Gemini responses
   - Attach a .pdf and verify it's processed
   - Attach a .txt file and verify content appears as text
   - Attach a .docx and verify warning is logged
