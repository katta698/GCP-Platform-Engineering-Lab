"""Sketchnote diagram, v2 - chalk everywhere it is allowed to be.

The rule that shapes this file: Google's icon terms permit resizing and
repositioning their marks, nothing else. So no filter, no texture and no
recolour ever touches an icon. Everything that is NOT a Google product -
the board, the person, the folder, the clock, the arrows, the frames the
icons sit in - is hand-drawn chalk, which is also what makes the style
read as a chalkboard rather than as icons pasted onto a dark rectangle.
"""
import io, os, re, math, random, urllib.request, zipfile

# Google's official icon library, fetched on demand and cached - NOT vendored.
# Their terms permit using the marks in diagrams; shipping a copy of the library
# in a public repo is a different thing. One download, then .icon-cache/.
ICON_ZIP = "https://services.google.com/fh/files/misc/google-cloud-legacy-icons.zip"
ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".icon-cache")


def ensure_icons():
    """Extract the official icons once. Idempotent."""
    if os.path.isdir(ICONS) and os.listdir(ICONS):
        return
    os.makedirs(ICONS, exist_ok=True)
    print("fetching official Google Cloud icons ...")
    with urllib.request.urlopen(ICON_ZIP, timeout=180) as r:
        z = zipfile.ZipFile(io.BytesIO(r.read()))
    for n in z.namelist():
        if n.lower().endswith(".svg"):
            with open(os.path.join(ICONS, n.split("/")[-1]), "wb") as f:
                f.write(z.read(n))
    print("  cached", len(os.listdir(ICONS)), "icons")
random.seed(1111)

CHALK = "#f1eee4"
DIM = "#c3cbc0"
WARN = "#f0ad92"
GOOD = "#a6d2ae"
GOLD = "#f2d08a"


def jitter(x, y, a=1.8):
    return x + random.uniform(-a, a), y + random.uniform(-a, a)


def hand_line(x1, y1, x2, y2, col=CHALK, w=2.4, op=.92, marker=True):
    mx, my = jitter((x1 + x2) / 2, (y1 + y2) / 2, 4)
    m = ' marker-end="url(#nib)"' if marker else ""
    return (f'<path d="M{x1},{y1} Q{mx:.0f},{my:.0f} {x2},{y2}" fill="none" '
            f'stroke="{col}" stroke-width="{w}" stroke-linecap="round" '
            f'opacity="{op}"{m}/>')


def hand_rect(x, y, w, h, col=CHALK, sw=2.3, op=.6):
    """A rectangle drawn in four imperfect strokes that overshoot slightly."""
    pts = []
    c = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    for i in range(4):
        x1, y1 = c[i]
        x2, y2 = c[(i + 1) % 4]
        ox1, oy1 = jitter(x1, y1, 2.2)
        ox2, oy2 = jitter(x2, y2, 2.2)
        mx, my = jitter((x1 + x2) / 2, (y1 + y2) / 2, 2.6)
        pts.append(f'<path d="M{ox1:.0f},{oy1:.0f} Q{mx:.0f},{my:.0f} {ox2:.0f},{oy2:.0f}" '
                   f'fill="none" stroke="{col}" stroke-width="{sw}" '
                   f'stroke-linecap="round" opacity="{op}"/>')
    return "".join(pts)


def hand_circle(cx, cy, r, col=CHALK, sw=2.2, op=.5):
    """A ring that does not quite close, the way a drawn circle does not."""
    d = []
    start = random.uniform(0, .6)
    steps = 26
    sweep = 2 * math.pi * 0.97
    for i in range(steps + 1):
        a = start + sweep * i / steps
        rr = r + random.uniform(-1.6, 1.6)
        px, py = cx + rr * math.cos(a), cy + rr * math.sin(a)
        d.append(("M" if i == 0 else "L") + f"{px:.1f},{py:.1f}")
    return (f'<path d="{" ".join(d)}" fill="none" stroke="{col}" '
            f'stroke-width="{sw}" stroke-linecap="round" opacity="{op}"/>')


def icon(name, cx, cy, size, uid):
    """Official icon, unmodified: translated and scaled only."""
    src = open(os.path.join(ICONS, name), encoding="utf-8").read()
    body = src[src.index(">", src.index("<svg")) + 1: src.rindex("</svg>")]
    for cls in sorted(set(re.findall(r"cls-\d+", body)), reverse=True):
        body = body.replace(f".{cls}", f".{uid}{cls}")
        body = re.sub(rf'class="{cls}"', f'class="{uid}{cls}"', body)
    k = size / 24.0
    return (f'<g transform="translate({cx - size/2:.0f},{cy - size/2:.0f}) '
            f'scale({k:.3f})">{body}</g>')


def person(cx, cy, s=1.0, col=CHALK):
    """A chalk figure. Not a Google mark, so it may be drawn freely."""
    head = hand_circle(cx, cy - 22 * s, 11 * s, col, 2.4, .9)
    body = (f'<path d="M{cx},{cy-10*s} L{cx},{cy+16*s} M{cx-15*s},{cy+2*s} '
            f'L{cx+15*s},{cy+2*s} M{cx},{cy+16*s} L{cx-11*s},{cy+36*s} '
            f'M{cx},{cy+16*s} L{cx+11*s},{cy+36*s}" fill="none" stroke="{col}" '
            f'stroke-width="2.6" stroke-linecap="round" opacity=".9"/>')
    return head + body


def folder(x, y, w, h, col=GOLD):
    tab = (f'<path d="M{x},{y+10} L{x+4},{y} L{x+w*0.38},{y} L{x+w*0.44},{y+10}" '
           f'fill="none" stroke="{col}" stroke-width="2.4" stroke-linejoin="round" opacity=".85"/>')
    return tab + hand_rect(x, y + 10, w, h, col, 2.4, .85)


def clock(cx, cy, r, col=CHALK):
    face = hand_circle(cx, cy, r, col, 2.4, .9)
    hands = (f'<path d="M{cx},{cy} L{cx},{cy-r*0.55} M{cx},{cy} L{cx+r*0.42},{cy+r*0.2}" '
             f'fill="none" stroke="{col}" stroke-width="2.4" stroke-linecap="round" opacity=".9"/>')
    return face + hands


ensure_icons()

W, H = 1280, 820
p = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
     f'height="{H}" role="img" aria-label="A service account that holds no roles '
     f'requests a grant against a Privileged Access Manager entitlement on the '
     f'platform folder. A human approver, who is a different principal, approves. '
     f'PAM writes a temporary role binding into the folder IAM policy and removes '
     f'it about thirteen seconds after the thirty minute grant expires, at which '
     f'point the original permission denial returns.">']

p.append(f'''<defs>
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="4" seed="7"/>
    <feColorMatrix type="saturate" values="0"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.07"/></feComponentTransfer>
  </filter>
  <filter id="smudge"><feGaussianBlur stdDeviation="9"/></filter>
  <marker id="nib" viewBox="0 0 12 12" refX="9" refY="6" markerWidth="10" markerHeight="10" orient="auto-start-reverse">
    <path d="M1.5,1.5 L10.5,6 L1.5,10.5" fill="none" stroke="{CHALK}" stroke-width="1.8"
          stroke-linecap="round" stroke-linejoin="round"/>
  </marker>
  <style>
    .hand {{ font-family: Caveat, 'Segoe Script', cursive; fill: {CHALK}; }}
    .h1 {{ font-size: 44px; }} .h2 {{ font-size: 30px; }}
    .b  {{ font-size: 23px; fill: {DIM}; }} .s {{ font-size: 20px; fill: {DIM}; }}
  </style>
</defs>''')

# --- the board ---------------------------------------------------------
p.append(f'<rect width="{W}" height="{H}" fill="#30342f"/>')
p.append(f'<rect width="{W}" height="{H}" fill="#2b2f2b" opacity=".5"/>')
for _ in range(9):   # old chalk, half wiped
    cx, cy = random.uniform(60, W - 60), random.uniform(40, H - 40)
    p.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="{random.uniform(90,230):.0f}" '
             f'ry="{random.uniform(18,48):.0f}" fill="#ffffff" opacity="0.016" '
             f'filter="url(#smudge)"/>')
p.append(f'<rect width="{W}" height="{H}" filter="url(#grain)"/>')

# --- title -------------------------------------------------------------
p.append('<text x="64" y="78" class="hand h1">Access that expires on its own</text>')
p.append(hand_line(64, 96, 690, 96, CHALK, 2.6, .4, marker=False))
p.append(f'<text x="{W-64}" y="78" text-anchor="end" class="hand s" opacity=".55">'
         f'GCP Lab &#183; Week 11</text>')

# --- 1. the subject ----------------------------------------------------
p.append(hand_circle(146, 268, 54, CHALK, 2.2, .45))
p.append(icon("identity_and_access_management.svg", 146, 268, 56, "a"))
p.append('<text x="146" y="356" text-anchor="middle" class="hand h2">the subject</text>')
p.append('<text x="146" y="388" text-anchor="middle" class="hand b">a service account</text>')
p.append(f'<text x="146" y="414" text-anchor="middle" class="hand b" fill="{WARN}">holding no roles</text>')

p.append(hand_line(214, 262, 348, 248))
p.append('<text x="232" y="232" class="hand s">may ASK</text>')

# --- 2. the entitlement (no official icon exists - drawn) --------------
p.append(hand_rect(360, 176, 330, 160, CHALK, 2.4, .62))
p.append('<text x="384" y="216" class="hand h2">entitlement</text>')
p.append(f'<text x="384" y="250" class="hand b">a template, not a grant</text>')
p.append(f'<text x="384" y="282" class="hand b">roles/iam.securityReviewer</text>')
p.append(f'<text x="384" y="314" class="hand b">max 30 min &#183; needs approval</text>')
p.append(f'<text x="676" y="166" text-anchor="end" class="hand s" opacity=".6">PAM</text>')

p.append(hand_line(700, 230, 840, 230))

# --- 3. the approver (a person, drawn) ---------------------------------
p.append(person(906, 214, 1.0))
p.append('<text x="906" y="300" text-anchor="middle" class="hand h2">a human</text>')
p.append(f'<text x="906" y="330" text-anchor="middle" class="hand b" fill="{GOOD}">a DIFFERENT principal</text>')
p.append('<text x="906" y="356" text-anchor="middle" class="hand b">or it proves nothing</text>')

p.append(hand_line(906, 376, 906, 452))
p.append('<text x="922" y="420" class="hand s">approves</text>')

# --- 4. the folder policy ----------------------------------------------
p.append(folder(360, 470, 700, 126))
p.append(icon("project.svg", 418, 536, 46, "c"))
p.append('<text x="462" y="528" class="hand h2">folder IAM policy</text>')
p.append(f'<text x="462" y="562" class="hand b">a binding appears &#8212; written by PAM,</text>')
p.append(f'<text x="462" y="590" class="hand b">by nothing in the Terraform</text>')

p.append(hand_line(560, 612, 560, 690))
p.append(clock(636, 652, 26))
p.append('<text x="678" y="646" class="hand b">30 minutes pass</text>')
p.append('<text x="678" y="674" class="hand s">nobody acts</text>')

# --- 5. expiry ---------------------------------------------------------
p.append(hand_rect(360, 700, 560, 86, WARN, 2.5, .8))
p.append(f'<text x="384" y="740" class="hand h2" fill="{WARN}">the binding is gone</text>')
p.append(f'<text x="384" y="772" class="hand b">within ~13s of expiry, measured 3&#215;</text>')

p.append(hand_line(926, 744, 988, 744))
p.append('<text x="1000" y="736" class="hand b">the denial</text>')
p.append('<text x="1000" y="764" class="hand b">comes back</text>')

p.append(f'<text x="{W-64}" y="{H-24}" text-anchor="end" class="hand s" opacity=".45">'
         f'jayanthkatta.com</text>')
p.append("</svg>")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "week-11-sample.svg")
open(out, "w", encoding="utf-8").write("\n".join(p))
print("wrote", out, os.path.getsize(out), "bytes")
