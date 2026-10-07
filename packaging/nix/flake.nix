{
  description = "A2Tools DPS Meter: native Linux package, dev shell and NixOS capture permissions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pristine upstream source. No manual source hash: `nix flake lock` records
    # the content hash. A parent flake may `follows` this input, or you can use
    # `--override-input a2tools-src <url>`; prefer `.#local` / the module's
    # `source = "local"` over a `path:` override, which copies the whole
    # working tree (18 GiB of target/ and node_modules/ included) into the store.
    a2tools-src = {
      url = "github:taengu/A2Tools-DPS-Meter/4f3824dd82a129f4393aba99aaed322b6094d30d";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      a2tools-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      srcs = import ./lib.nix { lib = nixpkgs.lib; };

      # Untouched upstream source, as pinned by flake.lock (or redirected by a
      # parent flake's `follows` / --override-input).
      upstream = srcs.buildFrom pkgs a2tools-src;

      # Opt-in convenience target:
      #   A2TOOLS_LOCAL_SRC=$PWD nix build -L --impure ./packaging/nix#local
      # The env var keeps the machine-specific checkout path out of the flake;
      # reading it is an impurity, hence --impure.
      localPath = builtins.getEnv "A2TOOLS_LOCAL_SRC";
    in
    {
      packages.${system} = {
        default = upstream;
        a2tools-dps-meter = upstream;
        upstream = upstream;
      }
      // nixpkgs.lib.optionalAttrs (localPath != "") {
        # This working checkout, filtered (see lib.nix).
        local = srcs.buildLocal pkgs { path = localPath; };
      };

      # Build from any source you like, e.g. from the repository root:
      #   A2TOOLS_LOCAL_SRC=$PWD nix build -L --impure ./packaging/nix#local
      # or, without the env var:
      #   nix build -L --impure --expr \
      #     'let f = builtins.getFlake "path:/abs/path/to/repo/packaging/nix";
      #      in f.lib.x86_64-linux.buildLocal { path = ./.; }'
      lib.${system} = {
        fetchLocal = srcs.fetchLocal;
        buildFrom = src: srcs.buildFrom pkgs src;
        buildLocal = args: srcs.buildLocal pkgs args;
      };

      # UI launch only. Use the NixOS module below for live capture permissions.
      apps.${system}.default = {
        type = "app";
        program = "${upstream}/bin/a2tools-dps-meter";
      };

      devShells.${system}.default = import ./dev-shell.nix { inherit pkgs; };
      formatter.${system} = pkgs.nixfmt;

      # programs.a2tools-dps-meter.source = "github" | "local" selects the source.
      nixosModules.default = import ./module.nix { inherit self; };
    };
}
