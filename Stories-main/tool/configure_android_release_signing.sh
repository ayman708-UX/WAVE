#!/usr/bin/env bash
# Wire android/app/build.gradle.kts to use android/key.properties when present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="$ROOT/android/app/build.gradle.kts"
GRADLE_PROPS="$ROOT/android/gradle.properties"

if [[ ! -f "$GRADLE" ]]; then
  echo "error: run flutter create first (missing $GRADLE)" >&2
  exit 1
fi

# AGP 9 defaults to the new DSL where our signing snippet does not compile yet.
if [[ -f "$GRADLE_PROPS" ]] && ! grep -q '^android.newDsl=' "$GRADLE_PROPS"; then
  cat >> "$GRADLE_PROPS" <<'EOF'

# Stories CI/local signing uses the classic Android Gradle DSL.
android.newDsl=false
EOF
  echo "Set android.newDsl=false in android/gradle.properties"
fi

python3 - "$GRADLE" <<'PY'
import re
import sys
from pathlib import Path

gradle = Path(sys.argv[1])
text = gradle.read_text()
marker = "stories-release-signing"

if marker in text:
    print("Release signing already configured in build.gradle.kts")
    raise SystemExit(0)

if "import java.util.Properties" not in text:
    text = (
        "import java.io.FileInputStream\n"
        "import java.util.Properties\n\n"
        + text
    )

android_idx = text.index("android {")
keystore_block = """
// stories-release-signing
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

"""
text = text[:android_idx] + keystore_block + text[android_idx:]

build_types_needle = "    buildTypes {"
if build_types_needle not in text:
    raise SystemExit("error: buildTypes block not found in build.gradle.kts")

if "signingConfigs {" not in text:
    signing_block = """    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {"""
    text = text.replace(build_types_needle, signing_block, 1)

release_signing = """signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }"""

replaced = False
for pattern in (
    r"signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\)",
    r"signingConfig\s*=\s*signingConfigs\.debug",
):
    new_text, count = re.subn(pattern, release_signing, text, count=1)
    if count:
        text = new_text
        replaced = True
        break

if not replaced:
    raise SystemExit("error: could not patch release signingConfig in build.gradle.kts")

gradle.write_text(text)
print("Configured optional release signing in build.gradle.kts")
PY
