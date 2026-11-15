"""Week 11's diagram, sized for reading INLINE in the post.

Narrower canvas and a bigger type scale than the gallery sample: inline, this
is read at the content width - about 358px on a phone, where the plain SVG it
replaces rendered its labels at 4.1px.
"""
from sketchboard import Board

b = Board("Access expires on its own", eyebrow="",
          w=1120, h=740, type_scale=1.00)

b.icon_node("subject", 160, 240, "identity_and_access_management.svg", r=44,
            title="the subject",
            lines=["a service account", ("holding no roles", "warn")])

b.panel("ent", 330, 150, 318, 178, title="entitlement", corner="PAM",
        lines=["a template,", "not a grant", "max 30 min"])

b.person("human", 830, 168, title="a human",
         lines=[("a DIFFERENT", "good"), ("principal", "good")])

b.folder("policy", 286, 430, 520, 118, icon_file="project.svg",
         title="folder IAM policy",
         lines=["a binding appears — PAM wrote it"])

b.panel("gone", 286, 616, 448, 92, col="#f0ad92",
        title="the binding is gone",
        lines=["within ~13s of expiry, 3 trials"])

b.arrow("subject", "ent", "may ASK")
b.arrow("ent", "human")
b.arrow("human", "policy", "approves", side="v")
b.arrow("policy", "gone")
b.clock(866, 606, 22, note=["30 min passes,", "nobody acts"])

b.write("week-11-natural.svg",
    alt="A service account holding no roles requests a grant against a "
        "Privileged Access Manager entitlement on the platform folder. A human "
        "approver, a different principal, approves. PAM writes a temporary role "
        "binding into the folder IAM policy and removes it about thirteen "
        "seconds after the thirty minute grant expires.")
print("wrote week-11-post.svg")
