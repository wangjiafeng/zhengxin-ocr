#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
workspace_dir="${project_dir:h:h}"
output_dir="${workspace_dir}/outputs"
app_path="${output_dir}/正心OCR.app"
archive_path="${output_dir}/正心OCR-完整离线版-arm64.zip"

bundle_ready=false
existing_bundle_ready=false
[[ -f "${project_dir}/Bundle/models/.setup-complete" ]] && bundle_ready=true
[[ -f "${app_path}/Contents/Resources/models/.setup-complete" && -d "${app_path}/Contents/Resources/python" ]] && existing_bundle_ready=true
if [[ "${bundle_ready}" != true && "${existing_bundle_ready}" != true ]]; then
  print -u2 "缺少内置依赖与模型。请先运行：python3 prepare_bundle.py"
  exit 1
fi

mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
rm -f "${app_path}/Contents/MacOS/AncientOCR"
rm -rf "${app_path}/Contents/Resources/bin" "${app_path}/Contents/Resources/backend" "${app_path}/Contents/Resources/skill"
if [[ "${bundle_ready}" == true ]]; then
  rm -rf "${app_path}/Contents/Resources/python" "${app_path}/Contents/Resources/models"
fi

xcrun clang \
  -fobjc-arc \
  -fblocks \
  -Os \
  -target arm64-apple-macosx26.0 \
  -framework Cocoa \
  "${project_dir}/Sources/main.m" \
  -o "${app_path}/Contents/MacOS/AncientOCR"

cp "${project_dir}/Info.plist" "${app_path}/Contents/Info.plist"
cp "${project_dir}/Resources/AppIcon.icns" "${app_path}/Contents/Resources/AppIcon.icns"
rm -f "${app_path}/Contents/Resources/正心OCR帮助.html"
cp "${project_dir}/Resources/正心OCR帮助.md" "${app_path}/Contents/Resources/正心OCR帮助.md"
cp -R "${project_dir}/Resources/bin" "${app_path}/Contents/Resources/bin"
cp -R "${project_dir}/Resources/backend" "${app_path}/Contents/Resources/backend"
cp -R "${project_dir}/Resources/skill" "${app_path}/Contents/Resources/skill"
if [[ "${bundle_ready}" == true ]]; then
  cp -R "${project_dir}/Bundle/python" "${app_path}/Contents/Resources/python"
  cp -R "${project_dir}/Bundle/models" "${app_path}/Contents/Resources/models"
else
  print "复用现有 APP 内的依赖与模型。"
fi
chmod +x "${app_path}/Contents/MacOS/AncientOCR" "${app_path}/Contents/Resources/bin/"*

codesign --force --deep --sign - "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

rm -f "${archive_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"
echo "Built: ${app_path}"
echo "Archive: ${archive_path}"
