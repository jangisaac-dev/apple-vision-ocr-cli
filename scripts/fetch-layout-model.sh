#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
model_dir=${APPLE_VISION_OCR_MODEL_DIR:-"$repo_dir/.build/models"}
mkdir -p "$model_dir"
model_dir=$(cd "$model_dir" && pwd)
target="$model_dir/PPDocLayoutV3.mlmodelc"

print_export() {
    local escaped=${target//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    escaped=${escaped//\$/\\\$}
    escaped=${escaped//\`/\\\`}
    printf 'export APPLE_VISION_OCR_LAYOUT_MODEL="%s"\n' "$escaped"
}

if [[ -d "$target" ]]; then
    print_export
    exit 0
fi

work_dir=$(mktemp -d "$model_dir/.fetch-layout-model.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
package="$work_dir/PPDocLayoutV3.mlpackage"
base_url=https://huggingface.co/hugging-mac/pp-doclayout-v3-coreml/resolve/270f90d8404e9ef88ce6293da80d4cf731586353/model.mlpackage

fetch_file() {
    local relative_path=$1
    local checksum=$2
    local destination="$package/$relative_path"
    mkdir -p "$(dirname "$destination")"
    curl -fL "$base_url/$relative_path" -o "$destination"
    printf '%s  %s\n' "$checksum" "$destination" | shasum -a 256 -c -
}

fetch_file Manifest.json ffcc86c607a50e8e3d40b11964b0628442c13104b0fe8a43fe67ce5a3006e589
fetch_file Data/com.apple.CoreML/model.mlmodel 699fc72be51534a9a2f64314767249000e3f5580e523d26d48262ef02e877eb2
fetch_file Data/com.apple.CoreML/weights/weight.bin da3e08e77605d433b249910697e6c04a3dc05db6f6e3b2e35337e176a791a9c3
mkdir -p "$work_dir/out"
xcrun coremlcompiler compile "$package" "$work_dir/out" --platform macos --deployment-target 26.0
mv "$work_dir/out/PPDocLayoutV3.mlmodelc" "$target"
print_export
