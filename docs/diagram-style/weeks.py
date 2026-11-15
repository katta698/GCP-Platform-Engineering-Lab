#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One architecture diagram per week, in Google Cloud's reference style.

    python weeks.py          # regenerate all
    python weeks.py 04 13    # just these

Canvas is 960 wide to match the site's house standard: the figure fills the
post column exactly, so 12.5px type lands near 9px in that column. Widening
the page instead is the wrong half of that trade, and was tried once.

Org, folder and project are drawn as grouping CONTAINERS rather than icons,
because that is what they are in Google's own diagrams and no product icon
exists for them.
"""
import sys

from gcparch import Arch

W = 960
EYE = "GCP Platform Engineering Lab · Week %s"

# Evenly spaced column centres inside the 40..920 content area.
C3 = (187, 480, 773)
C4 = (150, 370, 590, 810)


def week_01():
    a = Arch("Landing zone: one hierarchy, built once",
             subtitle="Folders and projects created before anything runs in them",
             eyebrow=EYE % "01", w=W, h=620)
    a.zone("hcp", 40, 120, 200, 170, "HCP Terraform", kind="external")
    a.node("tf", 140, 215, "administration.svg", "terraform apply", "runs outside GCP")
    a.zone("org", 280, 96, 640, 400, "Organization — jayanthkatta.com", kind="cloud")
    a.zone("plat", 304, 146, 300, 330, "platform folder", kind="project")
    a.node("nh", 454, 220, "virtual_private_cloud.svg", "network hub", "compute, dns")
    a.node("lg", 454, 312, "cloud_logging.svg", "logging", "logging, bigquery")
    a.node("sec", 454, 404, "key_management_service.svg", "security", "kms, secretmanager")
    a.zone("work", 632, 146, 264, 196, "workloads folder", kind="project")
    # dev and prod are google_folder and nothing else: the week creates
    # the hierarchy, not what later runs in it.
    a.zone("dev", 656, 196, 216, 60, "dev — no projects yet", kind="region")
    a.zone("prod", 656, 268, 216, 60, "prod — no projects yet", kind="region")
    a.flow("tf", "plat", step=1)
    a.note(40, 546, [
        "1   Terraform runs outside Google Cloud and creates the hierarchy. Nothing pre-exists inside the organization.",
        "Each project enables only the APIs it needs, and auto_create_network is off, so no default network is ever made.",
        "The workloads folder holds the environments; the platform folder holds what every environment depends on.",
    ])
    return a, ("An organization containing a platform folder with three "
               "projects - network hub, logging and security - and a workloads "
               "folder holding dev and prod. HCP Terraform runs outside Google "
               "Cloud and creates the hierarchy.")


def week_02():
    a = Arch("Keyless CI: the issuer is public, so the condition is everything",
             subtitle="HCP mints a token per run; Google exchanges it for a short-lived one",
             eyebrow=EYE % "02", w=W, h=560)
    a.zone("ext", 40, 130, 240, 170, "HCP Terraform", kind="external")
    a.node("run", 160, 225, "administration.svg", "a run", "an OIDC token")
    a.zone("gc", 320, 96, 600, 340, "Google Cloud", kind="cloud")
    a.node("sts", 470, 225, "identity_and_access_management.svg",
           "Security Token Service", "verifies the condition")
    a.node("plan", 770, 160, "identity_and_access_management.svg", "tf-plan", "read roles")
    a.node("apply", 770, 348, "identity_and_access_management.svg", "tf-apply", "write roles")
    a.flow("run", "sts", step=1)
    a.flow("sts", "plan", step=2, route="v")
    a.flow("sts", "apply", step=3, route="v")
    a.note(40, 486, [
        "1   The attribute condition pins organization, project and workspace prefix. app.terraform.io is a PUBLIC issuer:",
        "     without it, any HCP user's validly signed token would be accepted.",
        "2-3 The token carries a run-phase claim, so a plan cannot assume the identity that can write. No key exists anywhere.",
    ])
    return a, ("An HCP Terraform run produces an OIDC token which Google's "
               "Security Token Service verifies against an attribute condition "
               "pinning the organization, project and workspace prefix. The "
               "token's run-phase claim decides whether it may assume the "
               "read-only plan identity or the write-capable apply identity.")


def week_03():
    a = Arch("Org policy: report before you refuse",
             subtitle="Every constraint runs in dry run first, and the violations land in the project log",
             eyebrow=EYE % "03", w=W, h=500)
    a.zone("org", 40, 96, 880, 260, "Organization — 4 policies, all dry run", kind="cloud")
    a.node("pol", 150, 215, "administration.svg", "Org Policy", "3 managed, 1 custom")
    a.zone("work", 330, 150, 280, 180, "workloads folder", kind="project")
    a.zone("dev", 352, 196, 236, 118, "dev — one exception", kind="region")
    a.node("proj", 470, 256, "project.svg", "a project")
    a.node("log", 790, 256, "cloud_logging.svg", "project audit log", "the violations")
    a.flow("pol", "work", step=1)
    a.flow("proj", "log", step=2)
    a.note(40, 400, [
        "1   A policy set at the organization applies to everything beneath it. An exception is set lower down, on one folder.",
        "2   Dry-run violations are written to the PROJECT log, not the organization's. Querying the org stream returns",
        "     empty with no error, which reads exactly like no violations, and is the reason to look at the project first.",
    ])
    return a, ("Four organization policies in dry run, inheriting down to the "
               "workloads folder, which contains a dev folder carrying one "
               "exception and a project beneath it. Violations are written to "
               "that project's audit log rather than the organization's.")


def week_04():
    a = Arch("Shared VPC: one network, two projects",
             subtitle="The host project owns the network; the workload project attaches to it",
             eyebrow=EYE % "04", w=W, h=520)
    a.zone("fold", 40, 96, 880, 280, "workloads folder — hierarchical firewall policy",
           kind="cloud")
    a.zone("host", 68, 150, 420, 196, "host project — network hub", kind="vpc")
    a.node("vpc", 170, 230, "virtual_private_cloud.svg", "hub VPC", "custom mode")
    a.node("sub", 370, 230, "cloud_network.svg", "subnets", "dev / prod")
    a.zone("svc", 540, 150, 352, 196, "service project", kind="project")
    a.node("vm", 716, 230, "compute_engine.svg", "e2-micro", "no external IP")
    a.flow("host", "svc", step=1)
    a.note(40, 420, [
        "1   The service project is attached to the host's Shared VPC. The workload gets addressing it does not own and",
        "     cannot change, and the firewall policy sits on the FOLDER above both projects, so neither can opt out.",
        "Creating a firewall policy and attaching it are different roles, and xpnAdmin cannot be scoped to a folder.",
    ])
    return a, ("A host project owning a custom-mode VPC with dev and prod "
               "subnets, and a service project attached to it running one "
               "e2-micro with no external address. A hierarchical firewall "
               "policy is applied at the folder above both projects.")


def week_05():
    a = Arch("Project factory: projects from a template, checked on creation",
             subtitle="A module produces the project; a custom constraint decides whether it is allowed",
             eyebrow=EYE % "05", w=W, h=470)
    a.zone("gc", 40, 96, 880, 230, "Google Cloud", kind="cloud")
    a.node("mod", C3[0], 200, "administration.svg", "Terraform module", "labels, tags, contacts")
    a.node("proj", C3[1], 200, "project.svg", "a new project", "placed in a folder")
    a.node("con", C3[2], 200, "policy_analyzer.svg", "custom constraint", "ID prefix and parent")
    a.flow("mod", "proj", step=1)
    a.flow("proj", "con", step=2)
    a.note(40, 372, [
        "1   One module supplies labels, an environment tag from a closed set, essential contacts and a deletion lien.",
        "2   The constraint is evaluated at creation. It reads resource.projectId and resource.parent, and CANNOT read",
        "     the project's labels - asking it to is rejected with Error 400, naming no field.",
    ])
    return a, ("A Terraform module produces a project carrying labels, a tag "
               "from a closed set, essential contacts and a lien. A custom "
               "organization policy constraint evaluates the project's ID "
               "prefix and parent folder when it is created.")


def week_06():
    a = Arch("Billing export: cost as a table you can query",
             subtitle="And a budget that notifies something able to act on it",
             eyebrow=EYE % "06", w=W, h=470)
    a.zone("gc", 40, 96, 880, 230, "Google Cloud", kind="cloud")
    a.node("bill", C4[0], 200, "billing.svg", "Cloud Billing", "the account")
    a.node("bq", C4[1], 200, "bigquery.svg", "BigQuery", "pricing export")
    a.node("bud", C4[2], 200, "administration.svg", "a budget", "programmatic rule")
    a.node("ps", C4[3], 200, "pubsub.svg", "Pub/Sub", "a topic")
    a.flow("bill", "bq", step=1)
    a.flow("bq", "bud", step=2)
    a.flow("bud", "ps", step=3)
    a.note(40, 372, [
        "1   A detailed export is a strict superset of a standard one. Running both stores the same rows twice, and bills twice.",
        "2-3 An email alert cannot be acted on by anything. Publishing to a topic is what makes a budget programmable,",
        "     and attaching the topic is what makes Cloud Billing write its own service agent onto it.",
    ])
    return a, ("A Cloud Billing account exporting detailed usage and pricing "
               "into BigQuery, and a budget whose programmatic rule publishes "
               "to a Pub/Sub topic rather than only sending email.")


def week_07():
    a = Arch("Asset inventory: what exists, and what changed",
             subtitle="A snapshot answers the first question; a feed answers the second",
             eyebrow=EYE % "07", w=W, h=580)
    a.zone("org", 40, 96, 880, 340, "Organization", kind="cloud")
    a.node("ci", 200, 190, "cloud_asset_inventory.svg", "Cloud Asset Inventory", "org-scoped")
    a.node("ps", 660, 190, "pubsub.svg", "a feed", "on every change")
    a.node("bq", 660, 352, "bigquery.svg", "BigQuery", "a snapshot, on demand")
    a.flow("ci", "ps", step=1)
    a.flow("ci", "bq", step=2, route="v")
    a.note(40, 482, [
        "1-2 Cloud Asset Inventory writes to both destinations AS ITSELF, not as the caller. Being owner of the destination",
        "     project is not enough and never becomes enough - its service agent needs its own grants on each one.",
        "No read-only role can read a feed: cloudasset.viewer lacks feeds.get, and only cloudasset.owner has it.",
    ])
    return a, ("Cloud Asset Inventory scoped to the organization, writing "
               "change notifications to a Pub/Sub feed and point-in-time "
               "snapshots to BigQuery. It writes to both as its own service "
               "agent rather than as the caller.")


def week_08():
    a = Arch("IAM deny: checked before allow",
             subtitle="A deny policy refuses a permission that no grant can give back",
             eyebrow=EYE % "08", w=W, h=470)
    a.zone("gc", 40, 96, 880, 230, "Google Cloud", kind="cloud")
    a.node("req", C4[0], 200, "identity_and_access_management.svg", "a request", "any principal")
    a.node("deny", C4[1], 200, "administration.svg", "deny policy", "evaluated FIRST")
    a.node("allow", C4[2], 200, "identity_and_access_management.svg", "allow policy", "roles and bindings")
    a.node("tb", C4[3], 200, "policy_analyzer.svg", "Troubleshooter", "names the rule")
    a.flow("req", "deny", step=1)
    a.flow("deny", "allow", step=2)
    a.flow("allow", "tb", step=3)
    a.note(40, 372, [
        "1   Deny is evaluated before allow, so a deny rule cannot be undone by granting a role on top of it.",
        "2   Only a request that survives the deny policy is then checked against the allow policy.",
        "3   Policy Troubleshooter v3 reports WHICH rule decided a request, rather than leaving it to be inferred.",
    ])
    return a, ("A request evaluated first against an IAM deny policy and only "
               "then against the allow policy, with Policy Troubleshooter "
               "explaining which rule decided the outcome.")


def week_09():
    a = Arch("Service account lifecycle: disable is reversible, delete is not",
             subtitle="Measure what has actually authenticated before touching anything",
             eyebrow=EYE % "09", w=W, h=490)
    a.zone("gc", 40, 96, 880, 230, "Google Cloud", kind="cloud")
    a.node("sa", C4[0], 200, "identity_and_access_management.svg", "service accounts", "every one in scope")
    a.node("aa", C4[1], 200, "policy_analyzer.svg", "Activity Analyzer", "authenticated when?")
    a.node("off", C4[2], 200, "identity_and_access_management.svg", "disabled", "not deleted")
    a.node("pol", C4[3], 200, "administration.svg", "Org Policy", "no key creation")
    a.flow("sa", "aa", step=1)
    a.flow("aa", "off", step=2)
    a.flow("off", "pol", step=3)
    a.note(40, 372, [
        "1   Activity Analyzer reports real authentication. An account that looks dormant may not be - one here had",
        "     authenticated days earlier, and a list of unused accounts is a guess until it has been measured.",
        "2-3 A deleted account's email can be reused, but IAM tracks an internal unique ID, so old bindings never apply",
        "     to the replacement: the rebuild looks identical and behaves differently. Disable instead, and block keys.",
    ])
    return a, ("Every service account in scope measured with Activity Analyzer "
               "for real authentication, then the ones that have never "
               "authenticated and hold no role are disabled rather than "
               "deleted, with key creation blocked by organization policy.")


def week_10():
    a = Arch("Group-based access: the role belongs to the group",
             subtitle="Access appears and disappears with membership, and nothing else changes",
             eyebrow=EYE % "10", w=W, h=500)
    a.zone("ci", 40, 130, 230, 160, "Cloud Identity", kind="external")
    a.node("grp", 155, 206, "identity_and_access_management.svg", "an access group", "holds the role")
    a.zone("gc", 310, 96, 610, 260, "Google Cloud", kind="cloud")
    a.node("sa", 440, 206, "identity_and_access_management.svg", "service account", "holds nothing")
    a.zone("fold", 610, 150, 286, 170, "platform folder", kind="project")
    a.node("log", 753, 226, "cloud_logging.svg", "logs", "logging.viewer")
    a.flow("sa", "grp", step=1)
    a.flow("grp", "fold", step=2)
    a.note(40, 402, [
        "1   The service account holds no role of its own. Every permission it has is a consequence of being a member.",
        "2   The role is bound to the GROUP, at the folder. Removing the member removes the access, with no IAM edit",
        "     and no Terraform run. Groups are parented to a customer, not an organization - searching by org returns zero.",
    ])
    return a, ("A service account holding no roles directly is a member of a "
               "Cloud Identity group, and that group holds logging.viewer on "
               "the platform folder, so the account can read logs only while "
               "the membership exists.")


def week_11():
    a = Arch("Just-in-time access: a role requested, held briefly, and lost",
             subtitle="The folder's IAM policy is unchanged until a grant is approved",
             eyebrow=EYE % "11", w=W, h=500)
    a.zone("gc", 40, 96, 880, 260, "Google Cloud", kind="cloud")
    a.node("sub", 150, 215, "identity_and_access_management.svg", "a subject", "holds nothing")
    a.node("pam", 370, 215, "security_command_center.svg", "an entitlement", "a template, not a grant")
    a.node("appr", 580, 215, "administration.svg", "an approver", "a different human")
    a.zone("fold", 700, 150, 196, 170, "platform folder", kind="project")
    a.node("bind", 798, 226, "identity_and_access_management.svg", "a binding", "expires by itself")
    a.flow("sub", "pam", step=1)
    a.flow("pam", "appr", step=2)
    a.flow("appr", "fold", step=3)
    a.note(40, 402, [
        "1   An entitlement is a TEMPLATE. Until a grant is approved the folder's IAM policy is completely unchanged.",
        "2   Requester and approver are different people, or the approval step is a form filled in twice by one person.",
        "3   The binding appears in the folder's policy, is written by no Terraform, and disappears ~13s after it expires.",
    ])
    return a, ("A subject service account holding no roles requests elevation "
               "through a Privileged Access Manager entitlement on the platform "
               "folder. A separate human approves, a temporary IAM binding "
               "appears in the folder's policy, and it disappears by itself "
               "when the grant expires.")


def week_12():
    a = Arch("Secret management: two things called rotation",
             subtitle="One of them creates new material; the other publishes a message",
             eyebrow=EYE % "12", w=W, h=470)
    a.zone("gc", 40, 96, 880, 230, "Google Cloud — security project", kind="cloud")
    a.node("key", C4[0], 200, "key_management_service.svg", "Cloud KMS key", "rotates itself")
    a.node("sec", C4[1], 200, "secret_manager.svg", "the secret", "CMEK, 1h schedule")
    a.node("ps", C4[2], 200, "pubsub.svg", "Pub/Sub", "SECRET_ROTATE")
    a.node("fn", C4[3], 200, "cloud_functions.svg", "a rotator", "~50 lines you write")
    a.flow("key", "sec", step=1)
    a.flow("sec", "ps", step=2)
    a.flow("ps", "fn", step=3)
    a.note(40, 372, [
        "1   Disabling this key makes the secret unreadable in 2-70s, without touching the secret or one IAM binding.",
        "2   Secret Manager's rotation schedule publishes a message and stops. No new version. No value change.",
        "3   The rotator is the component Google does not ship. Without it the schedule rotates nothing, forever.",
    ])
    return a, ("A Cloud KMS key encrypting a Secret Manager secret that carries "
               "a one-hour rotation schedule. When the schedule fires it "
               "publishes a SECRET_ROTATE message to Pub/Sub and does nothing "
               "else; a Cloud Run function subscribed to that topic is what "
               "actually adds a new secret version.")


def week_13():
    a = Arch("Hybrid connectivity with HA VPN and BGP",
             subtitle="Two networks, two tunnels, and routing the two sides negotiate between themselves",
             eyebrow=EYE % "13", w=W, h=490)
    a.zone("gc", 40, 96, 880, 250, "Google Cloud", kind="cloud")
    a.zone("hub", 64, 140, 392, 186, "hub VPC — 10.20.0.0/24", kind="vpc")
    a.zone("br", 504, 140, 392, 186, "branch VPC — 10.30.0.0/24", kind="vpc")
    a.node("hr", 150, 212, "cloud_router.svg", "Cloud Router", "ASN 64512")
    a.node("hgw", 370, 212, "cloud_vpn.svg", "HA VPN gateway", "2 interfaces")
    a.node("bgw", 590, 212, "cloud_vpn.svg", "HA VPN gateway", "2 interfaces")
    a.node("brr", 810, 212, "cloud_router.svg", "Cloud Router", "ASN 64513")
    a.flow("hgw", "bgw", step=1)
    a.flow("hr", "hgw", step=2)
    a.flow("brr", "bgw", step=3)
    a.note(40, 392, [
        "1   Two tunnels, interface 0 to interface 0 and 1 to 1. A single active interface carries no availability SLA.",
        "2-3 Each Cloud Router advertises its own subnet over BGP and installs whatever the other side advertises.",
        "When a tunnel drops, the routes learned through it are withdrawn in 3.1–3.6s and the survivor carries the traffic.",
    ])
    return a, ("Two VPC networks inside Google Cloud, each with an HA VPN "
               "gateway and a Cloud Router on its own BGP ASN. Two IPsec "
               "tunnels join the gateways. Each router advertises its own "
               "subnet and installs what the other advertises, so neither side "
               "is configured with a static route. When one tunnel drops the "
               "routes learned through it are withdrawn in about three seconds "
               "and the surviving tunnel carries the traffic.")


WEEKS = {"01": week_01, "02": week_02, "03": week_03, "04": week_04,
         "05": week_05, "06": week_06, "07": week_07, "08": week_08,
         "09": week_09, "10": week_10, "11": week_11, "12": week_12,
         "13": week_13}

if __name__ == "__main__":
    for n in (sys.argv[1:] or sorted(WEEKS)):
        arch, alt = WEEKS[n]()
        print("  wrote", arch.write(f"week-{n}.svg", alt=alt))
