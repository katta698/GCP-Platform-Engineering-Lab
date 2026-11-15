"""Week 11's diagram, at the proportions Jay approved on 2026-10-30.

That approval was a 1280x820 board at type_scale 1.0 - small text against a
large board, lots of air. Two later edits broke it: a denser layout squeezed
to 1060, then a type_scale of 1.18 to chase mobile legibility. Both made the
lettering chunkier, which is what "the font is bigger" meant.

The lesson: he approved PROPORTIONS, not a word count. Changing the canvas
changes the proportions even when the font sizes stay the same.
"""
from sketchboard import Board

b = Board("Access expires on its own", eyebrow="GCP Lab · Week 11",
          w=1280, h=820, type_scale=1.0)

b.icon_node("subject", 150, 266, "identity_and_access_management.svg", r=54,
            title="the subject",
            lines=["a service account", ("holding no roles", "warn")])

b.panel("ent", 372, 178, 396, 164, title="entitlement", corner="PAM",
        lines=["a template, not a grant",
               "roles/iam.securityReviewer",
               "max 30 min, needs approval"])

b.person("human", 918, 206, title="a human",
         lines=[("a DIFFERENT principal", "good")])

b.folder("policy", 372, 486, 660, 126, icon_file="project.svg",
         title="folder IAM policy",
         lines=["a binding appears — written by PAM"])

b.panel("gone", 372, 700, 540, 86, col="#f0ad92",
        title="the binding is gone",
        lines=["within ~13s of expiry, 3 trials"])

b.arrow("subject", "ent", "may ASK")
b.arrow("ent", "human")
b.arrow("human", "policy", "approves", side="v")
b.arrow("policy", "gone")
b.clock(1000, 672, 26, note=["30 min passes,", "nobody acts"])

b.write("week-11-post.svg",
    alt="A service account holding no roles requests a grant against a "
        "Privileged Access Manager entitlement on the platform folder. A human "
        "approver, a different principal, approves. PAM writes a temporary role "
        "binding into the folder IAM policy and removes it about thirteen "
        "seconds after the thirty minute grant expires.")
print("wrote week-11-post.svg")
