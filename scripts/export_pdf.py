#!/usr/bin/env python3
"""
5C Security Lab - PDF Export (pure Python, no external binaries)

Uses markdown-pdf (pip install markdown-pdf) which is based on PyMuPDF.
Generates Zeal Defense branded PDFs with cover page, TOC, and styled content.

Usage:
    python scripts/export_pdf.py                         # exports all 5 key docs
    python scripts/export_pdf.py docs/LAB_TEST_CASES.md  # single file
"""

import base64
import datetime
import os
import sys
from pathlib import Path

try:
    from markdown_pdf import MarkdownPdf, Section
except ImportError:
    print("[ERROR] markdown-pdf not installed. Run: pip install --user markdown-pdf")
    sys.exit(1)


ROOT   = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
BUILD  = ROOT / "build"
BUILD.mkdir(exist_ok=True)

LOGO_PNG = ASSETS / "zeal-defense-logo.png"
LOGO_SVG = ASSETS / "zeal-defense-logo.svg"


# -----------------------------------------------------------------------------
# Branded CSS (Zeal Defense colors: navy #0a1929 + cyan #00e5ff)
# -----------------------------------------------------------------------------
CSS = """
@page {
    size: A4;
    margin: 22mm 18mm 25mm 18mm;
}

body {
    font-family: 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
    font-size: 10pt;
    line-height: 1.6;
    color: #1a1a1a;
}

/* --- HEADINGS WITH PAGE BREAKS --- */
h1, h2, h3, h4, h5 {
    color: #0a1929;
    page-break-after: avoid;
}

h1 {
    font-size: 20pt;
    color: #00838f;
    font-weight: 700;
    padding-bottom: 12pt;
    padding-top: 24pt;
    margin-top: 0;
    margin-bottom: 24pt;
    page-break-before: always;
    border: 0;
    background: #ffffff;
    display: block;
    width: 100%;
}

/* Don't page-break before the very first heading */
h1:first-of-type,
body > h1:first-child {
    page-break-before: auto;
}


h2 {
    font-size: 15pt;
    padding-bottom: 0;
    margin-top: 40pt;
    padding-top: 0;
    margin-bottom: 14pt;
    color: #00838f;
    font-weight: 700;
    page-break-after: avoid;
    page-break-before: auto;
}


h3 {
    font-size: 12pt;
    margin-top: 36pt;
    padding-top: 0;
    margin-bottom: 10pt;
    page-break-after: avoid;
}

h4 {
    font-size: 10.5pt;
    color: #555;
    margin-top: 16pt;
    margin-bottom: 6pt;
}

/* --- PARAGRAPHS AND LISTS --- */
p {
    margin: 6pt 0 10pt 0;
    orphans: 3;
    widows: 3;
}

li {
    margin: 3pt 0;
    orphans: 2;
    widows: 2;
}

ul, ol {
    margin-bottom: 12pt;
}

/* --- INLINE CODE --- */
code {
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 8.5pt;
    background: #eef2f6;
    color: #0a1929;
    padding: 1pt 4pt;
    border: none;
    border-radius: 2pt;
}

/* --- CODE BLOCKS --- */
pre {
    background: #0a1929;
    color: #e2e8f0;
    padding: 12pt 14pt;
    border-left: 3pt solid #00e5ff;
    border-radius: 4pt;
    font-size: 8pt;
    line-height: 1.5;
    white-space: pre-wrap;
    word-wrap: break-word;
    page-break-inside: avoid;
    margin-top: 8pt;
    margin-bottom: 32pt;
    clear: both;
}

pre code {
    background: transparent;
    border: none;
    color: #e2e8f0;
    padding: 0;
    font-size: 8pt;
}

/* --- TABLES: zero borders, clean zebra stripes --- */
table {
    border-collapse: collapse !important;
    border: 0 !important;
    border-spacing: 0 !important;
    width: 100%;
    margin-top: 10pt;
    margin-bottom: 22pt;
    font-size: 8.5pt;
    page-break-inside: avoid;
    background: transparent;
}

thead { background: transparent !important; }
tbody { background: transparent !important; }

thead tr, tbody tr, tr {
    border: 0 !important;
    border-top: 0 !important;
    border-bottom: 0 !important;
    border-left: 0 !important;
    border-right: 0 !important;
    outline: 0 !important;
    box-shadow: none !important;
}

th {
    background: #eef2f6;
    color: #0a1929;
    text-align: left;
    padding: 8pt 10pt;
    font-weight: 700;
    font-size: 8pt;
    letter-spacing: 0.3pt;
    border: 0 !important;
    border-bottom: 0 !important;
}

td {
    padding: 7pt 10pt;
    border: 0 !important;
    border-top: 0 !important;
    border-bottom: 0 !important;
    border-left: 0 !important;
    border-right: 0 !important;
    vertical-align: top;
    background: white;
}

tr:nth-child(even) td { background: #f8fafc; }

/* Emphasis on the last row of summary tables (Total row) */
tbody tr:last-child td {
    font-weight: 700;
    color: #0a1929;
    background: #eef2f6;
}

/* --- HORIZONTAL RULES: completely invisible, page break only --- */
hr {
    border: 0 !important;
    border-top: 0 !important;
    border-bottom: 0 !important;
    background: transparent !important;
    background-color: transparent !important;
    color: transparent !important;
    height: 0 !important;
    max-height: 0 !important;
    min-height: 0 !important;
    margin: 0 !important;
    padding: 0 !important;
    line-height: 0 !important;
    font-size: 0 !important;
    outline: none !important;
    box-shadow: none !important;
    opacity: 0 !important;
    visibility: hidden !important;
    display: block;
    page-break-after: always;
}

blockquote {
    border: none;
    background: #f5f8fb;
    margin: 10pt 0 16pt 0;
    padding: 8pt 12pt;
    color: #333;
    page-break-inside: avoid;
}

a { color: #00838f; text-decoration: none; }

/* --- STRONG / BOLD labels in analysis sections --- */
strong {
    color: #0a1929;
}

/* --- Ensure content after pre/table doesn't overlap --- */
pre + p, pre + h2, pre + h3, pre + h4,
table + p, table + h2, table + h3, table + h4,
pre + blockquote, table + blockquote {
    margin-top: 16pt;
}

/* --- Analysis labels --- */
p strong:first-child {
    color: #00838f;
}

ul, ol { margin: 4pt 0; padding-left: 20pt; }
"""


# -----------------------------------------------------------------------------
# Cover page (markdown with inline HTML + base64 logo)
# -----------------------------------------------------------------------------
COVER_CSS = """
@page {
    size: A4;
    margin: 0;
}
body {
    font-family: 'Segoe UI', Arial, sans-serif;
    margin: 0;
    padding: 0;
}
.cover {
    background: linear-gradient(180deg, #0a1929 0%, #0f2847 100%);
    color: white;
    padding: 50mm 20mm;
    text-align: center;
    min-height: 250mm;
}
.cover img { max-width: 120mm; margin-bottom: 12mm; }
.cover h1 {
    color: white;
    font-size: 28pt;
    margin: 6mm 0 3mm;
    border: none;
    padding: 0;
}
.cover h2 {
    color: #00e5ff;
    font-size: 14pt;
    font-weight: 400;
    margin: 0 0 18mm;
    border: none;
    padding: 0;
}
.meta {
    color: #94a3b8;
    font-size: 10pt;
    line-height: 1.7;
    margin-top: 15mm;
}
.meta strong { color: #00e5ff; }
.disclaimer {
    margin-top: 15mm;
    padding: 6mm;
    background: rgba(255, 100, 100, 0.12);
    border-left: 2pt solid #ff6b6b;
    font-size: 8.5pt;
    color: #ffdddd;
    text-align: left;
    max-width: 140mm;
    margin-left: auto;
    margin-right: auto;
}
.disclaimer strong { color: white; }
"""


def load_logo_data_uri() -> str:
    """Return a data: URI for the Zeal Defense logo (prefers PNG, falls back to SVG)."""
    if LOGO_PNG.exists():
        data = LOGO_PNG.read_bytes()
        b64 = base64.b64encode(data).decode("ascii")
        return f"data:image/png;base64,{b64}"
    if LOGO_SVG.exists():
        data = LOGO_SVG.read_bytes()
        b64 = base64.b64encode(data).decode("ascii")
        return f"data:image/svg+xml;base64,{b64}"
    print("[WARN] No logo file found in assets/ - using text-only cover")
    return ""


def build_cover_markdown(title: str, doc_name: str) -> str:
    """Return a markdown string for the cover page (uses raw HTML)."""
    logo_uri = load_logo_data_uri()
    date_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    logo_tag = f'<img src="{logo_uri}" alt="Zeal Defense" />' if logo_uri else '<h1 style="font-size:42pt;color:#00e5ff;">ZEAL DEFENSE</h1>'

    return f"""<div class="cover">
{logo_tag}

<h1>{title}</h1>
<h2>5C Security Lab — Cloud-Native AI Governance Platform</h2>

<div class="meta">
<strong>Document:</strong> {doc_name}<br>
<strong>Generated:</strong> {date_str}<br>
<strong>Version:</strong> 1.0<br>
<strong>Compliance Frameworks:</strong> SAMA-CSF • NCA-ECC • NCA-CCC • PDPL
</div>

<div class="disclaimer">
<strong>FOR EDUCATIONAL AND AUTHORIZED SECURITY TRAINING ONLY</strong><br>
This document describes intentionally vulnerable systems for hands-on
security training. All PII data referenced is synthetic. Do not use
these techniques against systems you do not own or have authorization
to test. Unauthorized access to computing resources is illegal.
</div>
</div>
"""


# -----------------------------------------------------------------------------
# Convert one markdown file to PDF
# -----------------------------------------------------------------------------
def convert(md_path: Path, out_path: Path, title: str = None) -> bool:
    if not md_path.exists():
        print(f"[WARN] Missing: {md_path}")
        return False

    title = title or md_path.stem.replace("_", " ").title()
    print(f"[{datetime.datetime.now():%H:%M:%S}] Converting {md_path.relative_to(ROOT)} -> {out_path.relative_to(ROOT)}")

    pdf = MarkdownPdf(toc_level=3)
    pdf.meta["title"] = title
    pdf.meta["author"] = "Zeal Defense"
    pdf.meta["creator"] = "5C Security Lab PDF Exporter"

    # Cover page
    cover_md = build_cover_markdown(title, md_path.name)
    pdf.add_section(Section(cover_md, toc=False), user_css=COVER_CSS)

    # Content — strip standalone --- horizontal rules (they render as dark stripes
    # in markdown-pdf/PyMuPDF even with visibility:hidden; h1 page-break handles breaks)
    import re as _re
    content = md_path.read_text(encoding="utf-8")
    content = _re.sub(r'(?m)^\s*-{3,}\s*$', '', content)
    pdf.add_section(Section(content, toc=True), user_css=CSS)

    try:
        pdf.save(str(out_path))
    except Exception as e:
        print(f"[ERROR] Failed to write PDF: {e}")
        return False

    size_kb = out_path.stat().st_size / 1024
    print(f"[OK] Created {out_path.relative_to(ROOT)} ({size_kb:.1f} KB)")
    return True


# -----------------------------------------------------------------------------
# Doc list
# -----------------------------------------------------------------------------
ALL_DOCS = [
    ("README.md",                         "Project Overview"),
    ("docs/SETUP_GUIDE.md",               "GCP Deployment Guide"),
    ("docs/LAB_MANUAL.md",                "Lab Manual - Index"),
    ("docs/LAB_EXECUTION_GUIDE.md",       "Master Execution Playbook"),
    ("docs/LAB_TEST_CASES.md",            "Test Case Catalog (200+ Payloads)"),
]


def main():
    args = sys.argv[1:]

    print("=" * 50)
    print("  5C Security Lab - PDF Export")
    print("=" * 50)

    # Log availability
    logo_status = "PNG" if LOGO_PNG.exists() else ("SVG" if LOGO_SVG.exists() else "MISSING")
    print(f"  Logo:      {logo_status}")
    print(f"  Output to: {BUILD.relative_to(ROOT)}/")
    print()

    # Targets
    if not args:
        targets = [(ROOT / src, BUILD / (Path(src).stem + ".pdf"), title) for src, title in ALL_DOCS]
    else:
        targets = []
        for arg in args:
            p = Path(arg)
            src = ROOT / p if not p.is_absolute() else p
            out = BUILD / (src.stem + ".pdf")
            targets.append((src, out, None))

    success = 0
    for src, out, title in targets:
        if convert(src, out, title):
            success += 1

    print()
    print("=" * 50)
    print(f"  Export Complete: {success}/{len(targets)} PDFs generated")
    print("=" * 50)
    for src, out, _ in targets:
        if out.exists():
            size_kb = out.stat().st_size / 1024
            print(f"  {out.relative_to(ROOT)}  ({size_kb:.1f} KB)")
    print(f"\n  Open folder: explorer {BUILD}")


if __name__ == "__main__":
    main()
