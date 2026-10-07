{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.a2tools-dps-meter;
  name = "a2tools-dps-meter";
  wrapper = "${config.security.wrapperDir}/${name}";
  srcs = import ./lib.nix { inherit lib; };

  # "github": the source of the flake input a2tools-src (pinned upstream).
  # "local":  cfg.localSource, i.e. your working checkout with uncommitted edits.
  githubPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  localPackage = srcs.buildLocal pkgs {
    path = cfg.localSource;
    ignore = cfg.localSourceIgnore;
  };

  # Ensure the desktop entry goes through the capability wrapper too.
  desktop = pkgs.makeDesktopItem {
    name = "A2Tools DPS Meter";
    desktopName = "A2Tools DPS Meter";
    comment = "AION2 combat analysis";
    exec = wrapper;
    icon = name;
    terminal = false;
    categories = [
      "Game"
      "Utility"
    ];
  };

  # Use our explicit desktop entry instead of depending on Tauri's generated
  # Exec field or on the graphical launcher's PATH ordering.
  installed = pkgs.symlinkJoin {
    name = "a2tools-dps-meter-installed";
    paths = [ cfg.package ];
    postBuild = ''
      rm -rf "$out/share/applications"
      mkdir -p "$out/share/applications"
      cp ${desktop}/share/applications/*.desktop "$out/share/applications/"
    '';
  };
in
{
  options.programs.a2tools-dps-meter = {
    enable = lib.mkEnableOption "A2Tools DPS Meter with packet capture";

    source = lib.mkOption {
      type = lib.types.enum [
        "github"
        "local"
      ];
      default = "github";
      description = ''
        Which A2Tools source to build: <literal>github</literal> uses the
        untouched upstream revision fetched by the flake input
        <optionname>a2tools-src</optionname>, <literal>local</literal> builds
        <option>programs.a2tools-dps-meter.localSource</option> (this
        repository, modifications included).
      '';
    };

    localSource = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/home/synopia/Projects/1_Privat/A2Tools-DPS-Meter";
      description = ''
        Absolute path to the local checkout used when
        <option>source</option> is <literal>local</literal>. It is a string so
        that Nix does not copy the directory unfiltered; the copy is pruned by
        <option>programs.a2tools-dps-meter.localSourceIgnore</option>.
      '';
    };

    localSourceIgnore = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "docs" ];
      description = ''
        Extra file or directory names to prune from the local checkout, on top
        of the defaults (${lib.concatStringsSep ", "} srcs.localSourceDefaults).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = if cfg.source == "local" && cfg.localSource != "" then localPackage else githubPackage;
      description = "Packaged meter, including its GTK/WebKit runtime wrapper.";
    };

    captureUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "synopia" ];
      description = "Existing local users allowed to capture game traffic.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optionals (cfg.source == "local" && cfg.localSource == "") [
      ''
        programs.a2tools-dps-meter.localSource must be set when
        programs.a2tools-dps-meter.source is "local"; the GitHub source is
        being used instead.
      ''
    ];

    environment.systemPackages = [ installed ];

    users.groups.a2tools-capture = { };
    users.users = lib.genAttrs cfg.captureUsers (_: {
      extraGroups = [ "a2tools-capture" ];
    });

    # NixOS creates a capability-bearing C wrapper in /run/wrappers/bin.
    # It propagates the capability in the ambient set through the package's
    # shell launcher to the ELF executable. No setcap on a store file/script.
    security.wrappers.${name} = {
      source = "${cfg.package}/bin/${name}";
      owner = "root";
      group = "a2tools-capture";
      permissions = "u+rx,g+rx,o-rwx";
      capabilities = "cap_net_raw+ep";
    };
  };
}
