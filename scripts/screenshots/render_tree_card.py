#!/usr/bin/env python3
"""
Render the "Terraform behind this week" file tree as a PNG card.

    python scripts/screenshots/render_tree_card.py \
        --week week-07-asset-inventory \
        --tree week-07-asset-inventory/docs/blog/tree.txt \
        --out  week-07-asset-inventory/docs/blog/screenshots/05-terraform-layout.png

Why an image and not a <pre> in the post
----------------------------------------
The Azure and AWS labs already publish this card as a committed PNG, and a
reader moving between the three series should meet the same object each week
rather than three different renderings of the same idea. A <pre> block inherits
the post's code styling, which is correct for a code sample and wrong here: this
is a figure about the shape of the week, and it reads as one.

Why a script and not a one-off
------------------------------
The Azure image was produced by hand and left no tool behind, so the next week
starts from nothing and the styling drifts. This takes a plain text tree and
always produces the same card, so consistency is mechanical rather than
remembered.

The tree text is written by hand (line counts come from `wc -l`, never
estimated) and lives next to the screenshots as tree.txt, so the figure and its
source stay together and a stale count is visible in a diff.

Attaches to the same signed-in Chrome the other captures use, purely because it
is already running; nothing here needs a session. Rendering is fully local.
"""

import argparse
import html
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

# Matches the Azure lab's card: white ground, dark code panel, one accent weight
# for the heading. Deliberately not themed - the card is an image, so it cannot
# respond to the reader's dark mode and must be legible on either.
TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><style>
  * {{ box-sizing: border-box; }}
  /* Rendered at 2x and downscaled by the page. At 1x the one-pixel vertical
     strokes of the tree connectors pick up red/blue subpixel fringing on the
     dark panel, which looks like a colour choice and is not one. */
  body {{ margin: 0; padding: 26px; background: #ffffff; zoom: 2;
         font-family: "Segoe UI", Arial, sans-serif; }}
  .card {{ background: #ffffff; border-radius: 14px; padding: 26px 28px 30px;
           box-shadow: 0 2px 10px rgba(16,24,40,.10); width: 980px; }}
  h1 {{ font-size: 19px; margin: 0 0 4px; color: #101828; font-weight: 700; }}
  p.sub {{ font-size: 12.5px; margin: 0 0 18px; color: #667085; }}
  pre {{ background: #1b2436; color: #e6edf3; border-radius: 10px;
         padding: 22px 24px; margin: 0; overflow: visible;
         font-family: Consolas, "Cascadia Mono", Menlo, monospace;
         font-size: 12.5px; line-height: 1.62; white-space: pre; }}
  .c {{ color: #8b98ad; }}
  .n {{ color: #9db2d0; }}
</style></head>
<body><div class="card">
  <h1>{title}</h1>
  <p class="sub">{subtitle}</p>
  <pre>{tree}</pre>
</div></body></html>"""


def colourise(line: str) -> str:
    """Grey the comments and the line counts; leave the tree itself alone."""
    esc = html.escape(line)
    if "#" in esc:
        head, _, tail = esc.partition("#")
        return f'{head}<span class="c">#{tail}</span>'
    return esc


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--week", required=True, help="e.g. week-07-asset-inventory")
    ap.add_argument("--tree", required=True, help="plain text file holding the tree")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cdp", default="9222")
    ap.add_argument("--title", default="The Terraform behind this week")
    args = ap.parse_args()

    tree_path = Path(args.tree)
    if not tree_path.exists():
        sys.exit(f"no tree file at {tree_path}")
    body = "\n".join(colourise(ln) for ln in tree_path.read_text(encoding="utf-8").rstrip("\n").split("\n"))

    doc = TEMPLATE.format(
        title=html.escape(args.title),
        subtitle=html.escape(f"{args.week} — what each file does, and how big it actually is"),
        tree=body,
    )

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()  # never leave a stale card behind if this run fails

    with sync_playwright() as pw:
        browser = pw.chromium.connect_over_cdp(f"http://127.0.0.1:{args.cdp}", timeout=90000)
        page = browser.contexts[0].new_page()
        try:
            page.set_viewport_size({"width": 2240, "height": 1800})
            page.set_content(doc, wait_until="load")
            page.wait_for_timeout(700)
            card = page.query_selector(".card")
            card.screenshot(path=str(out), scale="device")
        finally:
            page.close()

    if not out.exists():
        sys.exit("render produced no file")
    print(f"Saved: {out}  ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
