#!/bin/bash

# Godot Development Tools Installation Script
#
# Installs Python via asdf and gdtoolkit (gdformat / gdlint).
# Works with asdf 0.18+ (`asdf set`) and older (`asdf local`). See gama/install_tools.sh.
#
# Usage: ./install_tools.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Installing Godot development tools for dungeoneers..."

if ! command -v asdf &> /dev/null; then
	echo "ERROR: asdf is not installed. See https://asdf-vm.com/guide/getting-started.html"
	exit 1
fi

if ! asdf plugin list | grep -q "python"; then
	echo "Installing asdf Python plugin..."
	asdf plugin add python
fi

# Version pinned in this repo (asdf install reads .tool-versions).
PY_VER="$(awk '/^python[[:space:]]/ { print $2; exit }' .tool-versions 2>/dev/null || true)"
PY_VER="${PY_VER:-3.11.5}"

echo "Installing Python ${PY_VER} from .tool-versions..."
asdf install python "${PY_VER}"

echo "Pinning Python ${PY_VER} for this directory (.tool-versions)..."
if asdf set python "${PY_VER}" 2>/dev/null; then
	:
elif asdf local python "${PY_VER}" 2>/dev/null; then
	:
else
	echo "ERROR: could not pin Python (tried: asdf set python ${PY_VER}  and  asdf local python ${PY_VER})."
	echo "Upgrade asdf or set python in .tool-versions manually."
	exit 1
fi

echo "Python: $(python --version)"
echo "pip: $(pip --version)"

echo "Installing gdtoolkit..."
pip install gdtoolkit

# asdf 0.18+: reshim requires a version; older asdf accepts bare plugin name.
if ! asdf reshim python "${PY_VER}" 2>/dev/null; then
	asdf reshim python 2>/dev/null || true
fi

if command -v gdformat &> /dev/null; then
	echo "gdtoolkit OK: $(gdformat --version)"
else
	_PYROOT="$(asdf where python "${PY_VER}" 2>/dev/null || asdf where python 2>/dev/null || true)"
	if [ -n "$_PYROOT" ] && [ -x "$_PYROOT/bin/gdformat" ]; then
		_gdv="$("$_PYROOT/bin/gdformat" --version)"
		echo "gdtoolkit OK (not on PATH yet): $_gdv"
		echo "Try: hash -r  or a new shell, then ./format_all.sh"
	else
		echo "ERROR: gdtoolkit install failed (no gdformat under asdf Python)."
		echo "See: https://github.com/Scony/godot-gdscript-toolkit"
		exit 1
	fi
fi

echo "Done."
