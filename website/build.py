#!/usr/bin/env python3
"""Builds OneRoot's website into website/public: Home, Support (from
docs/SUPPORT.md) and Privacy (from docs/PRIVACY.md). Same build, look and
deployment as the Bzide site, so the two stay a family.

Only the Python standard library. Run from anywhere:
    python3 website/build.py
The Markdown handled is what those docs use: # headings, paragraphs,
- bullets, 1. steps, | tables, and inline **bold**, *italic*, `code` and
[links](url).
"""

import hashlib
import html
import re
import shutil
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
OUT = WEBSITE / "public"
# In the stylesheet's URL, so Cloudflare and browsers (which keep it for a
# day) fetch a changed one at once.
STYLE_VERSION = hashlib.sha256((WEBSITE / "style.css").read_bytes()).hexdigest()[:10]

# The one place to change the site's details.
SITE = {
    "name": "OneRoot",
    "url": "https://oneroot.hillcraft-sc.com",
    # Downloads are GitHub releases (that repo holds releases only).
    "download_url": "https://github.com/hillcraft-sc/OneRoot/releases/latest",
    "issues_url": "https://github.com/hillcraft-sc/OneRoot/issues",
    # A support/licensing address (public). Empty hides it; GitHub issues
    # are the contact then.
    "support_email": "admin@hillcraft-sc.com",
    "tip_url": "https://ko-fi.com/hillcraftsc",
}


# MARK: - Markdown

def inline(text: str) -> str:
    """Escapes HTML, then styles code, links, bold and italic."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)
    return text


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"[`*]", "", text.lower())).strip("-")


def cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def markdown(source: str) -> tuple[str, str, list[tuple[str, str]]]:
    """The page's title (its # heading), its HTML, and its ## sections for a contents list."""
    title, parts, sections = "", [], []
    paragraph, bullets, steps, table = [], [], [], []

    def flush():
        nonlocal paragraph, bullets, steps, table
        if paragraph:
            parts.append(f"<p>{inline(' '.join(paragraph))}</p>")
        if bullets:
            parts.append("<ul>" + "".join(f"<li>{inline(item)}</li>" for item in bullets) + "</ul>")
        if steps:
            parts.append("<ol>" + "".join(f"<li>{inline(item)}</li>" for item in steps) + "</ol>")
        if table:
            header, rows = table[0], [row for row in table[1:] if not all(re.fullmatch(r":?-+:?", c) for c in row)]
            head = "".join(f"<th>{inline(c)}</th>" for c in header)
            body = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>" for row in rows)
            parts.append(f'<div class="table"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>')
        paragraph, bullets, steps, table = [], [], [], []

    for raw in source.replace("\r\n", "\n").split("\n"):
        line = raw.strip()
        heading = re.match(r"^(#{1,3}) (.+)$", line)
        step = re.match(r"^(\d{1,3})\. (.+)$", line)
        if not line:
            flush()
        elif heading:
            flush()
            level, text = len(heading.group(1)), heading.group(2).strip()
            if level == 1:
                title = text
                continue
            anchor = slug(text)
            if level == 2:
                sections.append((anchor, text))
            parts.append(f'<h{level} id="{anchor}">{inline(text)}</h{level}>')
        elif line.startswith(("- ", "* ")):
            if paragraph or steps or table:
                flush()
            bullets.append(line[2:])
        elif step:
            if paragraph or bullets or table:
                flush()
            steps.append(step.group(2))
        elif line.startswith("|"):
            if paragraph or bullets or steps:
                flush()
            table.append(cells(line))
        elif bullets:
            bullets[-1] += " " + line
        elif steps:
            steps[-1] += " " + line
        else:
            if table:
                flush()
            paragraph.append(line)
    flush()
    return title, "\n".join(parts), sections


def tip_link(text: str) -> str:
    return f'<a href="{SITE["tip_url"]}">{text}</a>'


def email_link() -> str:
    """The support address as a mailto link, marked for Cloudflare's Email
    Address Obfuscation to leave alone (its decoder script is blocked by the
    site's Content-Security-Policy)."""
    address = SITE["support_email"]
    return f'<!--email_off--><a href="mailto:{address}">{address}</a><!--/email_off-->'


def contact_link() -> str:
    return email_link() if SITE["support_email"] else f'<a href="{SITE["issues_url"]}">GitHub</a>'


# MARK: - Pages

def page(slug_name: str, title: str, body: str, description: str) -> str:
    nav = "".join(
        f'<a href="{href}"{" aria-current=\"page\"" if key == slug_name else ""}>{label}</a>'
        for key, href, label in (("home", "/", "Home"), ("support", "/support.html", "Support"), ("privacy", "/privacy.html", "Privacy"), ("more", "https://hillcraft-sc.com", "More Apps"))
    )
    full_title = f"{SITE['name']}: a file manager for macOS" if slug_name == "home" else f"{title} · {SITE['name']}"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="icon" href="/favicon.png">
<link rel="stylesheet" href="/style.css?v={STYLE_VERSION}">
</head>
<body>
<header class="site">
  <a class="brand" href="/"><img src="/icon-256.png" alt="" width="32" height="32">{SITE['name']}</a>
  <nav>{nav}</nav>
</header>
<main>
{body}
</main>
<footer class="site">
  <p>OneRoot is free software under the <a href="https://www.gnu.org/licenses/gpl-3.0.html">GNU GPL v3</a>. The OneRoot name and icon are not covered by that license. © 2026 Eric Hebert.</p>
  <p>Made by <a href="https://hillcraft-sc.com">Hillcraft</a> · <a href="/support.html">Support</a> · <a href="/privacy.html">Privacy</a> · <a href="{SITE['download_url']}">Download</a> · {tip_link("Leave a tip")}</p>
</footer>
</body>
</html>
"""


def document_page(slug_name: str, source: Path, intro: str, description: str) -> str:
    title, body, sections = markdown(source.read_text(encoding="utf-8"))
    contents = "".join(f'<li><a href="#{anchor}">{inline(text)}</a></li>' for anchor, text in sections)
    toc = f'<nav class="toc" aria-label="Contents"><h2>Contents</h2><ol>{contents}</ol></nav>' if len(sections) > 3 else ""
    return page(slug_name, title, f'<article class="doc"><h1>{inline(title)}</h1>{intro}{toc}{body}</article>', description)


def home() -> str:
    features = [
        ("Tabs that remember", "Each tab keeps its folder, history, selection and sort. Open several windows, and pick up where you left off next time."),
        ("See where you are", "A folder tree rooted where you're working, a sortable list with the columns you choose, and a path you can click or type into."),
        ("The Inspector", "A large preview and the details of whatever's selected: kind, size, dates, permissions and tags, with the actions that fit it."),
        ("Copy, move, undo", "Cut and paste files, with live progress, a Cancel that really stops, Retry when something fails, and Undo for copies, moves, renames and trashing."),
        ("Dual Pane and Workspaces", "Two folders side by side when you're sorting things out, and Workspaces that gather a project's folders from wherever they live."),
        ("Find anything", "Filter the current folder as you type, or search everywhere by name, kind, date, size, tag or contents, with results as they arrive."),
        ("Quick Actions", "Resize and convert images, combine into PDF, convert documents, batch rename, compress and extract, each previewed first and undoable."),
        ("Native and private", "Built with Apple's frameworks, with no third-party code. No analytics, no accounts, and no network connections of its own."),
    ]
    cards = "".join(f'<div class="card"><h3>{html.escape(t)}</h3><p>{html.escape(d)}</p></div>' for t, d in features)
    body = f"""<section class="hero">
  <img class="icon" src="/icon-256.png" alt="The OneRoot app icon" width="128" height="128">
  <h1>Your files, under control.</h1>
  <p class="lede">OneRoot is a fast, native file manager for macOS. Browsing stays calm and familiar; the power tools are there the moment you need them.</p>
  <a class="button" href="{SITE['download_url']}">Download for Mac</a>
  <p class="soon">Or with Homebrew: <code>brew install --cask hillcraft-sc/tap/oneroot</code></p>
  <p class="soon">Free and open source · macOS 14 or later · Apple silicon and Intel</p>
  <p class="soon">Looking for Linux? There's an early release (0.3.1) with most of the Mac features, still rough in places: <a href="https://github.com/hillcraft-sc/OneRoot/releases/tag/linux-v0.3.1">see the Linux release</a>.</p>
</section>
<section class="features">{cards}</section>
<section class="more">
  <p>OneRoot is signed by its developer and notarized by Apple. See <a href="/support.html">Support</a> for installing it and giving it Full Disk Access, and <a href="/privacy.html">Privacy</a> for what it keeps and where.</p>
  <p>OneRoot is free software (<a href="https://github.com/hillcraft-sc/OneRoot">source on GitHub</a>). If you enjoy it, you can {tip_link("leave a tip on Ko-fi")}.</p>
</section>"""
    return page("home", "Home", body, "OneRoot: a fast, native file manager for macOS, with tabs, a folder tree, an Inspector, Dual Pane, Workspaces, search, and file operations you can undo.")


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for file in (WEBSITE / "static").iterdir():
        shutil.copy(file, OUT / file.name)
    shutil.copy(WEBSITE / "style.css", OUT / "style.css")
    contact = (
        '<div class="contact"><h2>Contact</h2><p>Questions, problems or ideas? '
        + (f"Email {email_link()}, or open an issue on <a href=\"{SITE['issues_url']}\">GitHub</a>."
           if SITE["support_email"] else f"Open an issue on <a href=\"{SITE['issues_url']}\">GitHub</a>.")
        + "</p></div>"
    )
    pages = {
        "index.html": home(),
        "support.html": document_page("support", REPO / "docs" / "SUPPORT.md", contact, "How to install, set up and get help with OneRoot."),
        "privacy.html": document_page("privacy", REPO / "docs" / "PRIVACY.md", "", "OneRoot's privacy policy: what it connects to, what it keeps on your Mac, and what it never sends."),
    }
    for name, content in pages.items():
        (OUT / name).write_text(content, encoding="utf-8")
    print(f"Built {len(pages)} pages into {OUT}")


if __name__ == "__main__":
    build()
