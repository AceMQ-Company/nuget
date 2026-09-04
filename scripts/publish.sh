#!/usr/bin/env bash
#
# Adds packages to the feed and regenerates its indexes.
#
#   ./scripts/publish.sh path/to/AceMq.Amqp.0.1.0.nupkg [...]
#   ./scripts/publish.sh                 # regenerate indexes only
#
# There is no server and no credentials: the feed is a directory tree that a
# NuGet client walks by convention, exactly as the Maven repository is. To
# publish, run this and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${ACEMQ_NUGET_BASE:-https://acemq.org/nuget}"

cd "$ROOT"
python3 - "$BASE_URL" "$@" <<'PY'
import base64, hashlib, json, os, re, shutil, sys, zipfile

base = sys.argv[1].rstrip("/")
container = os.path.join("v3", "flatcontainer")


def identity(nupkg):
    """The id and version a client will look this package up by."""
    with zipfile.ZipFile(nupkg) as z:
        name = next(n for n in z.namelist()
                    if n.endswith(".nuspec") and "/" not in n)
        xml = z.read(name).decode("utf-8")
        return (re.search(r"<id>([^<]+)</id>", xml).group(1),
                re.search(r"<version>([^<]+)</version>", xml).group(1),
                z.read(name))


for nupkg in sys.argv[2:]:
    pid, version, nuspec = identity(nupkg)
    # Every flat-container URL is lowercased by the client. A file stored under
    # its original casing is a 404, and the failure looks like a missing package
    # rather than a naming mistake.
    lid, lver = pid.lower(), version.lower()
    d = os.path.join(container, lid, lver)
    os.makedirs(d, exist_ok=True)

    shutil.copyfile(nupkg, os.path.join(d, f"{lid}.{lver}.nupkg"))
    with open(os.path.join(d, f"{lid}.nuspec"), "wb") as f:
        f.write(nuspec)
    with open(nupkg, "rb") as f:
        digest = base64.b64encode(hashlib.sha512(f.read()).digest()).decode()
    with open(os.path.join(d, f"{lid}.{lver}.nupkg.sha512"), "w") as f:
        f.write(digest)
    print(f"added {pid} {version}")


def sortkey(v):
    """Order versions numerically, and a prerelease below its release."""
    core, _, pre = v.partition("-")
    parts = [int(p) if p.isdigit() else 0 for p in core.split(".")]
    return (parts, pre == "", pre)


ids = sorted(d for d in os.listdir(container)
             if os.path.isdir(os.path.join(container, d))) if os.path.isdir(container) else []

for pid in ids:
    versions = sorted((v for v in os.listdir(os.path.join(container, pid))
                       if os.path.isdir(os.path.join(container, pid, v))), key=sortkey)
    with open(os.path.join(container, pid, "index.json"), "w") as f:
        json.dump({"versions": versions}, f, indent=2)
        f.write("\n")

# PackageBaseAddress is the one resource a host with no server can provide, and
# it is all that restore needs. Search, package details and push are absent by
# construction, which is what the README documents rather than apologises for.
with open("index.json", "w") as f:
    json.dump({
        "version": "3.0.0",
        "resources": [{
            "@id": f"{base}/v3/flatcontainer/",
            "@type": "PackageBaseAddress/3.0.0",
            "comment": "Package content (.nupkg) and the version list for each id.",
        }],
    }, f, indent=2)
    f.write("\n")

listed = []
for pid in ids:
    versions = json.load(open(os.path.join(container, pid, "index.json")))["versions"]
    # The nuspec of the newest version carries the name and blurb to show.
    newest = versions[-1]
    nuspec = os.path.join(container, pid, newest, f"{pid}.nuspec")
    name, description = pid, ""
    if os.path.exists(nuspec):
        xml = open(nuspec, encoding="utf-8").read()
        m = re.search(r"<id>([^<]+)</id>", xml)
        if m:
            name = m.group(1)
        m = re.search(r"<description>([^<]*)</description>", xml, re.S)
        if m:
            description = " ".join(m.group(1).split())
    listed.append((name, newest, versions, description))

# The landing page's package list is generated, because a hand-written one goes
# stale on the first release and then quietly misinforms every visitor.
def escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace('"', "&quot;"))


if listed:
    rows = []
    for name, newest, versions, description in listed:
        older = ""
        if len(versions) > 1:
            older = ("<br><span style=\"font-size:.85em\">also " +
                     ", ".join(escape(v) for v in reversed(versions[:-1])) + "</span>")
        rows.append(
            "    <tr><td><code>{0}</code></td><td>{1}{2}</td><td>{3}</td></tr>".format(
                escape(name), escape(newest), older, escape(description)))
    block = ("  <table>\n"
             "    <tr><th>Package</th><th>Version</th><th></th></tr>\n"
             + "\n".join(rows) + "\n  </table>")
else:
    block = ("  <div class=\"card\">\n"
             "    <p><strong>Empty for now.</strong> The feed and its tooling work and are tested,\n"
             "       but nothing has been published to it yet.</p>\n  </div>")

page = "index.html"
if os.path.exists(page):
    html = open(page, encoding="utf-8").read()
    start, end = "<!-- packages:start", "<!-- packages:end -->"
    i, j = html.find(start), html.find(end)
    if i != -1 and j != -1:
        head = html[:i] + "<!-- packages:start -- written by scripts/publish.sh; do not edit by hand -->\n"
        open(page, "w", encoding="utf-8").write(head + block + "\n  " + html[j:])
        print(f"index.html lists {len(listed)} package(s)")
    else:
        print("index.html has no packages block; leaving it alone")

count = sum(len(v[2]) for v in listed)
print(f"feed at {base}: {len(ids)} package id(s), {count} version(s)")
PY
