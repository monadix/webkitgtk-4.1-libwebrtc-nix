# WebKitGTK 4.1 with LibWebRTC

A pinned development WebKitGTK build for GTK3 applications such as Luakit.
It retains the `webkit2gtk-4.1` API and Nixpkgs sandbox mounts, adapting their
patch to WebKit's UTF-8 string API. It adds NASM, libevent, ALSA and Opus, and
enables `ENABLE_WEB_RTC` without enabling all experimental features. A small
CMake patch exposes the bundled libvpx headers to LibWebRTC on Linux. The
validation package pins a published fork commit that fixes audio-only
MediaStream startup and adds its two API tests. Currently targets
`x86_64-linux`.

`source.json` pins WebKit's commit, source hash, version and date. `flake.lock`
pins Nixpkgs separately; daily WebKit updates leave Nixpkgs unchanged.

Check the package without compiling it:

```sh
nix flake check --no-build
nix develop --command actionlint
nix develop --command shellcheck scripts/update.sh
```

Build the runtime and headers intended for the binary cache:

```sh
nix build .#cache
```

`packages.x86_64-linux.default` and `packages.x86_64-linux.webkitgtk_4_1`
expose the WebKit package itself. `packages.x86_64-linux.cache` references its
runtime and development outputs, excluding separate debug symbols and docs
from the upload. WebKit still builds its normal outputs locally.

## Use with Home Manager

After publishing this repository, add it as a flake input, then pass its
package to Luakit's existing override:

```nix
inputs.webkit-dev.url = "github:monadix/webkitgtk-4.1-libwebrtc-nix";

# In a scope where the webkit-dev input is available:
luakit = pkgs.luakit.override {
  webkitgtk_4_1 = webkit-dev.packages.${pkgs.stdenv.hostPlatform.system}.default;
};
```

Preserve any existing Luakit `overrideAttrs` changes after this override.
Consume the exported package to match CI's dependency graph; making this
input's Nixpkgs follow another input can cause a cache miss and a local rebuild.

## Binary cache

The public cache is [luakit-hardened](https://luakit-hardened.cachix.org).
The flake advertises its URL and public signing key through `nixConfig`;
accept those settings when Nix prompts, or use `--accept-flake-config`.

Flake-input cache settings are not inherited by a consuming Home Manager or
NixOS flake. Add this to your NixOS configuration to use the cache there:

```nix
nix.settings = {
  extra-substituters = [ "https://luakit-hardened.cachix.org" ];
  extra-trusted-public-keys = [
    "luakit-hardened.cachix.org-1:x3DEaKNb//17n1vH+96ucQ7U9k6e5IuDogF22zZKEPI="
  ];
};
```

On other systems, add the equivalent settings to the Nix daemon's `nix.conf`.
Downloading these public binaries does not require an authentication token.

See [CI setup and retention](docs/ci.md) for daily updates, build workflows,
cache configuration, rollback behavior and the manual fork validation workflow.
