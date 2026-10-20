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

## Validate the MediaStream fixes

Run **Validate patched WebKit and cache** (`validate.yml`) manually in Actions.
`validation-source.json` pins the fork separately from the daily upstream source:
currently `monadix/WebKit` at `5a93a3c53026915ae609c5a821b2ba9e15244d07` on
branch `eng/gstreamer-hidden-mediastream`. The updater does not modify this pin.

That fork commit contains the audio-only MediaStream fix and its two API tests,
so `validation.nix` builds it without a package-local patch for this change. An
audio-only MediaStream now reports readiness when its live GStreamer pipeline
reaches `PAUSED`, the same point at which other live streams already do;
previously such a stream stayed in `HaveNothing`, so a `play()` whose asynchronous
media-session admission completed before the pipeline's first state notification
paused the bootstrapping pipeline and never resumed. The change does not affect
`paused()`, video first-frame readiness or non-MediaStream behavior. Its two
API tests are described below.

The workflow has two jobs:

1. **build** has 350 minutes to build the runtime, headers, three GLib API test
   executables and their fixtures. It exports their complete Nix runtime closure
   to a compressed GitHub artifact, retained for one day. It does not upload to
   Cachix. Export and upload share the build job's time budget.
2. **test-and-cache** has a separate 60-minute budget. It imports that exact
   closure and runs the hidden-muted-playback, audio-only-playback and
   audio-only-startup-pause MediaStream cases, existing page visibility, mute and
   autoplay cases, and mock getUserMedia permission checks under Xvfb with
   software rendering. Each case has a two-minute timeout; crashes,
   skipped/missing cases and assertions fail validation. Logs are kept as a
   GitHub artifact for 14 days. Only success uploads runtime and headers to
   `luakit-hardened` and updates
   `webkitgtk-4.1-libwebrtc-validation-x86_64-linux` with `--keep-revisions 3`.

The two new cases execute the pinned engine rather than inspecting it. Both
build a live audio-only MediaStream from a WebAudio destination, wait for the
element's `loadstart` event, and then block the page main thread for one second,
keeping queued state notifications and the media-session admission continuation
from running while backend work can proceed. `loadstart` is queued immediately
before the resource load that creates the MediaStream pipeline, so awaiting it
guarantees the backend load call has run; a synchronous delay at the same point
would only postpone the queued load. `audio-only-playback` requires the
element's exposed timeline to advance (`currentTime > 0`), the `playing` event, a
fulfilled `play()`, and `readyState >= HAVE_FUTURE_DATA`.
`audio-only-startup-pause` blocks the same way, requires the same timeline
advance, calls `pause()`, and requires the pending `play()` promise to settle
(fulfilment or rejection) while the element stays paused with its exposed
timeline frozen.

MediaStream `currentTime` is synthetic: monotonic time since `play()` or the
cached paused time, not sink position or rendered samples. The timeline checks
are therefore behavioral element checks; they do not show that the backend
started, rendered, or stopped.

Whether an engine without the fix fails these cases depends on event ordering:
the media-session admission continuation must pause the pipeline before its queued
`PLAYING` state notification is dispatched. That ordering has not been observed,
so the cases can under-detect an engine without the fix and, until the negative
control below has run, only exercise the pinned engine. A pass on the pinned
engine does not depend on that ordering, because readiness is published inside
the load task before `play()`.

The runner upranks GStreamer's fake audio sink
(`GST_PLUGIN_FEATURE_RANK=fakeaudiosink:max`) and fakes a two-channel output, as
the upstream API test runner does, because both cases play a live audio track.
The runner executes the test executables directly instead of through
`run-api-tests`, so it sets those variables itself.

### Negative control for the startup cases

A control needs the same tests compiled against an engine with only the fix
reverted. That cannot reuse the normal validation build, because it requires a
full engine build with the developer-mode API tests, so this is a manual CI
procedure on a throwaway branch and source pin rather than part of the routine
workflow:

1. Create a throwaway branch from the pinned fork commit.
2. On that branch, keep the `TestWebKitMediaStream.cpp` tests and their
   registration, and revert only the fix hunks in
   `MediaPlayerPrivateGStreamer.cpp` and `.h`. Commit and push that control
   branch to the fork. Do not add a package-local patch: the control commit
   itself carries the reverted engine, and the tests remain in the pinned
   source.
3. On a throwaway repository branch, point `validation-source.json` at the
   control commit with its real source hash, using the same sparse checkout as
   the normal pin. Keep the `DEVELOPER_MODE`, `ENABLE_API_TESTS` and test bundle
   wiring in `validation.nix` unchanged, so the same tests compile against the
   reverted engine.
4. In `validation-runner.nix`, select only
   `/webkit/WebKitMediaStream/audio-only-playback`, require the TAP result
   `not ok 1 /webkit/WebKitMediaStream/audio-only-playback`, and skip the Cachix
   push and pin steps. Only a completed run of that case failing its own
   assertions is valid evidence; reject `ok 1`, a skipped or missing case, a
   crash, an unrelated setup failure, or the runner's own `timeout` termination,
   because none of those show the regression.
5. Dispatch `validate.yml` on that branch with media logging enabled (WebCore
   media and GStreamer categories). Its build and test jobs run the same tests
   against the reverted engine in the same GLib environment.
6. Expected result: `not ok 1 …` from the test's own assertion. Confirm from
   those logs that the pipeline reached `PLAYING` and hit the failing order: the
   admission pause while the pipeline is playing (`updatePlayState …
   shouldBePlaying = 0, playerPaused = 0`, `Changing state from PLAYING to
   PAUSED`) before the queued `Changed state from PAUSED to PLAYING`.
   `currentTime` is synthetic and cannot serve as this evidence. A missing
   `loadstart`, no backend pipeline, or a pipeline that never requested `PLAYING`
   is a setup failure, not control evidence. If the case is `ok 1`, the failing
   ordering was not hit and these cases are not a regression guard.

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
focused API run does not replace upstream EWS or a real Telemost call with camera
and incoming audio.
