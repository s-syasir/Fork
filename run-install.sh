#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
