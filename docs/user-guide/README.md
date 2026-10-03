# User guide sources

The end-user guide for FlappedEar Telemetry, published to GitHub Pages at
<https://flappedear.github.io/Telemetry/> from `main`.

- `pages/*.html` holds one HTML body fragment per page. Its first line is
  `<!-- title: Page title | nav: Sidebar label -->`. The sidebar order is `NAV`
  in `build.py`.
- `assets/style.css` is the site's stylesheet (light and dark).
- `assets/screens/` holds the screenshots. They are taken from the app's own
  widgets with the owner's Jastrząb day of 29 August 2026, which the owner
  approved for the public guide (heart rate included).
- `build.py` (Python standard library only) wraps each page in the shared
  layout. It fails when a page is missing from `NAV`, a link points to a missing
  page or anchor, or an image is missing or has no alt text.

## Build and preview

```bash
python3 docs/user-guide/build.py      # writes docs/user-guide/_site (ignored by Git)
open docs/user-guide/_site/index.html
```

## Screenshots

```bash
git clone https://github.com/FlappedEar/refdata ../refdata   # private
GUIDE_RECORDINGS=../refdata \
  flutter test tool/user_guide/capture_screens_test.dart --update-goldens
```

This imports the recordings in `GUIDE_RECORDINGS` (the Jastrząb day in the
private `FlappedEar/refdata`) and drives the real pages at a 1280 × 800 desktop and a
412 × 915 phone, writing PNGs to `assets/screens/`. Text is drawn with Roboto
from the Flutter SDK. Maps show the street background's controls and
attribution over plain grey tiles, because tests have no network. Look at every
changed picture before committing it. Without `GUIDE_RECORDINGS` the tool uses
the made-up day of `tool/user_guide/demo_day.dart`, for trying it out; do not
publish those pictures.

## Publishing

`.github/workflows/user-guide.yml` builds the guide on pull requests that change
it, and deploys it to GitHub Pages on pushes to `main`. The repository setting
**Settings → Pages → Build and deployment → Source** must be **GitHub Actions**.

## Keeping it current

[AGENTS.md](../../AGENTS.md) ("The user guide") requires every change a user can
see to update the guide in the same pull request, and the pull request template
asks for it.
