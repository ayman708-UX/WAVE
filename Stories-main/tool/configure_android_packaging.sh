#!/usr/bin/env bash
# AGP 9+ rejects android:extractNativeLibs in the manifest; set legacy JNI packaging in Gradle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/app/build.gradle.kts"
MARKER="stories-legacy-jni-packaging"

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
    print("Legacy JNI packaging already configured in build.gradle.kts")
    raise SystemExit(0)

needle = "    buildTypes {"
if needle not in text:
    raise SystemExit("error: buildTypes block not found in build.gradle.kts")

insert = """    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {"""

text = text.replace(needle, insert, 1)
if marker not in text:
    text = text.replace(
        "    packaging {",
        f"    // {marker}\n    packaging {{",
        1,
    )

gradle.write_text(text)
print("Configured legacy JNI packaging in build.gradle.kts")
PY
