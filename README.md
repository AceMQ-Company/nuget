# AceMQ NuGet feed

A static NuGet v3 feed at **<https://acemq.org/nuget/index.json>**, served from
GitHub Pages. No server, no account, no credentials — the same arrangement as the
[Maven repository](https://github.com/AceMQ-Company/maven), for the same reason:
a package source should not be something you have to be let into.

> **Empty.** The feed and its tooling work, and are tested, but nothing is
> published yet. [AceMQ for .NET](https://github.com/AceMQ-Company/acemq-dotnet-amqp)
> currently implements the message envelope and nothing else — it cannot send a
> message, so there is no package worth shipping. This exists so that publishing
> the first one is a single command rather than an afternoon.

## Using it

Add the source to a `nuget.config` beside your solution:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="acemq" value="https://acemq.org/nuget/index.json" />
  </packageSources>
</configuration>
```

Then reference packages normally:

```bash
dotnet add package AceMq.Amqp --version 0.1.0
```

## What works, and what does not

The NuGet v3 protocol defines four resources as required: `PackageBaseAddress`,
`RegistrationsBaseUrl`, `SearchQueryService` and `PackagePublish`. Three of those
need a server that can answer queries or accept uploads. A static host can serve
only `PackageBaseAddress` — the flat container — and this feed publishes exactly
that resource and no others.

That is enough for the operations that matter, which was verified rather than
assumed:

| | |
|---|---|
| `dotnet restore`, `dotnet build` | works |
| `dotnet add package` with an explicit version | works |
| Floating versions such as `1.*` | works — resolved from the flat container's version index |
| `dotnet package search` | **fails**: `The source does not have a Search service!` |
| Browsing the feed in Visual Studio's package manager UI | **not available** — it needs the search resource |
| `dotnet nuget push` | **not available** — see below |
| `dotnet tool install` | **fails** with a NullReferenceException — see below |

### Installing a tool from this feed

`dotnet tool install --add-source https://acemq.org/nuget/index.json` dies with an
unhandled `NullReferenceException`. The tool installer wants resources a static feed
does not have, and unlike `dotnet package search` it crashes rather than saying so.

`--add-source` alone is not the fix either: it *adds to* the configured sources, so
the feed is still queried. Download the package and install with a `--configfile`
that names only the local folder:

```bash
curl -fsSLO https://acemq.org/nuget/v3/flatcontainer/acemq.amqp.devcerts/0.1.6/acemq.amqp.devcerts.0.1.6.nupkg
cat > tool.config <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources><clear />
  <add key="local" value="." />
</packageSources></configuration>
XML
dotnet tool install -g AceMq.Amqp.DevCerts --version 0.1.6 --configfile tool.config
```

Ordinary `PackageReference` restores are unaffected.

So a project that names its packages and versions restores and builds against this
feed exactly as it would against nuget.org. What it cannot do is *discover*
packages here. That is the same trade the Maven repository makes, and the same one
it has been fine with.

## Publishing

There is no push endpoint, because a static host cannot accept an upload. Adding a
package is a commit:

```bash
./scripts/publish.sh path/to/AceMq.Amqp.0.1.0.nupkg
git add -A && git commit -m "Publish AceMq.Amqp 0.1.0" && git push
```

The script reads the id and version out of the `.nuspec` inside the package, files
it into the flat container under the lowercased names a client will ask for,
writes the `.nuspec` and `.sha512` alongside it, and regenerates the version
indexes and the service index. Run with no arguments, it regenerates the indexes
and touches nothing else.

Versions are ordered numerically rather than lexically, so `0.2.10` sorts above
`0.2.9`, and a prerelease sorts below the release it precedes.

## Layout

```
index.json                                      the service index
v3/flatcontainer/{id}/index.json                every version of {id}
v3/flatcontainer/{id}/{version}/{id}.{version}.nupkg
v3/flatcontainer/{id}/{version}/{id}.nuspec
v3/flatcontainer/{id}/{version}/{id}.{version}.nupkg.sha512
```

Ids and versions are lowercase throughout. NuGet lowercases them when building a
URL, so a file stored under its original casing is a 404 — and the failure reads
as a missing package rather than as a naming mistake, which is why the script owns
the naming instead of leaving it to whoever publishes.

## Not nuget.org

For the same reason these packages are not on Maven Central: publishing there is
permanent, and the package identifiers are still settling. This feed is where
things live until 1.0.

The feed URL is recorded in exactly one place — the `@id` in `index.json`, which
`scripts/publish.sh` writes from `ACEMQ_NUGET_BASE`. If the feed moves to a .NET
domain later, that is the one value that changes.
