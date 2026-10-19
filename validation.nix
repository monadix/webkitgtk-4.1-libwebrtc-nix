{
  callPackage,
  patchelf,
}:
let
  webkit = callPackage ./package.nix {
    source = builtins.fromJSON (builtins.readFile ./validation-source.json);
  };
in
webkit.overrideAttrs (old: {
  outputs = old.outputs ++ [ "testBundle" ];
  nativeBuildInputs = old.nativeBuildInputs ++ [ patchelf ];
  # GLib API tests use private symbols hidden by the production symbol map.
  cmakeFlags = old.cmakeFlags ++ [
    "-DDEVELOPER_MODE=ON"
    "-DENABLE_API_TESTS=ON"
    "-DENABLE_LAYOUT_TESTS=OFF"
    "-DENABLE_MINIBROWSER=OFF"
    "-DENABLE_THUNDER=OFF"
    "-DCMAKE_COMPILE_WARNING_AS_ERROR=OFF"
  ];
  # Tests run in a separate CI job against these same installed outputs.
  doCheck = false;
  postPatch = (old.postPatch or "") + ''
    # Developer mode probes this directory, but the sparse source omits benchmark data.
    rm -rf PerformanceTests
    # Exclude unrelated API executables from the default build/install target.
    substituteInPlace Tools/CMakeLists.txt \
      --replace-fail 'add_subdirectory(TestWebKitAPI)' 'add_subdirectory(TestWebKitAPI EXCLUDE_FROM_ALL)'
    # These three paths cannot be overridden through the test environment.
    substituteInPlace Tools/TestWebKitAPI/glib/CMakeLists.txt \
      --replace-fail 'WEBKIT_SRC_DIR="''${CMAKE_SOURCE_DIR}"' "WEBKIT_SRC_DIR=\"$testBundle/share/webkit-api\"" \
      --replace-fail 'WEBKIT_TEST_WEB_PROCESS_EXTENSIONS_DIR="''${TEST_LIBRARY_DIR}"' "WEBKIT_TEST_WEB_PROCESS_EXTENSIONS_DIR=\"$testBundle/lib\"" \
      --replace-fail 'WEBKIT_TEST_RESOURCES_DIR="''${TEST_RESOURCES_DIR}"' "WEBKIT_TEST_RESOURCES_DIR=\"$testBundle/share/webkit-api\""
  '';
  postBuild = (old.postBuild or "") + ''
    ninja -j"$NIX_BUILD_CORES" TestWebKitMediaStream TestWebKitWebView TestUIClient
  '';
  postInstall = (old.postInstall or "") + ''
    mkdir -p "$testBundle/bin" "$testBundle/lib" "$testBundle/share/webkit-api/Tools/TestWebKitAPI/Tests/JavaScriptCore/glib"
    cp bin/TestWebKitAPI/WebKitGTK/{TestWebKitMediaStream,TestWebKitWebView,TestUIClient} "$testBundle/bin/"
    cp lib/WebKitGTKAPITests/libWebProcessExtensionTest.so "$testBundle/lib/"
    cp bin/TestWebKitAPI/WebKitGTK/resources/webkitglib-tests-resources.gresource "$testBundle/share/webkit-api/"
    cp -r ../Tools/TestWebKitAPI/Resources "$testBundle/share/webkit-api/Tools/TestWebKitAPI/"
    cp ../Tools/TestWebKitAPI/Tests/JavaScriptCore/glib/script.js \
      "$testBundle/share/webkit-api/Tools/TestWebKitAPI/Tests/JavaScriptCore/glib/"
    # CMake does not install these executables, so preserve a runtime library
    # search path before the normal Nix RPATH shrinking hook removes build paths.
    for binary in "$testBundle"/bin/* "$testBundle"/lib/*.so; do
      patchelf --set-rpath "$out/lib:$(patchelf --print-rpath "$binary")" "$binary"
    done
  '';
})
