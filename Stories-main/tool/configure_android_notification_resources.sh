#!/usr/bin/env bash
# Keep media notification drawable in release builds (audio_service MediaStyle).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/app/build.gradle.kts"
MARKER="stories-notification-resources"

if [[ ! -f "$GRADLE" ]]; then
  echo "error: run flutter create first (missing $GRADLE)" >&2
  exit 1
fi

python3 - "$GRADLE" "$MARKER" <<'PY'
import sys
from pathlib import Path

gradle = Path(sys.argv[1])
marker = sys.argv[2]
text = gradle.read_text()

if marker in text:
    print("Notification resource settings already configured in build.gradle.kts")
    raise SystemExit(0)

needle = "        release {"
if needle not in text:
    raise SystemExit("error: release buildType block not found in build.gradle.kts")

insert = f"""        release {{
            // {marker}
            isShrinkResources = false
            isMinifyEnabled = false"""

text = text.replace(needle, insert, 1)
gradle.write_text(text)
print("Configured release shrinkResources=false for notification icon")
PY
