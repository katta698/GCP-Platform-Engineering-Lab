"""Every GCP lab week's architecture diagram, declared as a spec.

Run: python weeks.py          (writes week-NN.svg for each)
     python weeks.py 03       (just one)

Each diagram says the same thing its predecessor said - the aria-labels were
lifted from the existing SVGs so nothing silently changes meaning.

Rules this file follows, all of them learned the hard way:

  * 1280x820 at type_scale 1.0. That is the proportion that was approved:
    small text on a large board. Shrinking the canvas makes text bigger
    relative to everything even when the font sizes do not change, which is
    what made two earlier attempts look wrong.
  * Official Google icons only for Google products, placed untouched. People,
    folders, clocks, boxes and arrows are drawn. If a product has no icon,
    draw a panel - do not improvise a mark.
  * Few elements. These are read at 696px in a post column; detail belongs in
    the prose and the validation table.
  * Short captions. A line that outgrows its panel is the most common defect
    here, and verify_fits.py now catches it.
"""
import sys

from sketchboard import Board

W, H = 1280, 820


def week_01():
    b = Board("One hierarchy, built once", eyebrow="GCP Lab · Week 1", w=W, h=H)
    b.panel("org", 96, 150, 380, 108, title="organization",
            lines=["from a domain you own"])
    b.panel("plat", 96, 356, 380, 150, title="platform", corner="folder",
            lines=["network · logging", "security"])
    b.panel("work", 96, 584, 380, 150, title="workloads", corner="folder",
            lines=["dev · prod", "where policy attaches"])
    b.icon_node("proj", 760, 250, "project.svg", r=54, title="projects",
                lines=["IAM, quota, billing", "free, so separate freely"])
    b.panel("hcp", 860, 600, 330, 140, title="HCP Terraform",
            lines=["state lives outside", "Google Cloud"])
    b.arrow("org", "plat")
    b.arrow("plat", "work")
    b.arrow("plat", "proj", "contains")
    b.arrow("hcp", "proj", "builds")
    b.note(96, 770, [("no API creates an organization — that step is a web form", "warn")])
    return b, ("GCP landing zone: organization with platform and workloads "
               "folders, platform projects, and HCP Terraform managing state")


def week_02():
    b = Board("The issuer is public", eyebrow="GCP Lab · Week 2", w=W, h=H)
    b.panel("hcp", 80, 196, 268, 136, title="HCP Terraform",
            lines=["mints one OIDC", "token per run"])
    b.panel("cond", 500, 170, 380, 190, title="attribute condition", corner="the boundary",
            lines=["organization name", "project name", "workspace prefix"])
    b.icon_node("sts", 1090, 250, "identity_and_access_management.svg", r=52,
                title="STS", lines=["exchanges the token"])
    b.panel("plan", 330, 540, 300, 126, title="tf-plan",
            lines=["read-only roles"])
    b.panel("apply", 760, 540, 300, 126, title="tf-apply", col="#f2d08a",
            lines=["write roles"])
    b.arrow("hcp", "cond", "signs")
    b.arrow("cond", "sts")
    b.arrow("sts", "apply", "phase = apply", side="v")
    b.arrow("cond", "plan", "phase = plan", side="v")
    b.note(140, 748, [("app.terraform.io signs tokens for EVERY customer", "warn"),
                      ("no key exists — org policy refuses to create one", "good")])
    return b, ("Token flow: HCP Terraform mints an OIDC token, the attribute "
               "condition gates it, Google STS exchanges it for a federated "
               "token, which impersonates a plan or apply service account")


def week_03():
    b = Board("Report before you refuse", eyebrow="GCP Lab · Week 3", w=W, h=H)
    b.panel("org", 96, 160, 420, 220, title="organization", corner="all DRY RUN",
            lines=["requireOsLogin", "blockProjectSshKeys", "disableSerialPortAccess",
                   "requireTerraformLabels"])
    b.panel("exc", 96, 470, 420, 130, title="workloads / dev", col="#f2d08a",
            lines=["one exception, scoped"])
    b.icon_node("log", 920, 250, "cloud_logging.svg", r=54, title="the PROJECT log",
                lines=["where violations land"])
    b.panel("note", 680, 520, 500, 160, title="not the organization log",
            col="#f0ad92",
            lines=["that stream does not exist,", "and querying it returns empty", "with no error at all"])
    b.arrow("org", "exc", "inherits down")
    b.arrow("org", "log", "logs to")
    b.note(96, 700, [("7 constraints were already enforced before any of this", "warn"),
                     "list shows what is SET, --effective shows what is ENFORCED"])
    return b, ("Four policies are set at the organization in dry run: three "
               "managed Compute constraints and one custom bucket-label "
               "constraint. The workloads/dev folder carries a deliberate "
               "exception that disables the serial port constraint. Violations "
               "are logged to the project audit log, not the organization's.")


def week_04():
    b = Board("One network, two projects", eyebrow="GCP Lab · Week 4", w=W, h=H)
    b.panel("host", 96, 170, 430, 200, title="host project", corner="Shared VPC",
            lines=["custom-mode VPC", "dev + prod subnets"])
    b.icon_node("vm", 900, 470, "compute_engine.svg", r=54, title="one e2-micro",
                lines=[("no external IP", "good")])
    b.panel("svc", 96, 470, 430, 150, title="service project",
            lines=["attached to the host"])
    b.panel("fw", 660, 650, 500, 140, title="firewall policy", col="#f2d08a",
            lines=["on the workloads folder", "IAP in, everything else out"])
    b.arrow("host", "svc", "attaches")
    b.arrow("svc", "vm", "runs")
    b.note(96, 680, [("created and attached are", "warn"), "different things — only the",
                     "association does anything"])
    return b, ("A host project owns a custom-mode VPC with two subnets. A "
               "service project in the workloads folder attaches to it, and its "
               "virtual machine draws an address from the host's dev subnet with "
               "no external IP. A hierarchical firewall policy attached to the "
               "workloads folder allows IAP ingress on port 22.")


def week_05():
    b = Board("Projects from a template", eyebrow="GCP Lab · Week 5", w=W, h=H)
    b.panel("mod", 96, 190, 360, 180, title="the module", corner="Terraform",
            lines=["labels · env tag", "essential contacts", "no default network"])
    b.icon_node("proj", 760, 250, "project.svg", r=56, title="a project",
                lines=["same shape every time"])
    b.panel("con", 420, 520, 460, 180, title="custom constraint", col="#f2d08a",
            lines=["checks the id prefix", "and the parent folder", "in DRY RUN"])
    b.arrow("mod", "proj", "produces")
    b.arrow("proj", "con", "evaluated by", side="v")
    b.note(96, 560, [("a tag is not a label", "warn"), "one is a value from a", "closed set; policy reads it"])
    return b, ("A module produces a project inside a folder, carrying labels, an "
               "environment tag from a closed set, essential contacts and no "
               "default network. Separately a custom organization policy "
               "constraint evaluates project creation against the project id "
               "prefix and parent, in dry run.")


def week_06():
    b = Board("Cost as a table you can query", eyebrow="GCP Lab · Week 6", w=W, h=H)
    b.icon_node("bill", 150, 250, "billing.svg", r=54, title="billing account",
                lines=["the thing that pays"])
    b.icon_node("bq", 700, 210, "bigquery.svg", r=54, title="BigQuery",
                lines=["usage rows, asked in SQL"])
    b.panel("budget", 96, 520, 380, 160, title="a budget", col="#f2d08a",
            lines=["watches spend", "publishes thresholds"])
    b.icon_node("ps", 900, 580, "pubsub.svg", r=52, title="Pub/Sub",
                lines=["threshold events"])
    b.arrow("bill", "bq", "exports to")
    b.arrow("bill", "budget", side="v")
    b.arrow("budget", "ps", "notifies")
    b.note(96, 712, [("attaching the topic needed a project-scoped", "warn"),
                     "exception to domain restricted sharing"])
    return b, ("The billing account exports usage rows to BigQuery, where cost "
               "questions are answered as SQL. Separately a budget watches spend "
               "and publishes threshold events to a Pub/Sub topic. Attaching the "
               "topic requires a project-scoped exception to the domain "
               "restricted sharing constraint.")


def week_07():
    b = Board("What exists, and what changed", eyebrow="GCP Lab · Week 7", w=W, h=H)
    b.icon_node("assets", 250, 290, "cloud_asset_inventory.svg", r=56,
                title="the assets", lines=["every resource, every policy"])
    b.icon_node("ps", 820, 180, "pubsub.svg", r=52, title="a feed",
                lines=["changes, as they happen"])
    b.icon_node("bq", 820, 520, "bigquery.svg", r=52, title="a snapshot",
                lines=["the whole inventory, in SQL"])
    b.arrow("assets", "ps", "notifies")
    b.arrow("assets", "bq", "exports")
    b.note(96, 640, [("both are written by Google's", "warn"),
                     "Cloud Asset service agent —", "not by the caller"])
    return b, ("The organization's assets feed two destinations. A feed publishes "
               "change notifications to a Pub/Sub topic. A snapshot export writes "
               "the full inventory to BigQuery, where the audit runs as SQL. Both "
               "destinations are written by Google's Cloud Asset service agent, "
               "not by the caller.")


def week_08():
    b = Board("Deny is checked first", eyebrow="GCP Lab · Week 8", w=W, h=H)
    b.panel("req", 96, 170, 320, 130, title="a request",
            lines=["delete an asset feed"])
    b.panel("deny", 470, 150, 360, 180, title="deny policy", col="#f0ad92",
            corner="evaluated FIRST",
            lines=["before any allow policy", "is even read"])
    b.panel("stop", 470, 450, 360, 130, title="tf-plan: denied", col="#f0ad92",
            lines=["no role can override it"])
    b.panel("pass", 470, 650, 360, 130, title="tf-apply: exempt", col="#a6d2ae",
            lines=["and a break-glass human"])
    # No caption on this node: the arrow reaching it has to pass exactly where
    # a caption would sit, and moving the node only moved the problem.
    b.icon_node("allow", 1100, 690, "identity_and_access_management.svg", r=44,
                title="allow policy")
    b.arrow("req", "deny")
    b.arrow("deny", "stop", side="v")
    b.arrow("pass", "allow", "reaches")
    b.note(96, 420, [("a deny rule outranks", "warn"), "every role you hold"])
    b.note(930, 300, ["only here are", "roles evaluated"])
    return b, ("A request to delete an asset feed is checked against the deny "
               "policy first. The plan identity is denied. The apply identity and "
               "a break-glass human are exempted and reach the allow policy, "
               "where their roles are evaluated.")


def week_09():
    b = Board("Disable is reversible. Delete is not.",
              eyebrow="GCP Lab · Week 9", w=W, h=H)
    b.icon_node("sa", 236, 260, "identity_and_access_management.svg", r=54,
                title="every service account", lines=["in the organization"])
    b.panel("recent", 560, 150, 420, 140, title="authenticated recently?",
            col="#a6d2ae", lines=["keep it"])
    b.panel("role", 560, 380, 420, 150, title="holds any role?",
            lines=["never authenticated,", "but still granted — keep"])
    b.panel("off", 560, 620, 420, 140, title="holds none: disable",
            col="#f2d08a", lines=["reversible, and it is"])
    b.arrow("sa", "recent")
    b.arrow("recent", "role", side="v")
    b.arrow("role", "off", side="v")
    b.note(140, 520, [("deletion is NOT done in this lab", "warn"),
                      "a deleted account's id", "can never be reused"])
    return b, ("A decision applied to every service account: if it authenticated "
               "recently, keep it; if it never authenticated, check whether it "
               "holds any role; if it holds none, disable it, which is "
               "reversible. Deletion is not done in this lab.")


def week_10():
    b = Board("The role belongs to the group", eyebrow="GCP Lab · Week 10",
              w=W, h=H)
    b.icon_node("sa", 150, 250, "identity_and_access_management.svg", r=52,
                title="a service account", lines=[("holds no roles", "warn")])
    b.panel("grp", 470, 170, 360, 150, title="an access group",
            lines=["holds logging.viewer", "on the platform folder"])
    b.panel("folder", 420, 470, 460, 150, title="platform folder", col="#f2d08a",
            lines=["contains the logging project"])
    b.icon_node("logs", 1060, 540, "cloud_logging.svg", r=50, title="its logs",
                lines=["readable — for now"])
    b.arrow("sa", "grp", "member of")
    b.arrow("grp", "folder", side="v")
    b.arrow("folder", "logs")
    b.note(96, 700, [("access appears and disappears with", "good"),
                     "membership and nothing else"])
    return b, ("A service account that holds no roles of its own is a member of a "
               "group. The group holds roles/logging.viewer on the platform "
               "folder. The folder contains the logging project, so the service "
               "account can read its logs only for as long as the membership "
               "exists.")


def week_12():
    b = Board("Two things called rotation", eyebrow="GCP Lab · Week 12",
              w=W, h=H)
    b.icon_node("key", 160, 220, "key_management_service.svg", r=52,
                title="our KMS key",
                lines=[("rotates itself", "good")])
    b.icon_node("secret", 600, 220, "secret_manager.svg", r=52,
                title="the secret")
    b.icon_node("topic", 1060, 220, "pubsub.svg", r=50, title="a topic",
                lines=[("mandatory", "warn")])
    b.icon_node("fn", 840, 610, "cloud_functions.svg", r=50,
                title="a rotator you write",
                lines=[("~50 lines", "good")])
    b.arrow("key", "secret", "encrypts")
    b.arrow("secret", "topic", "publishes")
    b.arrow("topic", "fn", side="v")
    b.arrow("fn", "secret", "adds a version")
    b.note(96, 690, [("the schedule only notifies —", "warn"),
                     "without the function, nothing rotates"])
    return b, ("A Cloud KMS key encrypts a Secret Manager secret. The key "
               "rotates itself on a schedule, creating a new key version with "
               "no code involved. The secret's own rotation schedule only "
               "publishes a message to a Pub/Sub topic; a Cloud Functions "
               "rotator subscribed to that topic is what actually adds a new "
               "secret version. Without the function the secret never changes.")


WEEKS = {"01": week_01, "02": week_02, "03": week_03, "04": week_04,
         "05": week_05, "06": week_06, "07": week_07, "08": week_08,
         "09": week_09, "10": week_10, "12": week_12}

if __name__ == "__main__":
    want = sys.argv[1:] or sorted(WEEKS)
    for n in want:
        board, alt = WEEKS[n]()
        path = board.write(f"week-{n}.svg", alt=alt)
        print(f"  wrote {path}")
