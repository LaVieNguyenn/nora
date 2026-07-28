#!/bin/bash
# Mở cửa sổ chính của Nora mà không cần tìm biểu tượng trên menubar.
#
# Trên MacBook có notch, thanh menubar chật có thể đẩy biểu tượng ra sau notch
# và không bấm được. Script này luôn mở được cửa sổ.

set -euo pipefail

APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dist/NoraUI.app"

if [[ ! -d "$APP" ]]; then
    echo "Chưa có bản build. Chạy: ./build_app.sh release" >&2
    exit 1
fi

if pgrep -x NoraUI > /dev/null; then
    # Đang chạy: một lần "open" nữa sẽ kích hoạt luồng mở lại cửa sổ.
    open "$APP"
else
    open "$APP" --args --window
fi
