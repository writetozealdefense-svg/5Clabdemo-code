#!/bin/bash
# =============================================================================
# 5C Security Lab - PDF Export Script (Linux/macOS)
#
# Converts markdown documents to branded PDFs with Zeal Defense logo.
#
# Usage:
#   ./scripts/export-to-pdf.sh docs/LAB_TEST_CASES.md
#   ./scripts/export-to-pdf.sh --all
#
# Requirements:
#   sudo apt install pandoc wkhtmltopdf   # Ubuntu/Debian
#   brew install pandoc wkhtmltopdf       # macOS
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS="$PROJECT_ROOT/assets"
BUILD="$PROJECT_ROOT/build"

LOGO="$ASSETS/zeal-defense-logo.png"
CSS="$ASSETS/pdf-style.css"
TPL="$ASSETS/pdf-cover.html"

mkdir -p "$BUILD"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

command -v pandoc      >/dev/null || fail "pandoc required (sudo apt install pandoc)"
command -v wkhtmltopdf >/dev/null || fail "wkhtmltopdf required (sudo apt install wkhtmltopdf)"

[ -f "$CSS" ] || fail "Missing $CSS"
[ -f "$TPL" ] || fail "Missing $TPL"

if [ ! -f "$LOGO" ]; then
    warn "Logo not found at $LOGO"
    warn "Place zeal-defense-logo.png in assets/ for branded cover. Using placeholder SVG for now."
    LOGO_URI="data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHdpZHRoPSczMDAnIGhlaWdodD0nMTUwJyB2aWV3Qm94PScwIDAgMzAwIDE1MCc+PHJlY3Qgd2lkdGg9JzMwMCcgaGVpZ2h0PScxNTAnIGZpbGw9JyMwYTE5MjknLz48dGV4dCB4PScxNTAnIHk9JzgwJyB0ZXh0LWFuY2hvcj0nbWlkZGxlJyBmaWxsPScjMDBlNWZmJyBmb250LWZhbWlseT0nQXJpYWwnIGZvbnQtc2l6ZT0nMzInIGZvbnQtd2VpZ2h0PSdib2xkJz5aRUFMPC90ZXh0Pjx0ZXh0IHg9JzE1MCcgeT0nMTE1JyB0ZXh0LWFuY2hvcj0nbWlkZGxlJyBmaWxsPScjZmZmJyBmb250LWZhbWlseT0nQXJpYWwnIGZvbnQtc2l6ZT0nMjAnPkRFRkVOU0U8L3RleHQ+PC9zdmc+"
else
    LOGO_URI="data:image/png;base64,$(base64 -w 0 "$LOGO" 2>/dev/null || base64 "$LOGO" | tr -d '\n')"
fi

convert_one() {
    local md="$1"
    local title="${2:-$(basename "$md" .md | tr '_' ' ')}"
    local out="$BUILD/$(basename "$md" .md).pdf"

    [ -f "$PROJECT_ROOT/$md" ] || { warn "Missing $md - skipping"; return; }

    echo "[$(date +%H:%M:%S)] Converting $md -> $out"

    # Markdown -> HTML fragment
    local body_html="$BUILD/.body-$$.html"
    pandoc "$PROJECT_ROOT/$md" --from markdown --to html5 --toc --toc-depth=3 -o "$body_html"

    # Build final HTML from template
    local tmp_html="$BUILD/.tmp-$$.html"
    local css_content body_content
    css_content="$(cat "$CSS")"
    body_content="$(cat "$body_html")"

    # Use python for safe substitution (avoids sed issues with special chars)
    python3 - "$TPL" "$tmp_html" "$title" "$(basename "$md")" "$(date '+%Y-%m-%d %H:%M')" "$LOGO_URI" "$CSS" "$body_html" <<'PY'
import sys, pathlib
tpl_p, out_p, title, doc, date, logo, css_p, body_p = sys.argv[1:]
html = pathlib.Path(tpl_p).read_text(encoding='utf-8')
css  = pathlib.Path(css_p).read_text(encoding='utf-8')
body = pathlib.Path(body_p).read_text(encoding='utf-8')
html = html.replace("{{TITLE}}", title)
html = html.replace("{{DOC_NAME}}", doc)
html = html.replace("{{DATE}}", date)
html = html.replace("{{VERSION}}", "1.0")
html = html.replace("{{LOGO_URI}}", logo)
html = html.replace("{{INLINE_CSS}}", css)
html = html.replace("{{CONTENT}}", body)
pathlib.Path(out_p).write_text(html, encoding='utf-8')
PY

    wkhtmltopdf \
        --enable-local-file-access \
        --page-size A4 \
        --margin-top 20mm --margin-bottom 20mm \
        --margin-left 15mm --margin-right 15mm \
        --footer-center "Zeal Defense | [page] of [topage]" \
        --footer-font-size 8 --footer-spacing 5 \
        --encoding UTF-8 \
        "$tmp_html" "$out" 2>/dev/null

    rm -f "$tmp_html" "$body_html"

    if [ -f "$out" ]; then
        ok "Created $out ($(du -h "$out" | cut -f1))"
    else
        warn "Failed to create $out"
    fi
}

if [ "${1:-}" = "--all" ]; then
    convert_one "README.md" "Project Overview"
    convert_one "docs/SETUP_GUIDE.md" "GCP Deployment Guide"
    convert_one "docs/LAB_MANUAL.md" "Lab Manual Index"
    convert_one "docs/LAB_EXECUTION_GUIDE.md" "Master Execution Playbook"
    convert_one "docs/LAB_TEST_CASES.md" "Test Case Catalog (200+ payloads)"
else
    convert_one "${1:-docs/LAB_TEST_CASES.md}" "${2:-}"
fi

echo ""
ok "Output directory: $BUILD"
ls -lh "$BUILD"/*.pdf 2>/dev/null || warn "No PDFs produced"
