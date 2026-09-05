# Bundled typography

Rethink Sans and JetBrains Mono are the website's display and metadata faces.
Both variable fonts are bundled locally under their accompanying SIL Open Font
Licenses. System fonts remain in use for ordinary controls and editing.

Downloaded 2026-09-04 from Google Fonts:

- https://github.com/google/fonts/tree/main/ofl/rethinksans
- https://github.com/google/fonts/tree/main/ofl/jetbrainsmono

The upstream variable TTF files are renamed RethinkSans.ttf and JetBrainsMono.ttf.
CampAppearance registers them once with Core Text for the app process. No font
download or system-wide installation happens at runtime.
