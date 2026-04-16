# Store banner (Google Play feature graphic)

Plik: `feature_graphic.svg`

- Rozmiar: **1024×500** (zgodny z Google Play "Feature graphic").
- Tło jest pełne (bez przezroczystości).
- Teksty są proste — możesz je zmienić pod swoją ofertę.

## Jak wyeksportować do PNG

Najprościej w Inkscape:

1) Otwórz `feature_graphic.svg`
2) `File → Export…`
3) Wybierz **PNG**, ustaw **1024×500**, eksportuj.

CLI (jeśli masz Inkscape w PATH):

```powershell
inkscape .\store\feature_graphic.svg --export-type=png --export-filename=.\store\feature_graphic.png --export-width=1024 --export-height=500
```

Następnie w Play Console wgraj PNG jako **Feature graphic**.
