#!/usr/bin/env bash
# Bump compileSdk for the app and all Android library plugins (file_picker, etc.).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_GRADLE="$ROOT/android/app/build.gradle.kts"
ROOT_GRADLE="$ROOT/android/build.gradle.kts"
COMPILE_SDK="${STORIES_COMPILE_SDK:-36}"
MARKER="stories-compile-sdk"

if [[ ! -f "$APP_GRADLE" ]]; then
  echo "error: run flutter create first (missing $APP_GRADLE)" >&2
  exit 1
fi

python3 - "$APP_GRADLE" "$ROOT_GRADLE" "$COMPILE_SDK" "$MARKER" <<'PY'
import re
import sys
from pathlib import Path

app_gradle = Path(sys.argv[1])
root_gradle = Path(sys.argv[2])
compile_sdk = sys.argv[3]
marker = sys.argv[4]

text = app_gradle.read_text()
text = re.sub(
    r"compileSdk\s*=\s*flutter\.compileSdkVersion",
    f"compileSdk = {compile_sdk}",
    text,
    count=1,
)
if f"compileSdk = {compile_sdk}" not in text:
    raise SystemExit("error: could not set app compileSdk in build.gradle.kts")
app_gradle.write_text(text)
print(f"Set app compileSdk to {compile_sdk}")

if not root_gradle.exists():
    raise SystemExit(f"error: missing {root_gradle}")

root_text = root_gradle.read_text()
root_text = re.sub(
    rf"\n// {re.escape(marker)}\n.*?(?=\nsubprojects \{{\n    project\.evaluationDependsOn|\ntasks\.register|\Z)",
    "\n",
    root_text,
    flags=re.DOTALL,
)

# afterEvaluate must be registered BEFORE evaluationDependsOn(:app).
block = f"""
// {marker}
subprojects {{
    pluginManager.withPlugin("com.android.library") {{
        extensions.configure<com.android.build.gradle.LibraryExtension> {{
            compileSdk = {compile_sdk}
        }}
    }}
    afterEvaluate {{
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {{
            compileSdk = {compile_sdk}
        }}
    }}
}}
"""

needle = "subprojects {\n    project.evaluationDependsOn(\":app\")"
if needle not in root_text:
    raise SystemExit("error: expected evaluationDependsOn block in android/build.gradle.kts")
root_text = root_text.replace(needle, block + "\n" + needle, 1)
root_gradle.write_text(root_text)
print(f"Configured plugin compileSdk {compile_sdk} in android/build.gradle.kts")
PY
