# A2Tools on NixOS

Standalone flake for x86_64 NixOS. It builds the production frontend and native
Rust executable, installs its data/icons/desktop entry, patches the libpcap
RPATH, and wraps the program with its GTK/WebKit runtime environment. The
optional NixOS module installs capture permissions.

Two sources are available, and you choose per machine which one is installed:
`github` (the untouched upstream tree fetched by the flake input) or `local`
(this repository's working checkout, uncommitted modifications included). See
"Choosing the source" below.

## Validation status

Both sources build on this machine: `nix build` (GitHub source) and the
`source = "local"` NixOS module path (this checkout) each produce the packaged
`a2tools-dps-meter` and the capability wrapper. Live capture, the desktop entry
and account/Secret Service features still need to be re-checked after each
change; the runtime settings reproduce the manual setup that worked earlier.

## 1. Build locally

Extract this directory somewhere persistent, for example
`/home/synopia/src/a2tools-nix`. No separate clone of A2Tools is necessary.

```sh
cd /home/synopia/src/a2tools-nix
nix flake lock
nix build -L
```

The GitHub source is pinned to commit
`4f3824dd82a129f4393aba99aaed322b6094d30d` (version 2.0.37).
`nix flake lock` records Nixpkgs and source content hashes. Keep the generated
`flake.lock`; it is intentionally not fabricated in this bundle. A parent flake
may redirect that input with `follows` (this system's config tracks upstream
`main`), and `.#local` bypasses it entirely in favour of a working checkout.

Cargo and npm dependencies are fetched from upstream's lockfiles. There are no
fake hashes to replace. The initial build will download dependencies and may
take a while to compile. Network access is handled by Nix fetchers; the build
itself runs offline.

`nix run` opens the packaged UI, but does not grant capture permissions. For
live capture, install the NixOS module below and launch its wrapper.

If keeping these files in Git, add all `.nix` files and `flake.lock` to Git before
building a Git-backed flake. Untracked files are omitted from its source.

## 2. Install and grant capture permissions declaratively

In your NixOS system flake's `inputs`:

```nix
a2tools.url = "path:/home/synopia/src/a2tools-nix";
```

Make `a2tools` available in your outputs arguments (or access it as
`inputs.a2tools`), then add these entries to the existing machine's `modules`:

```nix
a2tools.nixosModules.default
{
  programs.a2tools-dps-meter = {
    enable = true;
    captureUsers = [ "synopia" ];
  };
}
```

Replace the username if needed. The module adds the existing user to the
`a2tools-capture` group. It installs the application and a desktop entry that
explicitly uses the privileged launcher.

### Choosing the source

`programs.a2tools-dps-meter.source` picks what gets built:

```nix
programs.a2tools-dps-meter = {
  enable = true;
  captureUsers = [ "synopia" ];

  # "github" (default): untouched upstream, as fetched by the flake input
  # a2tools-src. "local": the checkout below, uncommitted edits included.
  source = "local";
  localSource = "/home/synopia/Projects/1_Privat/A2Tools-DPS-Meter";

  # Optional extra names to prune from that checkout. Already pruned by
  # default: .cargo .git .idea .vscode node_modules dist dist-ssr target
  # result.
  localSourceIgnore = [ ];
};
```

`localSource` is a string, not a path, on purpose: a path literal would be
copied into the store unfiltered, i.e. all 18 GiB of `src-tauri/target` and
`node_modules`. The filtered copy is about 24 MB and is re-read on every
evaluation, so a `local` build always sees the current working tree without
`nix flake update`. Only changes to this `packaging/nix` directory itself need
`nix flake update a2tools` from the system configuration.

In this machine's NixOS config the switch is exposed one level up, in
`~/nixos-cfg/hosts/matrix/config.nix`:

```nix
cfg.apps = {
  # ...
  a2tools = enabled // { source = "github"; };  # or "local"
};
```

Rebuild your normal system configuration:

```sh
sudo nixos-rebuild switch --flake /path/to/your/nixos-config#your-hostname
```

Log out of the desktop session and back in once so it acquires the new group.
Then launch **A2Tools DPS Meter** from your app launcher, or:

```sh
/run/wrappers/bin/a2tools-dps-meter
```

Verify:

```sh
id -nG
getcap /run/wrappers/bin/a2tools-dps-meter
```

If `getcap` is not installed, run `nix shell nixpkgs#libcap -c getcap
/run/wrappers/bin/a2tools-dps-meter` as a single command. NixOS may also show
`cap_setpcap` on its C wrapper; this is used to propagate the requested
`cap_net_raw` into the ambient capability set.

There is no manual `sudo setcap` step. Nix store files are immutable and cannot
carry mutable capabilities. The NixOS module creates a root-owned wrapper in
`/run/wrappers/bin`, restricted to the capture group, and recreates it during
system activation. Its source is the packaged runtime launcher. The capability
survives that launcher and reaches the actual executable. The GUI keeps your
normal user identity; it is not run as root.

After installing the module, use the desktop entry or `/run/wrappers/bin/...`.
`nix run` and `./result/bin/...` directly launch the unprivileged package.

## Building local source changes from the command line

`nix build` builds the GitHub source. To build this working checkout instead:

```sh
A2TOOLS_LOCAL_SRC=$PWD nix build -L --impure ./packaging/nix#local
```

`packages.local` exists only while `A2TOOLS_LOCAL_SRC` is set, which keeps the
machine-specific path out of the flake; reading that variable is an impurity,
hence `--impure` (`nix eval` needs it too). `lib.x86_64-linux.buildLocal` and
`buildFrom` are the same helpers if you want to script it:

```sh
nix build -L --impure --expr '
  let f = builtins.getFlake "path:/abs/path/to/repo/packaging/nix";
  in f.lib.x86_64-linux.buildLocal { path = ./.; }'
```

Do NOT use `--override-input a2tools-src "path:$PWD"` for this repository: a
`path:` input copies the whole tree into the store, `src-tauri/target` and
`node_modules` included (18 GiB here). The filtered helpers above copy ~24 MB.

## How runtime packaging works

- `cargo-tauri.hook` runs the frontend production build and Tauri build. It
  extracts a temporary Debian bundle into the Nix store, preserving Tauri's
  expected resource layout. It does not execute Debian's post-install script.
- `postFixup` adds libpcap to the real executable's RPATH AFTER Nix's usual
  RPATH shrinking. This is necessary because libpcap is opened with `dlopen`.
- The GTK application wrapper supplies the schema paths, GIO modules, and
  GStreamer plugins. Explicit schema and plugin paths cover the errors we saw
  with the manual build. The Tauri hook also contributes its WebKit asset plugin.
- The module provides only `CAP_NET_RAW`, which was sufficient for the tested
  manual capture setup. It does not grant capabilities to Node, npm or Cargo.

The host still supplies the graphical session and GPU drivers. If using account
features, the app also expects an available Secret Service implementation, such
as a suitably configured KWallet or GNOME Keyring. This flake does not replace
your desktop session or enable a different keyring.

## Updating

For a new A2Tools revision, change the commit in `flake.nix`, then:

```sh
nix flake update a2tools-src
nix build -L
```

To update only the packaging toolchain:

```sh
nix flake update nixpkgs
nix build -L
```

Your NixOS configuration separately locks its local flake input. After changing
this bundle or its lockfile, update that input FROM your system configuration:

```sh
nix flake update a2tools
sudo nixos-rebuild switch --flake .#your-hostname
```

Rebuilds automatically get the correct new capability wrapper. Use Nix to
update the application; its upstream self-updater cannot replace store files.

## Development

The development shell supplies the compiler, build libraries, runtime paths,
Git, Node, Tauri CLI, patchelf and libcap. It does not grant capture capabilities
or create a mutable checkout automatically.

```sh
git clone https://github.com/taengu/A2Tools-DPS-Meter.git
cd A2Tools-DPS-Meter
nix develop /home/synopia/src/a2tools-nix
npm ci
npm run tauri dev
```

For a complete Nix package build from local source changes:

```sh
cd A2Tools-DPS-Meter
A2TOOLS_LOCAL_SRC=$PWD nix build -L --impure ./packaging/nix#local
```

That is a build test; it does not change the installed system wrapper's target.
Set `programs.a2tools-dps-meter.source = "local"` (plus `localSource`) in your
system configuration if you want to install your changes with declarative
capture permissions.

### Gitignored files that break a Nix build

`ide-env.sh --cargo` writes `src-tauri/.cargo/config.toml` for RustRover. It is
gitignored, but a `local` source copy is filtered by NAME, not by `.gitignore`,
so it would otherwise leak into the store. Cargo then applies its
`[env] ... force = true` entries to every build script, replacing the sandbox's
`PKG_CONFIG_PATH` with this host's store paths, and the build dies early with
`failed to run custom build command for javascriptcore-rs-sys`. `.cargo` is
therefore in `localSourceDefaults` in `lib.nix`. Keep other host-generated
config out of the checkout, or add its name to `localSourceIgnore`.

For the previously working Vite hot-reload workflow, start `npm run dev` in one
dev shell. After producing the debug binary, run in another Bash dev shell:

```bash
meter_bin="$(realpath src-tauri/target/debug/a2tools-dps-meter)"
patchelf --add-rpath "$(pkg-config --variable=libdir libpcap)" "$meter_bin"
sudo "$(command -v setcap)" cap_net_raw=ep "$meter_bin"
"$meter_bin"
```

That manual step applies only to your mutable debug executable, and must be
repeated when Cargo replaces it. The installed package needs none of it.

## Preparing an upstream PR later

The packaging expression deliberately accepts `src` as an argument. In an
upstream flake, remove the separate `a2tools-src` input and pass `src = self`
when calling `nix/package.nix`. Keep the module and development shell, generate
and commit the lockfile, then validate a clean build and live capture on NixOS.
Changing the source input alone does not require rewriting the package.

Before submission, verify startup from the desktop entry after login, correct
scaling, live capture, the packaged game data, and an update/rebuild. Test the
original auto-sizing code with the fixed GTK environment before including any
of our temporary debugging modifications. `source = "github"` keeps the
installed system package on untouched upstream; switch it to `"local"` only
once the changes are meant to be installed.
