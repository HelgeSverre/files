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
exe=""

case "${os}" in
  Darwin*) platform="macos" ;;
  Linux*)  platform="linux" ;;
  MINGW*|MSYS*|CYGWIN*)
    platform="windows"
    cpu="x86_64"
    exe=".exe"
    ;;
  *)
    echo "files: unsupported platform '${os}'" >&2
    exit 1
    ;;
esac

if [[ -z "${cpu:-}" ]]; then
  case "${arch}" in
    arm64|aarch64) cpu="arm64" ;;
    x86_64|amd64)  cpu="x86_64" ;;
    *)
      echo "files: unsupported architecture '${arch}'" >&2
      exit 1
      ;;
  esac
fi

asset="files-${platform}-${cpu}${exe}"
if [[ "${VERSION}" == "latest" ]]; then
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
else
  url="https://github.com/${REPO}/releases/download/${VERSION}/${asset}"
fi

mkdir -p "${BIN_DIR}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

echo "files: downloading ${url}"
curl -fsSL "${url}" -o "${tmpdir}/files${exe}"
chmod +x "${tmpdir}/files${exe}" 2>/dev/null || true

# Strip the Gatekeeper quarantine flag curl attaches on macOS (best effort).
if [[ "${platform}" == "macos" ]]; then
  xattr -d com.apple.quarantine "${tmpdir}/files${exe}" 2>/dev/null || true
fi

mv "${tmpdir}/files${exe}" "${BIN_DIR}/files${exe}"

if ! command -v "files${exe}" >/dev/null 2>&1 && [[ "${BIN_DIR}" != "/usr/local/bin" ]]; then
  echo "files: note: '${BIN_DIR}' is not on your PATH — add it with:"
  echo "  export PATH=\"${BIN_DIR}:\$PATH\""
fi

echo "files: installed ${VERSION} to ${BIN_DIR}/files${exe}"
"${BIN_DIR}/files${exe}" --version
