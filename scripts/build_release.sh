#!/usr/bin/env bash
# Builds split-per-ABI release APKs, injecting the bundled Gemini API key
# (if app/secrets.local.env exists) via --dart-define instead of ever
# hardcoding it in source. Run from anywhere; paths are resolved relative
# to this script's location.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="$ROOT_DIR/app/secrets.local.env"

DART_DEFINES=()
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$SECRETS_FILE"; set +a
  if [[ -n "${GEMINI_API_KEY:-}" && "${GEMINI_API_KEY}" != "paste-your-key-here" ]]; then
    DART_DEFINES+=(--dart-define="GEMINI_API_KEY=${GEMINI_API_KEY}")
    echo "Bundling Gemini API key from app/secrets.local.env"
  fi
else
  echo "No app/secrets.local.env found -- building without a bundled API key."
  echo "(copy app/secrets.local.env.example to app/secrets.local.env to add one)"
fi

cd "$ROOT_DIR/app"
flutter build apk --release --split-per-abi "${DART_DEFINES[@]}"

echo ""
echo "Built:"
ls -la build/app/outputs/flutter-apk/*.apk
