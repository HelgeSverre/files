#!/usr/bin/env bash
# Render Formula/files.rb for the homebrew tap from release SHA256s.
# Usage: render-formula.sh <version> <sha_macos_arm64> <sha_macos_x86_64> <sha_linux_x86_64> <sha_linux_arm64>
set -euo pipefail

version="$1"
macos_arm64="$2"
macos_x64="$3"
linux_x64="$4"
linux_arm64="$5"

cat <<EOF
class Files < Formula
  desc "Fast, git-aware directory tree for your terminal"
  homepage "https://github.com/HelgeSverre/files"
  version "${version}"
  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/HelgeSverre/files/releases/download/v${version}/files-macos-arm64.tar.gz"
      sha256 "${macos_arm64}"
    end
    if Hardware::CPU.intel?
      url "https://github.com/HelgeSverre/files/releases/download/v${version}/files-macos-x86_64.tar.gz"
      sha256 "${macos_x64}"
    end
  end
  if OS.linux?
    if Hardware::CPU.arm?
      url "https://github.com/HelgeSverre/files/releases/download/v${version}/files-linux-arm64.tar.gz"
      sha256 "${linux_arm64}"
    end
    if Hardware::CPU.intel?
      url "https://github.com/HelgeSverre/files/releases/download/v${version}/files-linux-x86_64.tar.gz"
      sha256 "${linux_x64}"
    end
  end
  license "MIT"

  def install
    bin.install "files"
  end

  test do
    assert_match "files", shell_output("#{bin}/files --version")
  end
end
EOF
