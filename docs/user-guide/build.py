#!/usr/bin/env python3
"""Builds the FlappedEar Telemetry user guide into a static site.

Each file in pages/ (English, published at the site root) and pages-pl/
(Polish, published under /pl/) is an HTML body fragment whose first line is
    <!-- title: Page title | nav: Sidebar label -->
The build wraps every page in the shared layout and copies assets/. It fails
when a page is missing from NAV (or NAV names a missing page), when a link
points to a missing page or anchor, when an image is missing or has no alt
text, or when the Polish pages differ from the English ones in page set,
anchors, links or images. Standard library only.

Usage: python3 docs/user-guide/build.py [output directory]
The default output directory is docs/user-guide/_site.
"""

from html import escape
from html.parser import HTMLParser
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
REPO = "https://github.com/FlappedEar/Telemetry"

# Sidebar groups, in order. Every page in pages/ appears exactly once.
NAV = [
    ("Start here", ["index", "install", "quick-start"]),
    ("Your day", ["import", "day", "laps", "saving", "profile"]),
    ("Looking at a lap", ["lap", "compare", "corners", "driving"]),
    ("Day analysis", ["theoretical-best", "segments", "day-report"]),
    ("Reference", ["overlays", "phone", "troubleshooting"]),
]

GROUPS_PL = {
    "Start here": "Zacznij tutaj",
    "Your day": "Twój dzień",
    "Looking at a lap": "Oglądanie okrążenia",
    "Day analysis": "Analiza dnia",
    "Reference": "Informacje",
}

# One entry per language. English is the default and lives at the site root.
LANGS = {
    "en": {
        "dir": ROOT / "pages", "out": "", "assets": "assets/", "other": "pl",
        "html_lang": "en", "title_suffix": "FlappedEar Telemetry User Guide",
        "brand": "User Guide", "skip": "Skip to content", "menu": "Menu",
        "source": "Source on GitHub", "switch": "Polski", "switch_label": "Przeczytaj po polsku",
        "nav_label": "User guide", "pager_label": "Previous and next page",
        "groups": {},
    },
    "pl": {
        "dir": ROOT / "pages-pl", "out": "pl/", "assets": "../assets/", "other": "en",
        "html_lang": "pl", "title_suffix": "Podręcznik użytkownika FlappedEar Telemetry",
        "brand": "Podręcznik użytkownika", "skip": "Przejdź do treści", "menu": "Menu",
        "source": "Kod źródłowy na GitHubie", "switch": "English", "switch_label": "Read in English",
        "nav_label": "Podręcznik użytkownika", "pager_label": "Poprzednia i następna strona",
        "groups": GROUPS_PL,
    },
}

META = re.compile(r"^<!--\s*title:\s*(.+?)\s*\|\s*nav:\s*(.+?)\s*-->\s*$")


class Collector(HTMLParser):
    """Collects ids, links and images of one page."""

    def __init__(self):
        super().__init__()
        self.ids, self.links, self.images = set(), [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if tag == "img":
            self.images.append((attrs.get("src", ""), attrs.get("alt", "")))


def read_pages(lang):
    pages = {}
    for path in sorted(LANGS[lang]["dir"].glob("*.html")):
        first, _, body = path.read_text(encoding="utf-8").partition("\n")
        match = META.match(first)
        if not match:
            sys.exit(f"{path.name}: first line must be <!-- title: ... | nav: ... -->")
        pages[path.stem] = {"title": match[1], "nav": match[2], "body": body}
    return pages


def check(pages, lang):
    errors = []
    prefix = "" if lang == "en" else "pages-pl/"
    listed = [name for _, names in NAV for name in names]
    for name in listed:
        if name not in pages:
            errors.append(f"{prefix}NAV lists {name}.html, which does not exist")
    for name in pages:
        if listed.count(name) != 1:
            errors.append(f"{prefix}{name}.html must appear exactly once in NAV")
    parsed = {}
    for name, page in pages.items():
        collector = Collector()
        collector.feed(page["body"])
        parsed[name] = collector
    for name, collector in parsed.items():
        for href in collector.links:
            if re.match(r"^(https?:|mailto:)", href):
                continue
            target, _, anchor = href.partition("#")
            page = name if target == "" else target.removesuffix(".html")
            if target and not target.endswith(".html"):
                if not (ROOT / target).exists():
                    errors.append(f"{prefix}{name}.html links to missing file {href}")
                continue
            if page not in parsed:
                errors.append(f"{prefix}{name}.html links to missing page {href}")
            elif anchor and anchor not in parsed[page].ids:
                errors.append(f"{prefix}{name}.html links to missing anchor {href}")
        for src, alt in collector.images:
            if not (ROOT / src).is_file():
                errors.append(f"{prefix}{name}.html shows missing image {src}")
            if not alt.strip():
                errors.append(f"{prefix}{name}.html: image {src} has no alt text")
    return parsed, errors


def check_parity(english, polish):
    """The Polish pages must mirror the English ones: same pages, anchors, links, images."""
    errors = []
    for name in sorted(set(english) | set(polish)):
        if name not in polish:
            errors.append(f"pages-pl/{name}.html is missing")
        elif name not in english:
            errors.append(f"pages-pl/{name}.html has no English page")
        else:
            en, pl = english[name], polish[name]
            if en.ids != pl.ids:
                diff = sorted(en.ids ^ pl.ids)
                errors.append(f"pages-pl/{name}.html: ids differ from English: {diff}")
            if sorted(en.links) != sorted(pl.links):
                errors.append(f"pages-pl/{name}.html: links differ from English")
            if sorted(src for src, _ in en.images) != sorted(src for src, _ in pl.images):
                errors.append(f"pages-pl/{name}.html: images differ from English")
    return errors


def fail(errors):
    if errors:
        sys.exit("User guide check failed:\n  " + "\n  ".join(errors))


def sidebar(pages, current, lang):
    parts = []
    for group, names in NAV:
        group = LANGS[lang]["groups"].get(group, group)
        parts.append(f'<p class="nav-group">{escape(group)}</p>\n<ul>')
        for name in names:
            mark = ' aria-current="page"' if name == current else ""
            label = escape(pages[name]["nav"])
            parts.append(f'<li><a href="{name}.html"{mark}>{label}</a></li>')
        parts.append("</ul>")
    return "\n".join(parts)


def neighbours(current):
    order = [name for _, names in NAV for name in names]
    i = order.index(current)
    return (order[i - 1] if i > 0 else None, order[i + 1] if i + 1 < len(order) else None)


TEMPLATE = """<!doctype html>
<html lang="{html_lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · {title_suffix}</title>
<link rel="stylesheet" href="{assets}style.css">
<link rel="alternate" hreflang="{other}" href="{switch_href}">
</head>
<body>
<a class="skip" href="#content">{skip}</a>
<header class="topbar">
  <button class="menu" type="button" aria-controls="sidebar" aria-expanded="false">{menu}</button>
  <a class="brand" href="index.html">FlappedEar Telemetry <span>{brand}</span></a>
  <a class="lang" href="{switch_href}" hreflang="{other}" lang="{other}" title="{switch_label}">{switch}</a>
  <a class="repo" href="{repo}">{source}</a>
</header>
<div class="layout">
<nav id="sidebar" class="sidebar" aria-label="{nav_label}">
{sidebar}
</nav>
<main id="content">
<article>
{body}
</article>
<nav class="pager" aria-label="{pager_label}">{pager}</nav>
</main>
</div>
<script>
const button = document.querySelector('.menu');
button.addEventListener('click', () => {{
  const open = document.body.classList.toggle('nav-open');
  button.setAttribute('aria-expanded', open);
}});
</script>
</body>
</html>
"""


def render(lang, pages, output):
    cfg = LANGS[lang]
    target = output / cfg["out"]
    target.mkdir(parents=True, exist_ok=True)
    for name, page in pages.items():
        before, after = neighbours(name)
        pager = ""
        if before:
            pager += f'<a class="prev" href="{before}.html">← {escape(pages[before]["nav"])}</a>'
        if after:
            pager += f'<a class="next" href="{after}.html">{escape(pages[after]["nav"])} →</a>'
        # Fragments reference shared assets as assets/...; the Polish site sits one level down.
        body = re.sub(r'(src|href)="assets/', rf'\1="{cfg["assets"]}', page["body"].strip())
        # The language switch lands on the same page of the other language.
        switch_href = ("pl/" if cfg["other"] == "pl" else "../") + f"{name}.html"
        html = TEMPLATE.format(
            title=escape(page["title"]),
            repo=REPO,
            sidebar=sidebar(pages, name, lang),
            body=body,
            pager=pager,
            switch_href=switch_href,
            **{k: cfg[k] for k in (
                "html_lang", "title_suffix", "assets", "other", "skip", "menu", "brand",
                "source", "switch", "switch_label", "nav_label", "pager_label")},
        )
        (target / f"{name}.html").write_text(html, encoding="utf-8")


def build(output):
    parsed, errors = {}, []
    pages = {lang: read_pages(lang) for lang in LANGS}
    for lang in LANGS:
        parsed[lang], found = check(pages[lang], lang)
        errors += found
    errors += check_parity(parsed["en"], parsed["pl"])
    fail(errors)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    shutil.copytree(ASSETS, output / "assets")
    for lang in LANGS:
        render(lang, pages[lang], output)
    (output / ".nojekyll").write_text("")
    print(f"Built {len(pages['en'])} pages x {len(LANGS)} languages into {output}")


if __name__ == "__main__":
    build(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "_site")
