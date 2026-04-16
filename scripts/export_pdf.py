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
    margin: 20mm 18mm;
}

body {
    font-family: 'Segoe UI', 'Helvetica Neue', Arial, sans-serif;
    font-size: 10.5pt;
    line-height: 1.55;
    color: #1a1a1a;
}

h1, h2, h3, h4, h5 { color: #0a1929; page-break-after: avoid; }
h1 {
    font-size: 22pt;
    border-bottom: 3px solid #00b8d4;
    padding-bottom: 6px;
    margin-top: 24pt;
}
h2 {
    font-size: 16pt;
    border-bottom: 1px solid #c0c8d0;
    padding-bottom: 3px;
    margin-top: 18pt;
    color: #00838f;
}
h3 { font-size: 13pt; margin-top: 14pt; }
h4 { font-size: 11pt; color: #555; }

p, li { margin: 4pt 0; }

code {
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 9pt;
    background: #eef2f6;
    color: #0a1929;
    padding: 1pt 4pt;
    border: 1px solid #d0d7de;
    border-radius: 2pt;
}

pre {
    background: #0a1929;
    color: #e2e8f0;
    padding: 10pt;
    border-left: 3pt solid #00e5ff;
    border-radius: 3pt;
    font-size: 8.5pt;
    white-space: pre-wrap;
    word-wrap: break-word;
    page-break-inside: avoid;
}
pre code {
    background: transparent;
    border: none;
    color: #e2e8f0;
    padding: 0;
}

table {
    border-collapse: collapse;
    width: 100%;
    margin: 8pt 0;
    font-size: 9pt;
    page-break-inside: avoid;
}
th {
    background: #0a1929;
    color: white;
    text-align: left;
    padding: 6pt 8pt;
    font-weight: 600;
}
td {
    padding: 5pt 8pt;
    border: 1px solid #d0d7de;
    vertical-align: top;
}
tr:nth-child(even) td { background: #f5f8fb; }

blockquote {
    border-left: 3pt solid #00e5ff;
    background: #e8f5fa;
    margin: 8pt 0;
    padding: 6pt 10pt;
    color: #333;
}

a { color: #00838f; text-decoration: none; }

hr { border: none; border-top: 1px solid #c0c8d0; margin: 16pt 0; }

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

    # Content
    content = md_path.read_text(encoding="utf-8")
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
