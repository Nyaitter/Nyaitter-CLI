#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="${SCRIPT_DIR}/nyaitter"

TARGET_DIR="${HOME}/.local/bin"
mkdir -p "$TARGET_DIR"

ln -sf "$BIN_PATH" "${TARGET_DIR}/nyaitter"
chmod +x "${TARGET_DIR}/nyaitter"

echo "✅ Nyaitter CLI をインストールしました: ${TARGET_DIR}/nyaitter"
echo ""
echo "PATH に ${TARGET_DIR} が含まれていることを確認してください："
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "テスト実行: nyaitter --help"
