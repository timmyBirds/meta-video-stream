#!/usr/bin/env bash
# generate.sh — install xcodegen (if needed) and regenerate MetaVideoStream.xcodeproj
# Run from the ios-app/ directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEAM_ID="B5WNGX3893"
XCODEPROJ="MetaVideoStream.xcodeproj"

# ── 1. Ensure xcconfig files exist ────────────────────────────────────────────
for cfg in Debug Release; do
  target="Config/${cfg}.xcconfig"
  example="${target}.example"
  if [[ ! -f "$target" ]]; then
    echo "⚠️  ${target} not found — copying from example."
    cp "$example" "$target"
    echo "   Fill in your META_APP_ID, CLIENT_TOKEN, and DEVELOPMENT_TEAM in ${target}"
  fi
done

# ── 2. Install xcodegen if missing ────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo "📦 xcodegen not found. Installing via Homebrew…"
  if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew is required. Install it from https://brew.sh and re-run."
    exit 1
  fi
  brew install xcodegen
fi

# ── 3. Generate project ───────────────────────────────────────────────────────
echo "🔨 Generating ${XCODEPROJ}…"
xcodegen generate --spec project.yml

# ── 4. Patch DevelopmentTeam into pbxproj so Xcode finds it immediately ──────
# xcodegen writes DEVELOPMENT_TEAM into build settings, but Xcode's signing UI
# also needs the DevelopmentTeam key in the TargetAttributes section.
PBXPROJ="${XCODEPROJ}/project.pbxproj"
echo "🔑 Patching DevelopmentTeam in pbxproj…"
/usr/libexec/PlistBuddy -x -c "Print" "${PBXPROJ}" > /dev/null 2>&1 || true

# Use sed to insert DevelopmentTeam next to any ProvisioningStyle = Automatic line
# (xcodegen writes this when signing.style = automatic)
if grep -q "ProvisioningStyle = Automatic" "${PBXPROJ}"; then
  sed -i '' "s/ProvisioningStyle = Automatic;/DevelopmentTeam = ${TEAM_ID};\n\t\t\t\tProvisioningStyle = Automatic;/g" "${PBXPROJ}"
  echo "   ✓ DevelopmentTeam patched."
else
  echo "   ⚠️  ProvisioningStyle not found — set Team manually in Xcode Signing & Capabilities."
fi

echo "✅ Done. Open ${XCODEPROJ} in Xcode."
