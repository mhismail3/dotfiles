#!/usr/bin/env python3
"""
Mistral OCR CLI Tool

Extract text from images using Mistral's OCR API.

Usage:
    python ocr.py <image-path>
    python ocr.py <image-path> --copy     # Also copy to clipboard
    python ocr.py <image-path> -o out.txt # Save to file

Environment:
    MISTRAL_API_KEY - Your Mistral API key (required)
"""

import sys
import os
import base64
import json
import subprocess
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

API_ENDPOINT = "https://api.mistral.ai/v1/ocr"
MODEL_ID = "mistral-ocr-latest"

SUPPORTED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".avif"}
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB

MIME_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".avif": "image/avif",
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def print_usage():
    print("""
Mistral OCR - Extract text from images

Usage:
    python ocr.py <image-path> [options]

Options:
    --copy, -c      Copy extracted text to clipboard
    -o <file>       Save output to file
    --help, -h      Show this help message

Environment:
    MISTRAL_API_KEY  Your Mistral API key (required)
                     Get one at: https://console.mistral.ai/api-keys

Examples:
    python ocr.py photo.jpg
    python ocr.py screenshot.png --copy
    python ocr.py document.jpg -o output.txt
    MISTRAL_API_KEY=xxx python ocr.py image.png
""")


def get_mime_type(file_path: Path) -> str:
    return MIME_TYPES.get(file_path.suffix.lower(), "image/jpeg")


def encode_image_to_base64(file_path: Path) -> str:
    with open(file_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def copy_to_clipboard(text: str) -> bool:
    try:
        if sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=text.encode(), check=True)
            return True
        elif sys.platform.startswith("linux"):
            subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode(), check=True)
            return True
        elif sys.platform == "win32":
            subprocess.run(["clip"], input=text.encode(), check=True)
            return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return False


# ═══════════════════════════════════════════════════════════════════════════════
# API CALL
# ═══════════════════════════════════════════════════════════════════════════════

def call_mistral_ocr(api_key: str, image_data_url: str) -> dict:
    request_body = json.dumps({
        "model": MODEL_ID,
        "document": {
            "type": "image_url",
            "image_url": {
                "url": image_data_url
            }
        }
    }).encode("utf-8")

    req = Request(
        API_ENDPOINT,
        data=request_body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST"
    )

    try:
        with urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as e:
        error_body = e.read().decode("utf-8")
        error_msg = f"API request failed with status {e.code}"

        try:
            error_json = json.loads(error_body)
            error_msg = (
                error_json.get("message") or
                error_json.get("detail") or
                error_json.get("error", {}).get("message") or
                error_msg
            )
        except json.JSONDecodeError:
            pass

        if e.code == 401:
            error_msg = "Invalid API key. Please check your MISTRAL_API_KEY."
        elif e.code == 403:
            error_msg = "API key does not have permission for OCR. Check your Mistral account."
        elif e.code == 429:
            error_msg = "Rate limit exceeded. Please wait and try again."

        raise RuntimeError(error_msg)
    except URLError as e:
        raise RuntimeError(f"Network error: {e.reason}")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print_usage()
        sys.exit(0 if args else 1)

    # Parse arguments
    image_path = None
    copy_to_clip = False
    output_file = None

    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("--copy", "-c"):
            copy_to_clip = True
        elif arg == "-o" and i + 1 < len(args):
            i += 1
            output_file = args[i]
        elif not arg.startswith("-"):
            image_path = arg
        i += 1

    if not image_path:
        print("Error: No image path provided", file=sys.stderr)
        print_usage()
        sys.exit(1)

    # Check API key
    api_key = os.environ.get("MISTRAL_API_KEY")
    if not api_key:
        print("Error: MISTRAL_API_KEY environment variable is not set", file=sys.stderr)
        print("Get your API key at: https://console.mistral.ai/api-keys", file=sys.stderr)
        print("\nUsage: MISTRAL_API_KEY=your-key python ocr.py <image>", file=sys.stderr)
        sys.exit(1)

    # Resolve and validate image path
    resolved_path = Path(image_path).resolve()

    if not resolved_path.exists():
        print(f"Error: File not found: {resolved_path}", file=sys.stderr)
        sys.exit(1)

    file_size = resolved_path.stat().st_size
    if file_size > MAX_FILE_SIZE:
        print(f"Error: File too large ({file_size / 1024 / 1024:.1f}MB). Maximum is 50MB.", file=sys.stderr)
        sys.exit(1)

    ext = resolved_path.suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        print(f"Error: Unsupported file type: {ext}", file=sys.stderr)
        print(f"Supported types: {', '.join(SUPPORTED_EXTENSIONS)}", file=sys.stderr)
        sys.exit(1)

    # Process image
    print(f"Processing: {resolved_path.name} ({file_size / 1024:.1f} KB)", file=sys.stderr)

    try:
        # Encode image
        base64_data = encode_image_to_base64(resolved_path)
        mime_type = get_mime_type(resolved_path)
        data_url = f"data:{mime_type};base64,{base64_data}"

        # Call API
        print("Calling Mistral OCR API...", file=sys.stderr)
        response = call_mistral_ocr(api_key, data_url)

        # Extract text from response
        pages = response.get("pages", [])
        if not pages:
            print("No text found in image.", file=sys.stderr)
            sys.exit(0)

        extracted_text = "\n\n---\n\n".join(
            page.get("markdown", "").strip()
            for page in sorted(pages, key=lambda p: p.get("index", 0))
            if page.get("markdown", "").strip()
        )

        if not extracted_text.strip():
            print("No text found in image.", file=sys.stderr)
            sys.exit(0)

        # Output
        print(extracted_text)

        # Copy to clipboard if requested
        if copy_to_clip:
            if copy_to_clipboard(extracted_text):
                print("\n✓ Copied to clipboard", file=sys.stderr)
            else:
                print("\n✗ Failed to copy to clipboard", file=sys.stderr)

        # Save to file if requested
        if output_file:
            Path(output_file).write_text(extracted_text, encoding="utf-8")
            print(f"\n✓ Saved to {output_file}", file=sys.stderr)

    except RuntimeError as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
