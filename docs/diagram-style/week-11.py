"""Week 11's diagram, as a spec. Compare with render_sketch_diagram.py, the
hand-positioned prototype this replaces."""
from sketchboard import Board

b = Board("Access that expires on its own", eyebrow="GCP Lab · Week 11")

b.icon_node("subject", 150, 266, "identity_and_access_management.svg",
            title="the subject",
            lines=["a service account", ("holding no roles", "warn")])

b.panel("ent", 372, 178, 342, 164, title="entitlement", corner="PAM",
        lines=["a template, not a grant",
               "roles/iam.securityReviewer",
               "max 30 min · needs approval"])

b.person("human", 918, 214, title="a human",
         lines=[("a DIFFERENT principal", "good"), "or it proves nothing"])

b.folder("policy", 372, 470, 700, 126, icon_file="project.svg",
         title="folder IAM policy",
         lines=["a binding appears — written by PAM,",
                "by nothing in the Terraform"])

b.panel("gone", 372, 700, 560, 86, col="#f0ad92",
        title="the binding is gone",
        lines=["within ~13s of expiry, measured 3×"])

b.arrow("subject", "ent", "may ASK")
b.arrow("ent", "human")
b.arrow("human", "policy", "approves")
b.arrow("policy", "gone")

b.clock(1000, 648, 26, note=["30 minutes pass", "nobody acts"])
b.note(968, 736, ["the denial", "comes back"])

out = b.write("week-11-sample.svg",
    alt="A service account holding no roles requests a grant against a "
        "Privileged Access Manager entitlement on the platform folder. A human "
        "approver, a different principal, approves. PAM writes a temporary role "
        "binding into the folder IAM policy and removes it about thirteen "
        "seconds after the thirty minute grant expires, at which point the "
        "original permission denial returns.")
print("wrote", out)
