# Source-selection helpers, shared by flake.nix and module.nix.
#
# Two sources are supported:
#   * the pristine upstream tree fetched by the flake input `a2tools-src`
#   * a mutable local checkout (your working copy, uncommitted edits included)
{ lib }:
rec {
  # Names pruned when a local checkout is copied into the Nix store. These are
  # gigabytes of build artifacts here, and the build regenerates them anyway.
  # `.cargo` is here because `ide-env.sh --cargo` writes a gitignored
  # src-tauri/.cargo/config.toml whose `[env] ... force = true` entries would
  # otherwise clobber PKG_CONFIG_PATH inside the sandbox with HOST store paths
  # that are not inputs of the derivation (javascriptcore-rs-sys then fails).
  localSourceDefaults = [
    ".cargo"
    ".git"
    ".idea"
    ".vscode"
    "node_modules"
    "dist"
    "dist-ssr"
    "target"
    "result"
  ];

  # Copy a local checkout into the store, keeping only what the build needs.
  # `path` is a STRING on purpose: a path literal would be copied unfiltered.
  fetchLocal =
    {
      path,
      ignore ? [ ],
    }:
    let
      pruned = localSourceDefaults ++ ignore;
    in
    builtins.path {
      name = "a2tools-local-src";
      path = builtins.toPath path;
      filter = name: _type: !(builtins.elem (baseNameOf name) pruned);
    };

  # Build the package from an explicit source tree (flake input, local path, ...).
  buildFrom = pkgs: src: pkgs.callPackage ./package.nix { inherit src; };

  buildLocal =
    pkgs:
    {
      path,
      ignore ? [ ],
    }:
    buildFrom pkgs (fetchLocal {
      inherit path ignore;
    });
}
