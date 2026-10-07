{
  lib,
  rustPlatform,
  importNpmLock,
  cargo-tauri,
  nodejs,
  pkg-config,
  wrapGAppsHook4,
  makeWrapper,
  patchelf,
  glib,
  gtk3,
  gsettings-desktop-schemas,
  glib-networking,
  librsvg,
  webkitgtk_4_1,
  openssl,
  libpcap,
  gst_all_1,
  src,
}:
let
  manifest = builtins.fromJSON (builtins.readFile (src + "/package.json"));
  schemaPath = lib.concatStringsSep ":" [
    "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}"
    "${gtk3}/share/gsettings-schemas/${gtk3.name}"
  ];
  gstPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];
in
rustPlatform.buildRustPackage {
  pname = "a2tools-dps-meter";
  inherit (manifest) version;
  inherit src;

  # The inspected Cargo.lock has only registry dependencies. These two
  # importers use the integrity checksums from the upstream lockfiles.
  cargoLock.lockFile = src + "/src-tauri/Cargo.lock";
  npmDeps = importNpmLock { npmRoot = src; };

  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";
  tauriBundleType = "deb";

  nativeBuildInputs = [
    cargo-tauri.hook
    nodejs
    importNpmLock.npmConfigHook
    pkg-config
    wrapGAppsHook4
    makeWrapper
    patchelf
  ];

  buildInputs = [
    glib
    gtk3
    gsettings-desktop-schemas
    glib-networking
    librsvg
    webkitgtk_4_1
    openssl
    libpcap
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];

  # Tauri's hook runs `npm run build`, builds the Rust application, and
  # extracts the deb payload (binary, icons, desktop file, game data).
  # Debian maintainer scripts are NOT executed; NixOS grants capabilities.

  # Keep Cargo unit tests enabled, using the same production feature that
  # Tauri enables when embedding the frontend.
  cargoTestFlags = [ "--lib" ];
  cargoCheckFeatures = [ "tauri/custom-protocol" ];

  # Wrap explicitly AFTER fixup: the RPATH shrinker otherwise drops libpcap,
  # since the application loads it with dlopen rather than a DT_NEEDED entry.
  dontWrapGApps = true;
  postFixup = ''
    patchelf --add-rpath "${lib.makeLibraryPath [ libpcap ]}" \
      "$out/bin/a2tools-dps-meter"

    wrapProgram "$out/bin/a2tools-dps-meter" \
      "''${gappsWrapperArgs[@]}" \
      --prefix XDG_DATA_DIRS : "${schemaPath}" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gstPath}"
  '';

  meta = {
    description = "Native Linux AION2 DPS meter and combat overlay";
    homepage = "https://github.com/taengu/A2Tools-DPS-Meter";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "a2tools-dps-meter";
  };
}
