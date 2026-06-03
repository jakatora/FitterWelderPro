"""
Third pass over the mojibake bug: previous PowerShell scripts in tools/ covered
Polish letters (ą/ć/ę/...) and emoji/dash glyphs but missed engineering symbols
that the FITTER submenu and the cut-list project tile use heavily:

    Ã˜ → Ø        outer diameter
    Ã— → ×        multiplication / "x"
    Â° → °        degree
    Â· → ·        middle dot used as visual separator
    â†" → ↔       left-right arrow (DN ↔ OD)
    â†' → →       right arrow (sequence)
    â€¢ → •       bullet
    â€" → —       em dash
    â€' → –       en dash
    âˆ' → −       minus
    Î± → α        greek alpha
    Î² → β        greek beta
    Î¸ → θ        greek theta

Idempotent: re-running does nothing because the replacements happen in a fixed
order and the target glyphs never re-introduce a source pattern. Writes UTF-8
without BOM.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"

# Longer mojibake patterns first so a 3-byte sequence isn't partially eaten by
# a shorter rule.
PAIRS = [
    # multi-byte arrows + punctuation (longer first so partials don't eat them)
    ("â†”", "↔"),
    ('â†"', "↔"),
    ("â†→", "→"),
    ("â†’", "→"),
    ("â†'", "→"),
    # â† + U+0090 (cp1252 control) = ← (left arrow). The control byte often
    # renders as nothing in editors but is there in the bytes.
    ("â†", "←"),
    ("â† ", "← "),
    ("âˆš", "√"),
    ("Â±", "±"),
    # ð = 0xF0 sequence used in mojibake'd emoji. Common ones:
    ("ðŸ\"", "📝"),  # pencil/edit
    ("â€¢", "•"),
    ('â€"', "—"),
    ("â€'", "–"),
    ("âˆ'", "−"),
    ("âˆ’", "−"),
    # latin-1 wedged characters
    ("Ã˜", "Ø"),
    ("Ã—", "×"),
    # greek letters used in formulas
    ("Î”", "Δ"),
    ("Î±", "α"),
    ("Î²", "β"),
    ("Î¸", "θ"),
    ("Ï", "ρ"),
    # Â-prefixed superscripts and punctuation
    ("Â³", "³"),
    ("Â²", "²"),
    ("Â¹", "¹"),
    ("Â°", "°"),
    ("Â·", "·"),
    ("Â®", "®"),
    # 2026-06-03: catches caught by the chat ISO module audit.
    # Subscripts (e.g. O₂, C₀) — 3-byte UTF-8 0xE2 0x82 0x8X misread as Win-1252.
    ("â‚‚", "₂"),
    ("â‚€", "₀"),
    ("â‚", "₁"),
    ("â‚ƒ", "₃"),
    # Capital S-acute (Ś) — Win-1252 mojibake for 0xC5 0x9A. fix_polish_encoding.ps1
    # has lowercase ś but missed the uppercase variant used in labels ("Średnica").
    ("Åš", "Ś"),
    # Box drawing horizontal — used as visual separator in form headers.
    ("â”€", "─"),
    # Emoji that the help button screen uses as section markers; the
    # mojibake'd byte sequence in help_button.dart is the result of the
    # original repo write going through Win-1252 round-trip.
    ("ðŸ'¨", "💨"),
]

changed_files = 0
changed_chars = 0
scanned = 0
for path in ROOT.rglob("*.dart"):
    scanned += 1
    text = path.read_text(encoding="utf-8")
    new = text
    for bad, good in PAIRS:
        if bad in new:
            new = new.replace(bad, good)
    if new != text:
        path.write_text(new, encoding="utf-8", newline="\n")
        changed_files += 1
        changed_chars += sum(1 for a, b in zip(text, new) if a != b)
        print(f"  fixed {path.relative_to(ROOT.parent)}")

print(f"\nscanned {scanned} files | changed {changed_files} | char diffs ~ {changed_chars}")
