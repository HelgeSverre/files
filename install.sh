#!/usr/bin/env bash
#
# install.sh — install the `files` binary from GitHub releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/HelgeSverre/files/main/install.sh | bash
#   bash install.sh            # latest release
#   bash install.sh v0.1.0     # specific release
#   bash install.sh latest /opt/local/bin   # custom install dir
set -euo pipefail

REPO="HelgeSverre/files"
VERSION="${1:-latest}"
BIN_DIR="${2:-${HOME}/.local/bin}"

os="$(uname -s)"
arch="$(uname -m)"

case "${os}" in
  Darwin*) platform="macos" ;;
  Linux*)  platform="linux" ;;
  *)
    echo "files: unsupported platform '${os}'" >&2
    exit 1
    ;;
esac

case "${arch}" in
  arm64|aarch64) cpu="arm64" ;;
  x86_64|amd64)  cpu="x86_64" ;;
  *)
    echo "files: unsupported architecture '${arch}'" >&2
    exit 1
    ;;
esac

if [[ "${VERSION}" == "latest" ]]; then
  url="https://github.com/${REPO}/releases/latest/download/files-${platform}-${cpu}"
else
  url="https://github.com/${REPO}/releases/download/${VERSION}/files-${platform}-${cpu}"
fi

mkdir -p "${BIN_DIR}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

echo "files: downloading ${url}"
curl -fsSL "${url}" -o "${tmpdir}/files"
chmod +x "${tmpdir}/files"

# Strip the Gatekeeper quarantine flag curl attaches on macOS (best effort).
if [[ "${platform}" == "macos" ]]; then
  xattr -d com.apple.quarantine "${tmpdir}/files" 2>/dev/null || true
fi

mv "${tmpdir}/files" "${BIN_DIR}/files"

if ! command -v files >/dev/null 2>&1 && [[ "${BIN_DIR}" != "/usr/local/bin" ]]; then
  echo "files: note: '${BIN_DIR}' is not on your PATH — add it with:"
  echo "  export PATH=\"${BIN_DIR}:\$PATH\""
fi

echo "files: installed ${VERSION} to ${BIN_DIR}/files"
"${BIN_DIR}/files" --version
