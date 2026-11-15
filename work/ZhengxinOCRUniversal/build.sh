#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
workspace_dir="${project_dir:h:h}"
output_dir="${workspace_dir}/outputs"
app_path="${output_dir}/正心OCR-通用安装版.app"
archive_path="${output_dir}/正心OCR-通用安装版-universal.zip"

mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
icon_build_dir="$(mktemp -d /private/tmp/zhengxin-ocr-icon.XXXXXX)"
trap 'rm -rf "${icon_build_dir}"' EXIT

xcrun clang \
  -fobjc-arc \
  -fblocks \
  -Os \
  -arch arm64 \
  -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  "${project_dir}/Sources/main.m" \
  -o "${app_path}/Contents/MacOS/ZhengxinOCRUniversal"

cp "${project_dir}/Info.plist" "${app_path}/Contents/Info.plist"
rm -f "${app_path}/Contents/Resources/正心OCR帮助.html"
cp "${project_dir}/Resources/正心OCR帮助.md" "${app_path}/Contents/Resources/正心OCR帮助.md"
xcrun actool "${project_dir}/AppIcon.icon" \
  --compile "${icon_build_dir}" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "${icon_build_dir}/partial.plist"
cp "${icon_build_dir}/Assets.car" "${app_path}/Contents/Resources/Assets.car"
cp "${icon_build_dir}/AppIcon.icns" "${app_path}/Contents/Resources/AppIcon.icns"
rsync -rlp --delete "${project_dir}/Resources/bin/" "${app_path}/Contents/Resources/bin/"
rsync -rlp --delete "${project_dir}/Resources/backend/" "${app_path}/Contents/Resources/backend/"
rsync -rlp --delete "${project_dir}/Resources/tools/" "${app_path}/Contents/Resources/tools/"
rsync -rlp --delete "${project_dir}/Resources/skill/" "${app_path}/Contents/Resources/skill/"
chmod +x "${app_path}/Contents/MacOS/ZhengxinOCRUniversal" "${app_path}/Contents/Resources/bin/"* "${app_path}/Contents/Resources/tools/"*

codesign --force --deep --sign - "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"
echo "Built: ${app_path}"
echo "Archive: ${archive_path}"
