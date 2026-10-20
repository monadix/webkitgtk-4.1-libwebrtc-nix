{
  lib,
  writeShellApplication,
  webkit,
  xvfb-run,
  dbus,
  coreutils,
  gnugrep,
  fontconfig,
  dejavu_fonts,
  makeFontsConf,
  mesa,
  gtk3,
  glib-networking,
  gst_all_1,
}:
writeShellApplication {
  name = "webkit-validation-tests";
  runtimeInputs = [
    xvfb-run
    dbus
    coreutils
    gnugrep
  ];
  text = ''
    export WEBKIT_EXEC_PATH=${webkit}/libexec/webkit2gtk-4.1
    export WEBKIT_INJECTED_BUNDLE_PATH=${webkit}/lib/webkit2gtk-4.1/injected-bundle
    export WEBKIT_INSPECTOR_RESOURCES_PATH=${webkit}/share
    export WEBKIT_GST_ALLOW_PLAYBACK_OF_INVISIBLE_VIDEOS=0
    # The audio-only MediaStream cases render real audio. Select the fake audio
    # sink and fake a two-channel output, as the upstream API test runner does,
    # so neither case opens a sound device.
    export GST_PLUGIN_FEATURE_RANK=fakeaudiosink:max
    export WEBKIT_GST_MAX_NUMBER_OF_AUDIO_OUTPUT_CHANNELS=2
    export GDK_BACKEND=x11
    export LIBGL_ALWAYS_SOFTWARE=1
    export LIBGL_DRIVERS_PATH=${mesa}/lib/dri
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}
    export FONTCONFIG_PATH=${fontconfig.out}/etc/fonts
    export XDG_DATA_DIRS=${gtk3}/share/gsettings-schemas/${gtk3.name}
    export GIO_EXTRA_MODULES=${glib-networking}/lib/gio/modules
    export GST_PLUGIN_SYSTEM_PATH_1_0=${
      lib.makeSearchPath "lib/gstreamer-1.0" (
        map lib.getLib (
          with gst_all_1;
          [
            gstreamer
            gst-plugins-base
            gst-plugins-good
            gst-plugins-bad
            gst-plugins-ugly
            gst-libav
          ]
        )
      )
    }
    export XDG_RUNTIME_DIR
    XDG_RUNTIME_DIR=$(mktemp -d)
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    logs=''${VALIDATION_LOG_DIR:-validation-logs}
    mkdir -p "$logs"
    status=0
    run_test() {
      local binary=$1 path=$2 log
      log="$logs/$binary-''${path##*/}.log"
      # A timeout, assertion, crash, skipped case, or empty test selection fails.
      if ! timeout --kill-after=10s 120s xvfb-run -a \
        ${webkit.testBundle}/bin/"$binary" --tap -p "$path" 2>&1 | tee "$log"; then
        status=1
      elif ! grep -Fx "ok 1 $path" "$log" > /dev/null; then
        status=1
      fi
    }
    run_test TestWebKitMediaStream /webkit/WebKitMediaStream/hidden-muted-playback
    run_test TestWebKitMediaStream /webkit/WebKitMediaStream/audio-only-playback
    run_test TestWebKitMediaStream /webkit/WebKitMediaStream/audio-only-startup-pause
    run_test TestWebKitWebView /webkit/WebKitWebView/page-visibility
    run_test TestWebKitWebView /webkit/WebKitWebView/is-audio-muted
    run_test TestWebKitWebView /webkit/WebKitWebView/autoplay-policy
    run_test TestUIClient /webkit/WebKitWebView/usermedia-permission-requests
    exit "$status"
  '';
}
