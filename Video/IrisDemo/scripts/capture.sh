#!/bin/zsh
set -euo pipefail
VIDEO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$VIDEO_ROOT/../.." && pwd)"
IRIS_SIMULATOR="${IRIS_SIMULATOR:-EECE834B-CBEC-4897-A2B9-7A6C5619FD1A}"
cd "$REPO_ROOT"
xcodebuild -project Iris.xcodeproj -scheme Iris -configuration Debug -destination "id=$IRIS_SIMULATOR" -derivedDataPath "$VIDEO_ROOT/review/DerivedData" CODE_SIGNING_ALLOWED=NO build > "$VIDEO_ROOT/review/build.log" 2>&1
xcrun simctl install "$IRIS_SIMULATOR" "$VIDEO_ROOT/review/DerivedData/Build/Products/Debug-iphonesimulator/Iris.app"
xcrun simctl status_bar "$IRIS_SIMULATOR" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl privacy "$IRIS_SIMULATOR" grant all com.iris.ios
maestro test --udid "$IRIS_SIMULATOR" --test-output-dir "$VIDEO_ROOT/review/maestro" "$VIDEO_ROOT/flows/capture.yaml"
python3 - "$VIDEO_ROOT" <<'PY'
from pathlib import Path
import sys,shutil
root=Path(sys.argv[1])
for p in sorted((root/'review/maestro').rglob('takeScreenshot/*.png')):
    shutil.copy2(p,root/'assets/screens'/p.name)
PY
xcrun simctl status_bar "$IRIS_SIMULATOR" clear
