# Second-pass fixer: emoji + em-dash mojibake.
# Run AFTER fix_polish_encoding.ps1.
#
# Pattern format: source-mojibake (3-4 chars from Win-1252 misread) →
# original character.  Emoji codepoints above U+FFFF are written as
# UTF-16 surrogate pairs in the replacement string.

# Helper: build a 2-codepoint string from a high surrogate + low surrogate.
function HS($hi, $lo) { return [string]::new([char[]]@([char]$hi, [char]$lo)) }

$pairs = @(
    # Common emojis (UTF-8 4-byte sequences misread as 4 Win-1252 chars)
    # NB: "ðŸ" prefix below is U+00F0 + U+0178 (matches UTF-8 F0 9F).
    @('wrench-1f527',  "$([char]0x00F0)$([char]0x0178)$([char]0x201D)$([char]0x00A7)", (HS 0xD83D 0xDD27)), # ðŸ”§ → 🔧
    @('fire-1f525',    "$([char]0x00F0)$([char]0x0178)$([char]0x201D)$([char]0x00A5)", (HS 0xD83D 0xDD25)), # ðŸ”¥ → 🔥
    @('clipboard',     "$([char]0x00F0)$([char]0x0178)$([char]0x201C)$([char]0x2039)", (HS 0xD83D 0xDCCB)), # ðŸ"‹ → 📋
    @('books',         "$([char]0x00F0)$([char]0x0178)$([char]0x201C)$([char]0x0161)", (HS 0xD83D 0xDCDA)), # ðŸ"š → 📚
    @('chart',         "$([char]0x00F0)$([char]0x0178)$([char]0x201C)$([char]0x0160)", (HS 0xD83D 0xDCCA)), # ðŸ"Š → 📊
    @('worker',        "$([char]0x00F0)$([char]0x0178)$([char]0x2018)$([char]0x00B7)", (HS 0xD83D 0xDC77)), # ðŸ'· → 👷
    @('finger-up',     "$([char]0x00F0)$([char]0x0178)$([char]0x2018)$([char]0x2020)", (HS 0xD83D 0xDC46)), # ðŸ'† → 👆
    @('abacus',        "$([char]0x00F0)$([char]0x0178)$([char]0x00A7)$([char]0x00AE)", (HS 0xD83D 0xDDEE)), # ðŸ§® → 🧮 (note: corruption may not be perfect)
    @('lightning',     "$([char]0x00E2)$([char]0x0161)$([char]0x00A1)",                [string][char]0x26A1),  # âš¡ → ⚡
    @('heavy-plus',    "$([char]0x00E2)$([char]0x017E)$([char]0x2022)",                [string][char]0x2795),  # âž• → ➕
    @('check',         "$([char]0x00E2)$([char]0x0153)$([char]0x2026)",                [string][char]0x2705),  # âœ… → ✅
    @('pencil',        "$([char]0x00E2)$([char]0x0153)$([char]0x008F)$([char]0x00EF)$([char]0x00B8)$([char]0x008F)", "$([char]0x270F)$([char]0xFE0F)"), # âœï¸ → ✏️ (often shortened to "âœï¸")
    @('arrow-up-down', "$([char]0x00E2)$([char]0x2020)$([char]0x2022)$([char]0x00EF)$([char]0x00B8)$([char]0x008F)", "$([char]0x2195)$([char]0xFE0F)"), # â†•ï¸ → ↕️
    # Dashes — most common comment/punctuation corruption
    @('em-dash',       "$([char]0x00E2)$([char]0x20AC)$([char]0x201D)",                [string][char]0x2014),  # â€" → — (U+2014)
    @('en-dash',       "$([char]0x00E2)$([char]0x20AC)$([char]0x201C)",                [string][char]0x2013),  # â€" → – (U+2013, less common)
    # Curly quotes
    @('lsquo',         "$([char]0x00E2)$([char]0x20AC)$([char]0x02DC)",                [string][char]0x2018),  # â€˜ → '
    @('rsquo',         "$([char]0x00E2)$([char]0x20AC)$([char]0x2122)",                [string][char]0x2019),  # â€™ → '
    @('ldquo',         "$([char]0x00E2)$([char]0x20AC)$([char]0x0153)",                [string][char]0x201C),  # â€œ → "
    @('rdquo',         "$([char]0x00E2)$([char]0x20AC)$([char]0x009D)",                [string][char]0x201D)   # â€ → "
)

$files = Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse
$totalChanged = 0
$totalReplacements = 0

foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $original = $content
    $localCount = 0

    foreach ($pair in $pairs) {
        $name, $bad, $good = $pair
        $beforeLen = $content.Length
        $content = $content.Replace($bad, $good)
        $afterLen = $content.Length
        if ($beforeLen -ne $afterLen) {
            $localCount += ($beforeLen - $afterLen) / ($bad.Length - $good.Length)
        }
    }

    if ($content -ne $original) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)
        Write-Host ("  fixed {0,4} chars in {1}" -f $localCount, $f.FullName.Replace($PWD.Path + '\', ''))
        $totalChanged++
        $totalReplacements += $localCount
    }
}

Write-Host ""
Write-Host ("Done: $totalChanged file(s) updated, $totalReplacements replacement(s).")
