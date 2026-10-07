#!/usr/bin/env bash
# Start RustRover (or IntelliJ + Rust plugin) INSIDE the dev shell, so the IDE
# process - and therefore cargo sync, rust-analyzer, the external linter, its
# embedded terminals and every run configuration - inherits PKG_CONFIG_PATH,
# the GTK/WebKit/OpenSSL/libpcap search paths and the runtime paths.
#
#   ./packaging/nix/ide-launch.sh                  # opens the repo root
#   ./packaging/nix/ide-launch.sh ~/some/other/dir
#
# Override the IDE binary with:  IDE_BIN=/path/to/idea ./packaging/nix/ide-launch.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

IDE_BIN="${IDE_BIN:-$HOME/.local/share/JetBrains/Toolbox/apps/rustrover/bin/rustrover}"
if ! command -v "$IDE_BIN" >/dev/null 2>&1 && [ ! -x "$IDE_BIN" ]; then
  echo "IDE_BIN not found: $IDE_BIN" >&2
  echo "Point IDE_BIN at your launcher, e.g.:" >&2
  echo "  IDE_BIN=\$HOME/.local/share/JetBrains/Toolbox/apps/rustrover/bin/rustrover" >&2
  exit 1
fi

exec nix develop "$here" -c "$IDE_BIN" "${1:-$repo}"
