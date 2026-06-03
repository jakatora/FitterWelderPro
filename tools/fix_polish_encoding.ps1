# Fix UTF-8 mojibake (PL chars) in all .dart files under lib/.
#
# Root cause: an editor read a UTF-8 file using Windows-1252 (cp1252) — NOT
# pure Latin-1 — then re-saved as UTF-8. Win-1252 maps the 0x80-0x9F range
# to smart-quotes / em-dash / TM / etc. (instead of control characters),
# so the corruption pattern is:
#   "ą" (U+0105) → UTF-8 bytes C4 85 → Win-1252 reads: 0xC4="Ä", 0x85="…"
#                → text becomes literal "Ä…" (U+00C4 + U+2026)
#
# Each Polish character below is mapped from its corrupted 2-codepoint form
# back to the original Unicode codepoint. The script reads each file as
# UTF-8, applies all replacements, and writes back as UTF-8 WITHOUT BOM
# if anything changed. Idempotent — re-running is a no-op.

# IMPORTANT: PowerShell source files in Windows PowerShell 5.1 are decoded
# using the system ANSI code page. Use $([char]0xXXXX) escapes for the
# Win-1252 second byte to keep the script ASCII-only on disk.

# Lowercase Polish letters (Win-1252 corruption pattern)
$pairs = @(
    @('a-ogonek',  "$([char]0x00C4)$([char]0x2026)", [char]0x0105),  # Ä… → ą
    @('c-acute',   "$([char]0x00C4)$([char]0x2021)", [char]0x0107),  # Ä‡ → ć
    @('e-ogonek',  "$([char]0x00C4)$([char]0x2122)", [char]0x0119),  # Ä™ → ę
    @('l-stroke',  "$([char]0x00C5)$([char]0x201A)", [char]0x0142),  # Å‚ → ł
    @('n-acute',   "$([char]0x00C5)$([char]0x201E)", [char]0x0144),  # Å„ → ń
    @('o-acute',   "$([char]0x00C3)$([char]0x00B3)", [char]0x00F3),  # Ã³ → ó
    @('s-acute',   "$([char]0x00C5)$([char]0x203A)", [char]0x015B),  # Å› → ś
    @('z-acute',   "$([char]0x00C5)$([char]0x00BA)", [char]0x017A),  # Åº → ź
    @('z-dot',     "$([char]0x00C5)$([char]0x00BC)", [char]0x017C),  # Å¼ → ż
    # Uppercase Polish letters
    @('A-ogonek',  "$([char]0x00C4)$([char]0x201E)", [char]0x0104),  # Ä„ → Ą
    @('C-acute',   "$([char]0x00C4)$([char]0x2020)", [char]0x0106),  # Ä† → Ć
    @('E-ogonek',  "$([char]0x00C4)$([char]0x02DC)", [char]0x0118),  # Ä˜ → Ę
    @('L-stroke',  "$([char]0x00C5)$([char]0x0081)", [char]0x0141),  # Å + U+0081 → Ł (rare; 0x81 undefined in Win-1252, stays raw)
    @('N-acute',   "$([char]0x00C5)$([char]0x0192)", [char]0x0143),  # Åƒ → Ń
    @('O-acute',   "$([char]0x00C3)$([char]0x201C)", [char]0x00D3),  # Ã" → Ó
    @('O-acute-2', "$([char]0x00C3)$([char]0x201D)", [char]0x00D3),  # Ã" → Ó (curly close)
    @('Z-acute',   "$([char]0x00C5)$([char]0x00B9)", [char]0x0179),  # Å¹ → Ź
    @('Z-dot',     "$([char]0x00C5)$([char]0x00BB)", [char]0x017B)   # Å» → Ż
)

# Comment markers that often get mangled by box-drawing characters.
# These aren't critical to runtime — they're comments — but the cleanup
# makes future diffs readable. Comment box-draw → ASCII dash.
$boxDrawClean = @(
    @("$([char]0x00E2)$([char]0x20AC)$([char]0x201C)", '-'),  # â€" → -
    @("$([char]0x00E2)$([char]0x20AC)$([char]0x201D)", '-'),  # â€" → -
    @("$([char]0x00E2)$([char]0x201C)$([char]0x20AC)", '-'),  # variation
    @("$([char]0x00E2)$([char]0x201D)$([char]0x20AC)", '-')   # variation
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
            # Each match shortens the string by ($bad.Length - $good.Length).
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
Write-Host ("Done: $totalChanged file(s) updated, $totalReplacements character(s) replaced.")
