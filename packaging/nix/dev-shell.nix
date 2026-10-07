{ pkgs }:
let
  schemaPath = pkgs.lib.concatStringsSep ":" [
    "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
    "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
  ];
  gstPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" [
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
  ];
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    cargo
    rustc
    cargo-tauri
    nodejs
    git
    patchelf
    libcap
    wrapGAppsHook4
  ];
  buildInputs = with pkgs; [
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
  shellHook = ''
    export XDG_DATA_DIRS="${schemaPath}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPath}''${GST_PLUGIN_SYSTEM_PATH_1_0:+:$GST_PLUGIN_SYSTEM_PATH_1_0}"
    export LD_LIBRARY_PATH="${
      pkgs.lib.makeLibraryPath [ pkgs.libpcap ]
    }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export GIO_EXTRA_MODULES="${pkgs.glib-networking}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"
  '';
}
