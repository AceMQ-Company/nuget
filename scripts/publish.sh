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

count = sum(len(json.load(open(os.path.join(container, p, "index.json")))["versions"])
            for p in ids)
print(f"feed at {base}: {len(ids)} package id(s), {count} version(s)")
PY
