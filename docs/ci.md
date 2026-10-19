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

## Validate the hidden MediaStream fix

Run **Validate patched WebKit and cache** (`validate.yml`) manually in Actions.
`validation-source.json` pins the fork separately from the daily upstream source:
currently `monadix/WebKit` at `ae6c8020421750a3078ae823321df0e4183dc703`.
The updater does not modify this pin.

The workflow has two jobs:

1. **build** has 350 minutes to build the runtime, headers, three GLib API test
   executables and their fixtures. It exports their complete Nix runtime closure
   to a compressed GitHub artifact, retained for one day. It does not upload to
   Cachix. Export and upload share the build job's time budget.
2. **test-and-cache** has a separate 60-minute budget. It imports that exact
   closure and runs the new hidden-muted-playback regression, existing page
   visibility, mute and autoplay cases, and mock getUserMedia permission checks
   under Xvfb with software rendering. Each case has a two-minute timeout;
   crashes, skipped/missing cases and assertions fail validation. Logs are kept
   as a GitHub artifact for 14 days. Only success uploads runtime and headers to
   `luakit-hardened` and updates
   `webkitgtk-4.1-libwebrtc-validation-x86_64-linux` with `--keep-revisions 3`.

The validation pin protects three successful **validation** versions separately
from the daily pin's three upstream versions. The same garbage-collection rules
above apply. Test binaries, fixtures, debug symbols and build dependencies are
excluded from the Cachix root. The temporary GitHub artifact includes the test
runner's full runtime dependencies, so it can be substantially larger than the
WebKit binary alone. Retry failed test jobs within one day; after artifact
expiry rerun the entire workflow.

`validation.nix` uses WebKit's `DEVELOPER_MODE` to expose the private symbols
needed by its GLib API tests. It retains Release compilation, disables layout
runners, MiniBrowser and Thunder, and builds only the three selected API test
executables. The packaged test fixtures and library paths refer to installed
Nix outputs so they survive transfer to another runner. The daily default
package keeps its existing production configuration.

For the equivalent local build and test:

```sh
nix build .#validation-cache .#validation-run-tests --no-link
runner=$(nix path-info .#validation-run-tests)
"$runner/bin/webkit-validation-tests"
```

After CI succeeds, use `packages.x86_64-linux.validation` in the Luakit override
in place of `default`, locked to the repository revision tested by the workflow.
This selects the same development-mode runtime tested and cached by CI. This
focused API run does not replace upstream EWS or a real Telemost camera call.
