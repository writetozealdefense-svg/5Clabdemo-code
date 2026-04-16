# =============================================================================
# 5C Security Lab - PDF Export Script (Windows PowerShell)
#
# Converts any markdown document in docs/ or labs/ to a branded PDF with:
#   - Zeal Defense logo on cover page
#   - Professional styling (navy + cyan brand colors)
#   - Table of contents
#   - Syntax-highlighted code blocks
#   - Page numbers in footer
#
# Usage:
#   .\scripts\export-to-pdf.ps1 -Input docs/LAB_TEST_CASES.md
#   .\scripts\export-to-pdf.ps1 -Input docs/LAB_EXECUTION_GUIDE.md -Output MyLab.pdf
#   .\scripts\export-to-pdf.ps1 -All              # exports every key doc
#
# Requirements:
#   - pandoc  (choco install pandoc)  — markdown parser
#   - wkhtmltopdf  (choco install wkhtmltopdf)  — HTML to PDF
#     OR
#   - weasyprint  (pip install weasyprint)  — Python alternative
#
# Logo location: assets/zeal-defense-logo.png (add this file manually)
# =============================================================================

param(
    [string]$InputFile = "docs/LAB_TEST_CASES.md",
    [string]$Output = "",
    [switch]$All,
    [string]$Title = "",
    [string]$Engine = "auto"     # auto / wkhtmltopdf / weasyprint / pandoc-native
)

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Fail($m) { Write-Host "[ERROR] $m" -ForegroundColor Red; exit 1 }
function Write-Log($m)  { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" -ForegroundColor Blue }

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$AssetsDir   = Join-Path $ProjectRoot "assets"
$BuildDir    = Join-Path $ProjectRoot "build"

$LogoPath  = Join-Path $AssetsDir "zeal-defense-logo.png"
$CssPath   = Join-Path $AssetsDir "pdf-style.css"
$TplPath   = Join-Path $AssetsDir "pdf-cover.html"

# -----------------------------------------------------------------------------
# Validate environment
# -----------------------------------------------------------------------------
if (-not (Test-Path $CssPath)) { Write-Fail "Missing $CssPath" }
if (-not (Test-Path $TplPath)) { Write-Fail "Missing $TplPath" }

if (-not (Test-Path $LogoPath)) {
    Write-Warn "Logo not found at $LogoPath"
    Write-Warn "Save the Zeal Defense logo there as a PNG before running, or the cover will have a broken image."
    $useLogoPlaceholder = $true
} else {
    $useLogoPlaceholder = $false
}

if (-not (Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir | Out-Null }

# -----------------------------------------------------------------------------
# Detect conversion engine
# -----------------------------------------------------------------------------
$hasPandoc      = (Get-Command pandoc -ErrorAction SilentlyContinue) -ne $null
$hasWkhtmltopdf = (Get-Command wkhtmltopdf -ErrorAction SilentlyContinue) -ne $null
$hasWeasyprint  = (Get-Command weasyprint -ErrorAction SilentlyContinue) -ne $null

Write-Log "Detecting tools..."
if ($hasPandoc)      { Write-Ok "pandoc found: $(pandoc --version | Select-Object -First 1)" }
if ($hasWkhtmltopdf) { Write-Ok "wkhtmltopdf found" }
if ($hasWeasyprint)  { Write-Ok "weasyprint found" }

if (-not $hasPandoc) {
    Write-Fail "pandoc is required. Install with: winget install JohnMacFarlane.Pandoc`n  Or: choco install pandoc"
}

# Resolve engine
if ($Engine -eq "auto") {
    if     ($hasWkhtmltopdf) { $Engine = "wkhtmltopdf" }
    elseif ($hasWeasyprint)  { $Engine = "weasyprint" }
    else                     { $Engine = "pandoc-native" }
}
Write-Ok "Using engine: $Engine"

# -----------------------------------------------------------------------------
# File list (when -All)
# -----------------------------------------------------------------------------
$allDocs = @(
    @{ Input = "README.md";                         Title = "Project Overview" }
    @{ Input = "docs/SETUP_GUIDE.md";               Title = "GCP Deployment Guide" }
    @{ Input = "docs/LAB_MANUAL.md";                Title = "Lab Manual — Index" }
    @{ Input = "docs/LAB_EXECUTION_GUIDE.md";       Title = "Master Execution Playbook" }
    @{ Input = "docs/LAB_TEST_CASES.md";            Title = "Test Case Catalog (200+ payloads)" }
)

$targets = if ($All) { $allDocs } else { @(@{ Input = $InputFile; Title = $Title }) }

# -----------------------------------------------------------------------------
# Conversion function
# -----------------------------------------------------------------------------
function Convert-MdToPdf {
    param([string]$MdFile, [string]$OutFile, [string]$DocTitle)

    $mdPath = Join-Path $ProjectRoot $MdFile
    if (-not (Test-Path $mdPath)) {
        Write-Warn "Input not found: $mdPath - skipping"
        return
    }

    if ([string]::IsNullOrEmpty($DocTitle)) {
        $DocTitle = [System.IO.Path]::GetFileNameWithoutExtension($MdFile) -replace '_', ' '
    }
    if ([string]::IsNullOrEmpty($OutFile)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($MdFile)
        $OutFile = Join-Path $BuildDir "${base}.pdf"
    }

    Write-Log "Converting: $MdFile -> $OutFile"

    # --- Step 1: Build the composite HTML ---
    $tempHtml = Join-Path $BuildDir "_tmp_$([guid]::NewGuid().ToString().Substring(0,8)).html"
    $tempBodyHtml = Join-Path $BuildDir "_body_$([guid]::NewGuid().ToString().Substring(0,8)).html"

    try {
        # Pandoc: markdown -> HTML fragment (with syntax highlighting, but no <html>/<head>)
        pandoc $mdPath `
            --from markdown `
            --to html5 `
            --no-highlight `
            --toc --toc-depth=3 `
            -o $tempBodyHtml
        if ($LASTEXITCODE -ne 0) { Write-Warn "pandoc body conversion had warnings"; }

        # Load pieces
        $bodyHtml = Get-Content $tempBodyHtml -Raw -Encoding UTF8
        $cssContent = Get-Content $CssPath -Raw -Encoding UTF8
        $template = Get-Content $TplPath -Raw -Encoding UTF8

        # Logo: embed as data URI for wkhtmltopdf / weasyprint
        if ($useLogoPlaceholder) {
            $logoUri = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHdpZHRoPSczMDAnIGhlaWdodD0nMTUwJyB2aWV3Qm94PScwIDAgMzAwIDE1MCc+PHJlY3Qgd2lkdGg9JzMwMCcgaGVpZ2h0PScxNTAnIGZpbGw9JyMwYTE5MjknLz48dGV4dCB4PScxNTAnIHk9JzgwJyB0ZXh0LWFuY2hvcj0nbWlkZGxlJyBmaWxsPScjMDBlNWZmJyBmb250LWZhbWlseT0nQXJpYWwnIGZvbnQtc2l6ZT0nMzInIGZvbnQtd2VpZ2h0PSdib2xkJz5aRUFMPC90ZXh0Pjx0ZXh0IHg9JzE1MCcgeT0nMTE1JyB0ZXh0LWFuY2hvcj0nbWlkZGxlJyBmaWxsPScjZmZmJyBmb250LWZhbWlseT0nQXJpYWwnIGZvbnQtc2l6ZT0nMjAnPkRFRkVOU0U8L3RleHQ+PC9zdmc+"
        } else {
            $bytes = [System.IO.File]::ReadAllBytes($LogoPath)
            $b64 = [Convert]::ToBase64String($bytes)
            $logoUri = "data:image/png;base64,$b64"
        }

        # Template substitution
        $final = $template `
            -replace '\{\{TITLE\}\}',        [regex]::Escape($DocTitle).Replace('\','') `
            -replace '\{\{DOC_NAME\}\}',     (Split-Path $MdFile -Leaf) `
            -replace '\{\{DATE\}\}',         (Get-Date -Format 'yyyy-MM-dd HH:mm') `
            -replace '\{\{VERSION\}\}',      '1.0' `
            -replace '\{\{LOGO_URI\}\}',     $logoUri `
            -replace '\{\{INLINE_CSS\}\}',   [regex]::Escape($cssContent).Replace('\','') `
            -replace '\{\{CONTENT\}\}',      [regex]::Escape($bodyHtml).Replace('\','')

        # The above regex::Escape trick doesn't work for CSS/HTML bodies.
        # Use a different approach: simple string replace without regex
        $final = $template
        $final = $final.Replace('{{TITLE}}', $DocTitle)
        $final = $final.Replace('{{DOC_NAME}}', (Split-Path $MdFile -Leaf))
        $final = $final.Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd HH:mm'))
        $final = $final.Replace('{{VERSION}}', '1.0')
        $final = $final.Replace('{{LOGO_URI}}', $logoUri)
        $final = $final.Replace('{{INLINE_CSS}}', $cssContent)
        $final = $final.Replace('{{CONTENT}}', $bodyHtml)

        [System.IO.File]::WriteAllText($tempHtml, $final, [System.Text.Encoding]::UTF8)

        # --- Step 2: HTML -> PDF ---
        switch ($Engine) {
            "wkhtmltopdf" {
                wkhtmltopdf `
                    --enable-local-file-access `
                    --page-size A4 `
                    --margin-top 20mm --margin-bottom 20mm `
                    --margin-left 15mm --margin-right 15mm `
                    --footer-center "Zeal Defense | [page] of [topage]" `
                    --footer-font-size 8 `
                    --footer-font-name "Arial" `
                    --footer-spacing 5 `
                    --encoding UTF-8 `
                    $tempHtml $OutFile
            }
            "weasyprint" {
                weasyprint $tempHtml $OutFile
            }
            "pandoc-native" {
                # Fallback: use pandoc's built-in PDF engine
                # (requires LaTeX or chrome/edge headless)
                Write-Warn "Using pandoc native engine (may require LaTeX or edge)."
                pandoc $mdPath `
                    --from markdown `
                    --to pdf `
                    --toc --toc-depth=3 `
                    --css=$CssPath `
                    --metadata title="$DocTitle" `
                    --metadata author="Zeal Defense" `
                    --metadata date=(Get-Date -Format 'yyyy-MM-dd') `
                    -o $OutFile
            }
        }

        if (Test-Path $OutFile) {
            $sizeKB = [math]::Round((Get-Item $OutFile).Length / 1KB, 1)
            Write-Ok "Created $OutFile ($sizeKB KB)"
        } else {
            Write-Warn "Output not created: $OutFile"
        }
    }
    finally {
        if (Test-Path $tempHtml) { Remove-Item $tempHtml -Force }
        if (Test-Path $tempBodyHtml) { Remove-Item $tempBodyHtml -Force }
    }
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Blue
Write-Host "  5C Security Lab - PDF Export" -ForegroundColor Blue
Write-Host "==========================================" -ForegroundColor Blue

foreach ($t in $targets) {
    Convert-MdToPdf -MdFile $t.Input -OutFile $Output -DocTitle $t.Title
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Export Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output directory: $BuildDir"
Write-Host "  Open folder:      Start-Process '$BuildDir'"
Write-Host ""

if ($All) {
    Write-Host "  Generated files:"
    Get-ChildItem $BuildDir -Filter "*.pdf" | ForEach-Object {
        Write-Host "    $($_.FullName) ($([math]::Round($_.Length / 1KB, 1)) KB)"
    }
}
