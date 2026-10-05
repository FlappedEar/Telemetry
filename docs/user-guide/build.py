#!/usr/bin/env python3
"""Builds the FlappedEar Telemetry user guide into a static site.

Each file in pages/ is an HTML body fragment whose first line is
    <!-- title: Page title | nav: Sidebar label -->
The build wraps every page in the shared layout and copies assets/. It fails
when a page is missing from NAV (or NAV names a missing page), when a link
points to a missing page or anchor, or when an image is missing or has no
alt text. Standard library only.

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
PAGES = ROOT / "pages"
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


def read_pages():
    pages = {}
    for path in sorted(PAGES.glob("*.html")):
        first, _, body = path.read_text(encoding="utf-8").partition("\n")
        match = META.match(first)
        if not match:
            sys.exit(f"{path.name}: first line must be <!-- title: ... | nav: ... -->")
        pages[path.stem] = {"title": match[1], "nav": match[2], "body": body}
    return pages


def check(pages):
    errors = []
    listed = [name for _, names in NAV for name in names]
    for name in listed:
        if name not in pages:
            errors.append(f"NAV lists {name}.html, which does not exist")
    for name in pages:
        if listed.count(name) != 1:
            errors.append(f"{name}.html must appear exactly once in NAV")
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
                    errors.append(f"{name}.html links to missing file {href}")
                continue
            if page not in parsed:
                errors.append(f"{name}.html links to missing page {href}")
            elif anchor and anchor not in parsed[page].ids:
                errors.append(f"{name}.html links to missing anchor {href}")
        for src, alt in collector.images:
            if not (ROOT / src).is_file():
                errors.append(f"{name}.html shows missing image {src}")
            if not alt.strip():
                errors.append(f"{name}.html: image {src} has no alt text")
    if errors:
        sys.exit("User guide check failed:\n  " + "\n  ".join(errors))


def sidebar(pages, current):
    parts = []
    for group, names in NAV:
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
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · FlappedEar Telemetry User Guide</title>
<link rel="stylesheet" href="assets/style.css">
</head>
<body>
<a class="skip" href="#content">Skip to content</a>
<header class="topbar">
  <button class="menu" type="button" aria-controls="sidebar" aria-expanded="false">Menu</button>
  <a class="brand" href="index.html">FlappedEar Telemetry <span>User Guide</span></a>
  <a class="repo" href="{repo}">Source on GitHub</a>
</header>
<div class="layout">
<nav id="sidebar" class="sidebar" aria-label="User guide">
{sidebar}
</nav>
<main id="content">
<article>
{body}
</article>
<nav class="pager" aria-label="Previous and next page">{pager}</nav>
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


def build(output):
    pages = read_pages()
    check(pages)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    shutil.copytree(ASSETS, output / "assets")
    for name, page in pages.items():
        before, after = neighbours(name)
        pager = ""
        if before:
            pager += f'<a class="prev" href="{before}.html">← {escape(pages[before]["nav"])}</a>'
        if after:
            pager += f'<a class="next" href="{after}.html">{escape(pages[after]["nav"])} →</a>'
        html = TEMPLATE.format(
            title=escape(page["title"]),
            repo=REPO,
            sidebar=sidebar(pages, name),
            body=page["body"].strip(),
            pager=pager,
        )
        (output / f"{name}.html").write_text(html, encoding="utf-8")
    (output / ".nojekyll").write_text("")
    print(f"Built {len(pages)} pages into {output}")


if __name__ == "__main__":
    build(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "_site")
