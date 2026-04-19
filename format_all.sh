#!/bin/bash
# Non-interactive formatter: runs `gdformat .` on this project.
# gama uses an interactive per-file flow in gama/format_all.sh; this script stays CI-friendly.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Match typical shells: load asdf when not already on PATH (gama assumes a login shell with asdf).
_asdf_source() {
	for _asdf_sh in \
		"${ASDF_DIR:+$ASDF_DIR/asdf.sh}" \
		"${HOME}/.asdf/asdf.sh" \
		"/opt/homebrew/opt/asdf/libexec/asdf.sh" \
		"/usr/local/opt/asdf/libexec/asdf.sh"; do
		if [ -f "$_asdf_sh" ]; then
			# shellcheck source=/dev/null
			. "$_asdf_sh"
			return 0
		fi
	done
	return 1
}

if ! command -v asdf &> /dev/null; then
	_asdf_source || true
fi

_PY_VER="$(awk '/^python[[:space:]]/ { print $2; exit }' "$SCRIPT_DIR/.tool-versions" 2>/dev/null || true)"
_PY_VER="${_PY_VER:-3.11.5}"

_resolve_gdformat() {
	if command -v gdformat &> /dev/null; then
		command -v gdformat
		return 0
	fi
	local _py _bindir _cand
	for _py in "$(command -v python 2>/dev/null)" "$(command -v python3 2>/dev/null)"; do
		if [ -n "$_py" ] && [ -x "$_py" ]; then
			_bindir="$(dirname "$_py")"
			_cand="$_bindir/gdformat"
			if [ -x "$_cand" ]; then
				echo "$_cand"
				return 0
			fi
		fi
	done
	if command -v asdf &> /dev/null; then
		local _root
		_root="$(asdf where python "${_PY_VER}" 2>/dev/null || asdf where python 2>/dev/null || true)"
		if [ -n "$_root" ] && [ -x "$_root/bin/gdformat" ]; then
			echo "$_root/bin/gdformat"
			return 0
		fi
	fi
	return 1
}

GDFORMAT="$(_resolve_gdformat || true)"
if [ -z "$GDFORMAT" ]; then
	echo "ERROR: gdformat not found (gama expects asdf Python + gdtoolkit on PATH)."
	echo "  Run from this directory:  ./install_tools.sh"
	echo "  Then open a new terminal or:  hash -r"
	exit 1
fi

echo "Formatting GDScript with: $GDFORMAT"
exec "$GDFORMAT" .
