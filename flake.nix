{
  description = "Development WebKitGTK 4.1 (GTK3) with LibWebRTC";

  nixConfig = {
    extra-substituters = [ "https://luakit-hardened.cachix.org" ];
    extra-trusted-public-keys = [
      "luakit-hardened.cachix.org-1:x3DEaKNb//17n1vH+96ucQ7U9k6e5IuDogF22zZKEPI="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      webkit = pkgs.callPackage ./package.nix { };
    in
    {
      packages.${system} = {
        default = webkit;
        webkitgtk_4_1 = webkit;
        # One cache pin protects both the runtime and downstream build headers.
        cache = pkgs.linkFarm "webkitgtk-4.1-libwebrtc-cache" [
          {
            name = "out";
            path = webkit.out;
          }
          {
            name = "dev";
            path = webkit.dev;
          }
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          git
          jq
          nix-prefetch-git
          actionlint
          shellcheck
        ];
      };
    };
}
