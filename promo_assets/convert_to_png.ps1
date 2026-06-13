# ============================================================
# FitterWelderPro - SVG -> PNG batch converter
# ------------------------------------------------------------
# Tries Inkscape first (best quality, native SVG renderer).
# Falls back to Microsoft Edge --headless --screenshot,
# wrapping each SVG in a temporary HTML shell so Edge renders
# it at its native (viewBox) resolution.
#
# Output: ./png/<original-name>.png
# ============================================================

[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$Force
)

if (-not $Root) { $Root = (Get-Location).Path }

$pngDir = Join-Path $Root 'png'
if (-not (Test-Path $pngDir)) {
    New-Item -ItemType Directory -Path $pngDir | Out-Null
}

# ---- locate renderer ---------------------------------------
$inkscape = Get-Command inkscape -ErrorAction SilentlyContinue
$useInkscape = $false
if ($inkscape) {
    $useInkscape = $true
    Write-Host "[renderer] Inkscape detected at: $($inkscape.Source)" -ForegroundColor Green
} else {
    $edgeCandidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    )
    $edge = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $edge) {
        Write-Host "[renderer] Neither Inkscape nor Microsoft Edge found. Install Inkscape or run on Windows with Edge." -ForegroundColor Red
        exit 1
    }
    Write-Host "[renderer] Inkscape not found - falling back to Edge headless: $edge" -ForegroundColor Yellow
}

# ---- collect inputs ----------------------------------------
$svgFiles = @()
$svgFiles += Get-ChildItem -Path (Join-Path $Root 'screenshots') -Filter '*.svg' -File -ErrorAction SilentlyContinue
$svgFiles += Get-ChildItem -Path (Join-Path $Root 'banners')     -Filter '*.svg' -File -ErrorAction SilentlyContinue

if (-not $svgFiles -or $svgFiles.Count -eq 0) {
    Write-Host "No SVG files found under $Root\screenshots or $Root\banners." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host ("Converting {0} SVG file(s) -> {1}" -f $svgFiles.Count, $pngDir) -ForegroundColor Cyan
Write-Host ("-" * 60)

# ---- helpers -----------------------------------------------
function Get-SvgViewBox {
    param([string]$Path)
    try {
        $head = Get-Content -Path $Path -TotalCount 12 -ErrorAction Stop -Encoding UTF8
        $joined = ($head -join ' ')
        if ($joined -match 'viewBox\s*=\s*"\s*([\-\d\.]+)\s+([\-\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s*"') {
            return [pscustomobject]@{
                W = [math]::Round([double]$Matches[3])
                H = [math]::Round([double]$Matches[4])
            }
        }
        if ($joined -match 'width\s*=\s*"\s*([\d\.]+)' -and $joined -match 'height\s*=\s*"\s*([\d\.]+)') {
            $w = [double]($joined | Select-String -Pattern 'width\s*=\s*"\s*([\d\.]+)'  | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
            $h = [double]($joined | Select-String -Pattern 'height\s*=\s*"\s*([\d\.]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
            return [pscustomobject]@{ W = [math]::Round($w); H = [math]::Round($h) }
        }
    } catch {}
    return [pscustomobject]@{ W = 1200; H = 1200 }
}

function Convert-Inkscape {
    param([string]$SvgPath, [string]$PngPath, [int]$W, [int]$H)
    & $inkscape.Source `
        --export-type=png `
        --export-filename=$PngPath `
        --export-width=$W `
        --export-height=$H `
        --export-background-opacity=1.0 `
        $SvgPath 2>&1 | Out-Null
    return (Test-Path $PngPath)
}

function Convert-Edge {
    param([string]$SvgPath, [string]$PngPath, [int]$W, [int]$H)

    $tmpDir = Join-Path $env:TEMP ('fwp_svg_' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    try {
        $svgName = [System.IO.Path]::GetFileName($SvgPath)
        Copy-Item -Path $SvgPath -Destination (Join-Path $tmpDir $svgName) -Force

        $html = @"
<!doctype html>
<html><head><meta charset='utf-8'><style>
html,body{margin:0;padding:0;background:#0F1115;}
img{display:block;width:${W}px;height:${H}px;}
</style></head>
<body><img src="$svgName"></body></html>
"@
        $htmlPath = Join-Path $tmpDir 'page.html'
        Set-Content -Path $htmlPath -Value $html -Encoding UTF8

        $args = @(
            '--headless=new',
            '--disable-gpu',
            '--no-sandbox',
            '--hide-scrollbars',
            ('--window-size={0},{1}' -f $W, $H),
            ('--screenshot=' + $PngPath),
            ('--default-background-color=0F1115FF'),
            ('file:///' + ($htmlPath -replace '\\','/'))
        )
        & $edge @args 2>&1 | Out-Null
        return (Test-Path $PngPath)
    } finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- main loop ---------------------------------------------
$converted = 0
$failed    = 0
$failedList = @()
$idx = 0

foreach ($svg in $svgFiles) {
    $idx++
    $name = $svg.BaseName
    $pngPath = Join-Path $pngDir ($name + '.png')
    $rel = $svg.FullName.Substring($Root.Length).TrimStart('\','/')

    if ((Test-Path $pngPath) -and -not $Force) {
        Write-Host ("[{0,2}/{1}] SKIP   {2}  (already exists, use -Force to overwrite)" -f $idx, $svgFiles.Count, $rel) -ForegroundColor DarkGray
        $converted++
        continue
    }

    $vb = Get-SvgViewBox -Path $svg.FullName
    $w  = [int]$vb.W
    $h  = [int]$vb.H
    if ($w -le 0 -or $h -le 0) { $w = 1200; $h = 1200 }

    Write-Host ("[{0,2}/{1}] {2}  ({3}x{4})  ... " -f $idx, $svgFiles.Count, $rel, $w, $h) -NoNewline

    $ok = $false
    try {
        if ($useInkscape) {
            $ok = Convert-Inkscape -SvgPath $svg.FullName -PngPath $pngPath -W $w -H $h
        } else {
            $ok = Convert-Edge -SvgPath $svg.FullName -PngPath $pngPath -W $w -H $h
        }
    } catch {
        $ok = $false
        Write-Host ""
        Write-Host ("    error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    if ($ok) {
        $converted++
        Write-Host "OK" -ForegroundColor Green
    } else {
        $failed++
        $failedList += $rel
        Write-Host "FAIL" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host ("-" * 60)
Write-Host ("Summary:  {0} converted   {1} failed   out: {2}" -f $converted, $failed, $pngDir) -ForegroundColor Cyan
if ($failed -gt 0) {
    Write-Host "Failed files:" -ForegroundColor Yellow
    foreach ($f in $failedList) { Write-Host ("  - " + $f) -ForegroundColor Yellow }
}
if ($useInkscape) {
    Write-Host "Renderer: Inkscape (native)" -ForegroundColor DarkGray
} else {
    Write-Host "Renderer: Microsoft Edge headless (fallback)" -ForegroundColor DarkGray
}

if ($failed -gt 0) { exit 1 } else { exit 0 }
