"""Chalkboard sketchnote diagrams, declared as data.

The prototype that won approval was hand-positioned SVG, which would have made
every week a bespoke art project. This is the same look with the layout pulled
out, so a week's diagram is a short spec and the drawing is shared.

    from sketchboard import Board
    b = Board("Access that expires on its own", eyebrow="GCP Lab - Week 11")
    b.icon_node("subject", 150, 270, "identity_and_access_management.svg",
                title="the subject", lines=["a service account",
                                            ("holding no roles", "warn")])
    b.panel("ent", 360, 176, 330, 160, title="entitlement",
            lines=["a template, not a grant"], corner="PAM")
    b.arrow("subject", "ent", "may ASK")
    b.write("week-11.svg")

THE RULE, which every diagram inherits: Google's icon terms permit resizing and
repositioning their marks and NOTHING else. `icon_node` places an icon
untouched. Anything that is not a Google product is drawn - `person`, `folder`,
`clock`, `panel`. If a product has no official icon, draw a panel; do not
improvise a mark.

Determinism: the hand-drawn wobble is seeded from the diagram title, so the same
spec always yields a byte-identical file and a regenerated diagram can be
reviewed in a diff.
"""
from __future__ import annotations

import io
import math
import os
import random
import re
import urllib.request
import zipfile

ICON_ZIP = "https://services.google.com/fh/files/misc/google-cloud-legacy-icons.zip"
ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".icon-cache")

CHALK = "#f1eee4"
DIM = "#c3cbc0"
WARN = "#f0ad92"
GOOD = "#a6d2ae"
GOLD = "#f2d08a"
COLOURS = {"": CHALK, "dim": DIM, "warn": WARN, "good": GOOD, "gold": GOLD}


def ensure_icons() -> None:
    """Fetch Google's official icon library once, into a gitignored cache.

    Not vendored. Using the marks in a diagram is covered by their terms;
    shipping a copy of their library in a public repo is a separate question.
    """
    if os.path.isdir(ICONS) and os.listdir(ICONS):
        return
    os.makedirs(ICONS, exist_ok=True)
    with urllib.request.urlopen(ICON_ZIP, timeout=180) as r:
        z = zipfile.ZipFile(io.BytesIO(r.read()))
    for n in z.namelist():
        if n.lower().endswith(".svg"):
            with open(os.path.join(ICONS, n.split("/")[-1]), "wb") as f:
                f.write(z.read(n))


class Board:
    def __init__(self, title: str, eyebrow: str = "", w: int = 1280, h: int = 820,
                 credit: str = "jayanthkatta.com"):
        ensure_icons()
        self.w, self.h = w, h
        self.title, self.eyebrow, self.credit = title, eyebrow, credit
        self.parts: list[str] = []
        self.anchors: dict[str, tuple[float, float, float, float]] = {}
        self._uid = 0
        # Seeded from the title: same diagram, same wobble, every time.
        self.rng = random.Random(sum(ord(c) * (i + 7) for i, c in enumerate(title)))

    # ---- drawing primitives ------------------------------------------
    def _j(self, x, y, a=1.9):
        return x + self.rng.uniform(-a, a), y + self.rng.uniform(-a, a)

    def _line(self, x1, y1, x2, y2, col=CHALK, w=2.4, op=.92, marker=True):
        mx, my = self._j((x1 + x2) / 2, (y1 + y2) / 2, 4)
        m = ' marker-end="url(#nib)"' if marker else ""
        self.parts.append(
            f'<path d="M{x1:.0f},{y1:.0f} Q{mx:.0f},{my:.0f} {x2:.0f},{y2:.0f}" '
            f'fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round" '
            f'opacity="{op}"{m}/>')

    def _rect(self, x, y, w, h, col=CHALK, sw=2.3, op=.62):
        c = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        for i in range(4):
            x1, y1 = c[i]
            x2, y2 = c[(i + 1) % 4]
            ox1, oy1 = self._j(x1, y1, 2.2)
            ox2, oy2 = self._j(x2, y2, 2.2)
            mx, my = self._j((x1 + x2) / 2, (y1 + y2) / 2, 2.6)
            self.parts.append(
                f'<path d="M{ox1:.0f},{oy1:.0f} Q{mx:.0f},{my:.0f} {ox2:.0f},{oy2:.0f}" '
                f'fill="none" stroke="{col}" stroke-width="{sw}" '
                f'stroke-linecap="round" opacity="{op}"/>')

    def _circle(self, cx, cy, r, col=CHALK, sw=2.2, op=.5):
        d, start, steps = [], self.rng.uniform(0, .6), 26
        for i in range(steps + 1):
            a = start + 2 * math.pi * .97 * i / steps
            rr = r + self.rng.uniform(-1.6, 1.6)
            d.append(("M" if i == 0 else "L")
                     + f"{cx + rr*math.cos(a):.1f},{cy + rr*math.sin(a):.1f}")
        self.parts.append(f'<path d="{" ".join(d)}" fill="none" stroke="{col}" '
                          f'stroke-width="{sw}" stroke-linecap="round" opacity="{op}"/>')

    def _text(self, x, y, s, cls="b", col=None, anchor="start", op=None):
        c = f' fill="{col}"' if col else ""
        o = f' opacity="{op}"' if op else ""
        self.parts.append(f'<text x="{x:.0f}" y="{y:.0f}" text-anchor="{anchor}" '
                          f'class="hand {cls}"{c}{o}>{s}</text>')

    def _lines(self, x, y, lines, anchor="start", step=30):
        for i, ln in enumerate(lines):
            txt, style = (ln if isinstance(ln, tuple) else (ln, ""))
            self._text(x, y + i * step, txt, "b", COLOURS.get(style, CHALK), anchor)

    # ---- the pieces a diagram is made of -----------------------------
    def icon_node(self, key, cx, cy, icon_file, title="", lines=(), r=54):
        """A Google product: the official icon, untouched, in a drawn ring."""
        self._circle(cx, cy, r, CHALK, 2.2, .45)
        self.parts.append(self._icon(icon_file, cx, cy, int(r * 1.04)))
        if title:
            self._text(cx, cy + r + 34, title, "h2", anchor="middle")
        self._lines(cx, cy + r + 66, lines, anchor="middle")
        # Include the caption: an arrow leaving downward must clear the text,
        # not start on top of it.
        bottom = cy + r + (34 if title else 0) + (66 + (len(lines) - 1) * 30
                                                  if lines else 0)
        self.anchors[key] = (cx - r, cy - r, 2 * r, max(2 * r, bottom - (cy - r)))

    def panel(self, key, x, y, w, h, title="", lines=(), col=CHALK, corner=""):
        """A drawn box, for anything with no official icon."""
        self._rect(x, y, w, h, col, 2.4, .62)
        if corner:
            self._text(x + w - 8, y - 10, corner, "s", anchor="end", op=".6")
        if title:
            self._text(x + 24, y + 40, title, "h2", col if col != CHALK else None)
        self._lines(x + 24, y + 76, lines, step=32)
        self.anchors[key] = (x, y, w, h)

    def person(self, key, cx, cy, title="", lines=(), s=1.0):
        self._circle(cx, cy - 22 * s, 11 * s, CHALK, 2.4, .9)
        self.parts.append(
            f'<path d="M{cx},{cy-10*s} L{cx},{cy+16*s} M{cx-15*s},{cy+2*s} '
            f'L{cx+15*s},{cy+2*s} M{cx},{cy+16*s} L{cx-11*s},{cy+36*s} '
            f'M{cx},{cy+16*s} L{cx+11*s},{cy+36*s}" fill="none" stroke="{CHALK}" '
            f'stroke-width="2.6" stroke-linecap="round" opacity=".9"/>')
        if title:
            self._text(cx, cy + 86, title, "h2", anchor="middle")
        self._lines(cx, cy + 116, lines, anchor="middle")
        bottom = cy + (86 if title else 40) + (30 + (len(lines) - 1) * 30
                                               if lines else 0)
        self.anchors[key] = (cx - 20, cy - 34, 40, bottom - (cy - 34))

    def folder(self, key, x, y, w, h, title="", lines=(), icon_file=None, col=GOLD):
        self.parts.append(
            f'<path d="M{x},{y+10} L{x+4},{y} L{x+w*0.36:.0f},{y} '
            f'L{x+w*0.42:.0f},{y+10}" fill="none" stroke="{col}" stroke-width="2.4" '
            f'stroke-linejoin="round" opacity=".85"/>')
        self._rect(x, y + 10, w, h, col, 2.4, .85)
        tx = x + 24
        if icon_file:
            self.parts.append(self._icon(icon_file, x + 52, y + 10 + h / 2, 46))
            tx = x + 92
        if title:
            self._text(tx, y + 54, title, "h2")
        self._lines(tx, y + 90, lines, step=30)
        self.anchors[key] = (x, y, w, h + 10)

    def clock(self, cx, cy, r=26, note=(), ):
        self._circle(cx, cy, r, CHALK, 2.4, .9)
        self.parts.append(
            f'<path d="M{cx},{cy} L{cx},{cy-r*0.55:.0f} M{cx},{cy} '
            f'L{cx+r*0.42:.0f},{cy+r*0.2:.0f}" fill="none" stroke="{CHALK}" '
            f'stroke-width="2.4" stroke-linecap="round" opacity=".9"/>')
        self._lines(cx + r + 16, cy - 4, note, step=28)

    def arrow(self, a, b, label="", side="auto"):
        """Connect two registered shapes edge to edge, not centre to centre."""
        ax, ay, aw, ah = self.anchors[a]
        bx, by, bw, bh = self.anchors[b]
        acx, acy = ax + aw / 2, ay + ah / 2
        bcx, bcy = bx + bw / 2, by + bh / 2
        horizontal = abs(bcx - acx) >= abs(bcy - acy) if side == "auto" else side == "h"
        if horizontal:
            if bcx > acx:
                x1, y1, x2, y2 = ax + aw + 6, acy, bx - 10, bcy
            else:
                x1, y1, x2, y2 = ax - 6, acy, bx + bw + 10, bcy
        else:
            if bcy > acy:
                x1, y1, x2, y2 = acx, ay + ah + 6, bcx, by - 10
            else:
                x1, y1, x2, y2 = acx, ay - 6, bcx, by + bh + 10
        self._line(x1, y1, x2, y2)
        if label:
            if horizontal:
                self._text((x1 + x2) / 2, min(y1, y2) - 16, label, "s", anchor="middle")
            else:
                self._text((x1 + x2) / 2 + 16, (y1 + y2) / 2, label, "s")

    def note(self, x, y, lines, anchor="start"):
        self._lines(x, y, lines, anchor=anchor, step=28)

    # ---- icons --------------------------------------------------------
    def _icon(self, name, cx, cy, size):
        self._uid += 1
        uid = f"i{self._uid}"
        src = open(os.path.join(ICONS, name), encoding="utf-8").read()
        body = src[src.index(">", src.index("<svg")) + 1: src.rindex("</svg>")]
        # Every Google icon styles itself with .cls-1 / .cls-2. Two in one
        # document silently repaint each other, so namespace per instance.
        for cls in sorted(set(re.findall(r"cls-\d+", body)), reverse=True):
            body = body.replace(f".{cls}", f".{uid}{cls}")
            body = re.sub(rf'class="{cls}"', f'class="{uid}{cls}"', body)
        k = size / 24.0
        return (f'<g transform="translate({cx - size/2:.0f},{cy - size/2:.0f}) '
                f'scale({k:.3f})">{body}</g>')

    # ---- output -------------------------------------------------------
    def _chrome(self):
        head = [f'<rect width="{self.w}" height="{self.h}" fill="#30342f"/>',
                f'<rect width="{self.w}" height="{self.h}" fill="#2b2f2b" opacity=".5"/>']
        for _ in range(9):          # old chalk, half wiped
            cx = self.rng.uniform(60, self.w - 60)
            cy = self.rng.uniform(40, self.h - 40)
            head.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" '
                        f'rx="{self.rng.uniform(90,230):.0f}" '
                        f'ry="{self.rng.uniform(18,48):.0f}" fill="#ffffff" '
                        f'opacity="0.016" filter="url(#smudge)"/>')
        head.append(f'<rect width="{self.w}" height="{self.h}" filter="url(#grain)"/>')
        return head

    def write(self, path, alt=""):
        body = self._chrome()
        body.append(f'<text x="64" y="78" class="hand h1">{self.title}</text>')
        underline = min(64 + len(self.title) * 21, self.w - 220)
        mx, my = self._j((64 + underline) / 2, 96, 3)
        body.append(f'<path d="M64,96 Q{mx:.0f},{my:.0f} {underline},96" fill="none" '
                    f'stroke="{CHALK}" stroke-width="2.6" opacity=".4"/>')
        if self.eyebrow:
            body.append(f'<text x="{self.w-64}" y="78" text-anchor="end" '
                        f'class="hand s" opacity=".55">{self.eyebrow}</text>')
        body += self.parts
        if self.credit:
            body.append(f'<text x="{self.w-64}" y="{self.h-24}" text-anchor="end" '
                        f'class="hand s" opacity=".45">{self.credit}</text>')

        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
               f'width="{self.w}" height="{self.h}" role="img" '
               f'aria-label="{alt or self.title}">'
               + DEFS + "\n" + "\n".join(body) + "\n</svg>\n")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        return path


DEFS = f'''<defs>
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="4" seed="7"/>
    <feColorMatrix type="saturate" values="0"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.07"/></feComponentTransfer>
  </filter>
  <filter id="smudge"><feGaussianBlur stdDeviation="9"/></filter>
  <marker id="nib" viewBox="0 0 12 12" refX="9" refY="6" markerWidth="10"
          markerHeight="10" orient="auto-start-reverse">
    <path d="M1.5,1.5 L10.5,6 L1.5,10.5" fill="none" stroke="{CHALK}"
          stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  </marker>
  <style>
    .hand {{ font-family: Caveat, 'Segoe Script', cursive; fill: {CHALK}; }}
    .h1 {{ font-size: 44px; }} .h2 {{ font-size: 30px; }}
    .b {{ font-size: 23px; fill: {DIM}; }} .s {{ font-size: 20px; fill: {DIM}; }}
  </style>
</defs>'''
