#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Architecture diagrams in Google Cloud's own reference-architecture style.

    from gcparch import Arch
    a = Arch("Title", subtitle="one line")
    a.zone("gc", 40, 90, 1200, 480, "Google Cloud", kind="cloud")
    a.zone("vpc", 70, 150, 540, 380, "hub VPC  10.20.0.0/24", kind="vpc")
    a.node("r", 200, 300, "cloud_router.svg", "Cloud Router", "ASN 64512")
    a.flow("r", "x", "BGP", step=1)
    a.write("week-13.svg", alt="...")

Replaces the chalkboard style from week 14 onward. White ground, official
icons unmodified, grouping containers for Google Cloud / project / VPC /
region, thin grey connectors, numbered step badges.

Google's icon terms allow resize and reposition only - no recolour, no
filter, no compositing. Icons are embedded verbatim and only translated and
scaled.
"""
import os
import re

from sketchboard import ICONS, ensure_icons          # same cached icon set

# Google Cloud's documentation palette.
INK      = "#202124"      # primary text
MUTED    = "#5F6368"      # secondary text, connectors
LINE     = "#DADCE0"      # container borders
BLUE     = "#1A73E8"      # step badges, emphasis
SURFACE  = "#FFFFFF"
TINT     = "#F8F9FA"      # container fill
TINT_VPC = "#F1F3F4"

FONT = ("'DM Sans','Google Sans',Roboto,-apple-system,"
        "'Helvetica Neue',Arial,sans-serif")

KINDS = {
    #            fill       border   dash          label colour
    "cloud":   (SURFACE,   LINE,    "",            MUTED),
    "project": (TINT,      LINE,    "",            MUTED),
    "vpc":     (TINT_VPC,  "#C6CBD1", "",          MUTED),
    "region":  (SURFACE,   "#C6CBD1", "6 4",       MUTED),
    "external":(SURFACE,   "#C6CBD1", "6 4",       MUTED),
}


class Arch:
    def __init__(self, title, subtitle="", w=1280, h=720, eyebrow=""):
        ensure_icons()
        self.w, self.h = w, h
        self.title, self.subtitle, self.eyebrow = title, subtitle, eyebrow
        self.parts, self.anchors, self.panels = [], {}, []
        self.caption = {}        # node key -> bottom of its caption
        self._uid = 0

    # ---- primitives ---------------------------------------------------

    def _text(self, x, y, s, size=14, col=INK, anchor="start", weight=400,
              cls=""):
        # cls="alabel" marks a connector's own caption: it sits ON the line
        # over an opaque backing, so the crossing check must skip it.
        s = (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        c = f' class="{cls}"' if cls else ""
        self.parts.append(
            f'<text x="{x:.0f}" y="{y:.0f}"{c} font-family="{FONT}" '
            f'font-size="{size}" font-weight="{weight}" fill="{col}" '
            f'text-anchor="{anchor}">{s}</text>')

    def _icon(self, name, cx, cy, size):
        """Official icon, verbatim. Only translated and scaled."""
        self._uid += 1
        uid = f"i{self._uid}"
        src = open(os.path.join(ICONS, name), encoding="utf-8").read()
        body = src[src.index(">", src.index("<svg")) + 1: src.rindex("</svg>")]
        # Every Google icon styles itself with .cls-1/.cls-2; two in one
        # document repaint each other unless namespaced per instance.
        for cls in sorted(set(re.findall(r"cls-\d+", body)), reverse=True):
            body = body.replace(f".{cls}", f".{uid}{cls}")
            body = re.sub(rf'class="{cls}"', f'class="{uid}{cls}"', body)
        k = size / 24.0
        return (f'<g transform="translate({cx - size/2:.1f},{cy - size/2:.1f}) '
                f'scale({k:.4f})">{body}</g>')

    # ---- containers ---------------------------------------------------

    def zone(self, key, x, y, w, h, label="", kind="project", icon=None):
        """A grouping box: Google Cloud, a project, a VPC, a region."""
        fill, border, dash, lab = KINDS.get(kind, KINDS["project"])
        self.panels.append((key, x, y, w, h))
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
            f'fill="{fill}" stroke="{border}" stroke-width="1"{d}/>')
        if label:
            tx = x + 16
            if icon:
                self.parts.append(self._icon(icon, x + 26, y + 22, 18))
                tx = x + 44
            self._text(tx, y + 27, label, 13, lab, weight=500)
        self.anchors[key] = (x, y, w, h)

    # ---- nodes ---------------------------------------------------------

    def node(self, key, cx, cy, icon, label="", sublabel="", size=44):
        """A product: official icon with its name beneath."""
        self.parts.append(self._icon(icon, cx, cy, size))
        b = cy + size / 2
        if label:
            b += 20
            self._text(cx, b, label, 13.5, INK, "middle", 500)
        if sublabel:
            b += 17
            self._text(cx, b, sublabel, 12, MUTED, "middle")
        self.anchors[key] = (cx - size / 2, cy - size / 2, size, size)
        self.caption[key] = b

    def note(self, x, y, lines, col=MUTED):
        for i, ln in enumerate(lines):
            self._text(x, y + i * 19, ln, 12.5, col)

    # ---- connectors -----------------------------------------------------

    def _edge(self, key):
        x, y, w, h = self.anchors[key]
        return x + w / 2, y + h / 2, w, h

    def flow(self, a, b, label="", step=None, dashed=False, route="auto",
             lpos=0.5):
        """An orthogonal connector between two anchors, optionally numbered.

        Google's diagrams route connectors in horizontal and vertical
        segments with right-angle bends, never diagonals. `route` forces
        "h" (leave sideways first) or "v" (leave vertically first); "auto"
        picks whichever axis the two anchors are further apart on.
        """
        ax, ay, aw, ah = self._edge(a)
        bx, by, bw, bh = self._edge(b)
        dx, dy = bx - ax, by - ay
        ALIGN = 14          # treat near-aligned anchors as aligned
        SPAN = 12           # clearance inside a container's near edge

        # A node's caption hangs below its icon, so a connector leaving
        # downward has to clear it or it is drawn through the node's own name.
        down = self.caption.get(a, ay + ah / 2) + 7
        # Likewise an arrow arriving from below lands on the caption, not the
        # icon, so it stops short of it.
        upto = self.caption.get(b, by + bh / 2) + 7

        if abs(dy) <= ALIGN:                       # straight across
            x1 = ax + (aw / 2) * (1 if dx > 0 else -1)
            x2 = bx - (bw / 2) * (1 if dx > 0 else -1)
            pts = [(x1, ay), (x2, ay)]
        elif abs(dx) <= ALIGN:                     # straight down/up
            y1 = down if dy > 0 else ay - ah / 2
            y2 = by - bh / 2 if dy > 0 else upto
            pts = [(ax, y1), (ax, y2)]
        elif (route == "auto" and abs(dx) > abs(dy)
              and (by - bh / 2 + SPAN < ay < by + bh / 2 - SPAN
                   or (dy < 0 and upto >= ay))):
            x1 = ax + (aw / 2) * (1 if dx > 0 else -1)
            x2 = bx - (bw / 2) * (1 if dx > 0 else -1)
            pts = [(x1, ay), (x2, ay)]
        elif (route == "auto" and abs(dx) > abs(dy)
              and ax - aw / 2 + SPAN < bx < ax + aw / 2 - SPAN):
            x1 = ax + (aw / 2) * (1 if dx > 0 else -1)
            x2 = bx - (bw / 2) * (1 if dx > 0 else -1)
            pts = [(x1, by), (x2, by)]
        else:
            first = route if route in ("h", "v") else ("h" if abs(dx) >= abs(dy) else "v")
            if first == "h":
                x1 = ax + (aw / 2) * (1 if dx > 0 else -1)
                y2 = by - bh / 2 if dy > 0 else upto
                pts = [(x1, ay), (bx, ay), (bx, y2)]
            else:
                y1 = down if dy > 0 else ay - ah / 2
                x2 = bx - (bw / 2) * (1 if dx > 0 else -1)
                pts = [(ax, y1), (ax, by), (x2, by)]

        d = ' stroke-dasharray="5 4"' if dashed else ""
        path = "M" + " L".join(f"{x:.0f},{y:.0f}" for x, y in pts)
        self.parts.append(
            f'<path d="{path}" fill="none" stroke="{MUTED}" stroke-width="1.4" '
            f'stroke-linejoin="round" marker-end="url(#ar)"{d}/>')
        # Label the longest segment, so it never lands on a bend.
        best, blen = (pts[0], pts[1]), -1
        for p, q in zip(pts, pts[1:]):
            seg = abs(q[0] - p[0]) + abs(q[1] - p[1])
            if seg > blen:
                best, blen = (p, q), seg
        mx = best[0][0] + (best[1][0] - best[0][0]) * lpos
        my = best[0][1] + (best[1][1] - best[0][1]) * lpos
        # The label always needs a backing, badge or not: without one the
        # connector draws straight through the text.
        if step is not None:
            if label:
                lw = len(label) * 6.6 + 14
                self.parts.append(
                    f'<rect x="{mx+12:.0f}" y="{my-9:.0f}" width="{lw:.0f}" '
                    f'height="18" rx="3" fill="{SURFACE}"/>')
                self._text(mx + 19, my + 4, label, 12, MUTED, cls="alabel")
            self.parts.append(
                f'<circle cx="{mx:.0f}" cy="{my:.0f}" r="10" fill="{BLUE}"/>')
            self._text(mx, my + 4, str(step), 11.5, "#FFFFFF", "middle", 600,
                       cls="alabel")
        elif label:
            self.parts.append(
                f'<rect x="{mx-len(label)*3.3-7:.0f}" y="{my-9:.0f}" '
                f'width="{len(label)*6.6+14:.0f}" height="18" rx="3" '
                f'fill="{SURFACE}"/>')
            self._text(mx, my + 4, label, 12, MUTED, "middle", cls="alabel")

    # ---- output ----------------------------------------------------------

    def write(self, path, alt=""):
        defs = (f'<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" '
                f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                f'<path d="M0,1 L9,5 L0,9" fill="none" stroke="{MUTED}" '
                f'stroke-width="1.4"/></marker></defs>')
        head = [f'<rect width="{self.w}" height="{self.h}" fill="{SURFACE}"/>']
        y = 40
        if self.eyebrow:
            head.append(f'<text x="40" y="{y}" font-family="{FONT}" '
                        f'font-size="12" font-weight="500" fill="{MUTED}" '
                        f'letter-spacing="0.6">{self.eyebrow.upper()}</text>')
            y += 26
        head.append(f'<text x="40" y="{y}" font-family="{FONT}" font-size="21" '
                    f'font-weight="600" fill="{INK}">{self.title}</text>')
        if self.subtitle:
            head.append(f'<text x="40" y="{y+22}" font-family="{FONT}" '
                        f'font-size="13.5" fill="{MUTED}">{self.subtitle}</text>')

        # verify_fits.py reads this to test whether a label escapes the
        # container it sits in; without it that check passes on everything.
        meta = ("<metadata id=\"panels\">" + ";".join(
            f"{k}:{x},{y},{w},{h}" for k, x, y, w, h in self.panels)
            + "</metadata>") if self.panels else ""

        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" '
               f'viewBox="0 0 {self.w} {self.h}" width="{self.w}" '
               f'height="{self.h}" role="img">'
               + (f'<title>{alt}</title>' if alt else "")
               + meta + defs + "".join(head) + "".join(self.parts) + "</svg>")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(svg)
        return path
