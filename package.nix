{
  lib,
  replaceVars,
  addDriverRunpath,
  webkitgtk_4_1,
  fetchgit,
  nasm,
  libevent,
  alsa-lib,
  libopus,
}:
let
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
webkitgtk_4_1.overrideAttrs (oldAttrs: {
  version = "${source.version}-unstable-${source.date}";
  src = fetchgit {
    url = "https://github.com/WebKit/WebKit.git";
    inherit (source) rev hash;
    fetchSubmodules = false;
    # Keep this identical to scripts/update.sh's prefetch selection.
    sparseCheckout = [
      "Source"
      "Tools"
      "CMakeLists.txt"
    ];
    nonConeMode = true;
  };
  patches =
    map (
      patch:
      if lib.getName patch == "fix-bubblewrap-paths.patch" then
        replaceVars ./fix-bubblewrap-paths.patch {
          inherit (builtins) storeDir;
          inherit (addDriverRunpath) driverLink;
        }
      else
        patch
    ) oldAttrs.patches
    ++ [ ./libwebrtc-vpx-include.patch ];
  nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ nasm ];
  buildInputs = oldAttrs.buildInputs ++ [
    libevent
    alsa-lib
    libopus
  ];
  cmakeFlags = oldAttrs.cmakeFlags ++ [ "-DENABLE_WEB_RTC=ON" ];
})
