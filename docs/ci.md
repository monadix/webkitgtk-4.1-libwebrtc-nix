# CI and Cachix

## Setup

Publish the repository with `main` as its default branch. Configure these under
GitHub Settings → Secrets and variables → Actions. The cache name is pinned to
`luakit-hardened` in the build workflow; its URL is
`https://luakit-hardened.cachix.org`. CI pins its public signing key in the
Nix installer settings; [client configuration](../README.md#binary-cache)
uses the same key.

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `CACHIX_AUTH_TOKEN` | A token allowed to read pins, push and pin paths in `luakit-hardened` |
| Variable, optional | `BUILD_RUNNER` | Runner label; defaults to `ubuntu-24.04` |

The update workflow needs permission to push commits to the default branch.
Branch protection must allow its bot to push, or updates will fail at that step.
No personal GitHub token is required: it calls the reusable build workflow
explicitly after pushing, since `GITHUB_TOKEN` pushes do not trigger push workflows.

## Updates and builds

`update.yml` runs daily at 03:17 UTC (06:17 Moscow time), or manually.
The hour is arbitrary; minute 17 avoids the start-of-hour load
[documented by GitHub](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
Midnight Moscow would use `0 21 * * *`; midnight UTC would use `0 0 * * *`.
The updater resolves WebKit's latest `main` commit, uses `nix-prefetch-git` to fetch and hash the same
sparse checkout as the package, and extracts the upstream version and commit
date. An unchanged commit is a no-op. A changed pin is evaluated without
compilation before it is committed, then passed to `build.yml`.

`build.yml` also runs on package changes pushed to `main`, or manually. It builds
only this package's cache root, uploads it, and updates the Cachix pin only after
a successful upload. Build jobs are serialized to avoid competing pin updates.
A failed build leaves the previous pin protected, but the repository branch can
point at a newer, unbuilt commit; keep consumers locked to a known successful
commit until its build has succeeded.

Update the Nixpkgs dependency separately when wanted:

```sh
nix flake update nixpkgs
```

For local source updates:

```sh
nix develop --command bash scripts/update.sh
nix flake check --no-build
```

The build workflow uses two compiler jobs and allows 350 minutes, within
GitHub's six-hour hosted job limit. It removes unused preinstalled SDKs on
GitHub-hosted runners to free disk space. The first build still needs substantial
RAM, temporary disk space and compilation time. A standard public Linux runner
has 4 CPUs and 16 GB RAM; the private-repository equivalent has 2 CPUs and 8 GB.
Use a larger runner label through `BUILD_RUNNER` if the standard runner cannot
finish within its memory, disk or time budget. Runtime CI compilation has not
been exercised by the local evaluation-only checks.

[GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [job limits](https://docs.github.com/en/actions/reference/limits).

## Keep three successful versions

The workflow uses one persistent pin name:

```sh
cachix pin "$CACHIX_CACHE_NAME" webkitgtk-4.1-libwebrtc-x86_64-linux \
  "$cache_root" --keep-revisions 3
```

Before creating a pin revision, the workflow reads the current pin through the
[Cachix API](https://app.cachix.org/api/v1/) and skips repinning the same healthy
cache root. Retrying the current build therefore does not consume another
retention slot.

Its cache root references both the runtime and headers. Reusing that pin name
keeps the latest three revisions protected; creating a separate permanent pin
for every version would defeat that limit. Git tags are not needed for cache
retention. Git history and consumers' flake locks identify previous source pins.

**Three protected revisions is not a hard limit of three physically stored
versions.** Older revisions become eligible for Cachix garbage collection.
Cachix evicts unprotected paths by access/creation age when enforcing the cache's
storage limit, so older binaries can remain until space is needed. No dashboard
setting is required for the three-revision pin rule: the workflow sends it to
Cachix after each new successful build. Your Cachix storage
quota must have room for the protected closures; their compressed size needs
measuring after successful builds. A byte quota is not a three-version deletion
rule. Other pins and uploads in `luakit-hardened` share that storage quota.

Only the successful runtime/development closure is explicitly uploaded. The
workflow disables automatic uploads of build outputs so source checkouts,
debug symbols and intermediate build dependencies do not accumulate in Cachix.
The service avoids duplicating paths already present in the upstream NixOS cache.

Sources: [Cachix pin retention](https://docs.cachix.org/pins),
[Cachix garbage collection](https://docs.cachix.org/garbage-collection),
[Cachix Action options](https://github.com/cachix/cachix-action).
