---
name: mistral-ocr
description: Extract and transcribe text from images using Mistral's OCR API. Use when the user provides an image and wants to extract text, transcribe content, read text from screenshots, photos of documents, receipts, or any image containing text.
---

# Mistral OCR - Image Text Extraction

Extract text from images using Mistral's powerful OCR API.

## Requirements

- Environment variable `MISTRAL_API_KEY` must be set
- Python 3.6+
- No external packages required (uses standard library only)

## Instructions

When the user provides an image path and wants to extract text:

1. First, verify the image file exists using the Read tool
2. Run the OCR script with the image path:

```bash
python ~/.claude/skills/mistral-ocr/scripts/ocr.py "<image-path>"
```

3. The extracted text will be output to stdout
4. Present the extracted text to the user

## Options

```bash
# Basic usage - extract text
python ~/.claude/skills/mistral-ocr/scripts/ocr.py image.jpg

# Copy result to clipboard
python ~/.claude/skills/mistral-ocr/scripts/ocr.py image.jpg --copy

# Save to file
python ~/.claude/skills/mistral-ocr/scripts/ocr.py image.jpg -o output.txt
```

## Supported Formats

- PNG (.png)
- JPEG (.jpg, .jpeg)
- WebP (.webp)
- AVIF (.avif)
- Maximum file size: 50MB

## Example Usage

User: "Extract text from this screenshot: /path/to/screenshot.png"

Response:
```bash
python ~/.claude/skills/mistral-ocr/scripts/ocr.py "/path/to/screenshot.png"
```

Then present the extracted text to the user.

## Error Handling

- If `MISTRAL_API_KEY` is not set, inform the user to set it
- If the file doesn't exist, report the error
- If the file type is unsupported, list supported formats
- If the API returns an error, report the specific error message

## Notes

- The script outputs status messages to stderr and extracted text to stdout
- Text is returned in markdown format, preserving structure like tables
- For multi-page documents, pages are separated by `---`
