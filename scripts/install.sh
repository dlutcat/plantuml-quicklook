#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$root/dist/PlantUML Preview.app"
destination="${1:-$HOME/Applications/PlantUML Preview.app}"
if [[ ! -d "$source_app" ]]; then
  echo '请先运行 python3 scripts/build.py' >&2
  exit 1
fi
if [[ -e "$destination" ]]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist")
  [[ "$identifier" == 'io.github.dlutcat.PlantUMLPreview' ]] || { echo '目标位置存在不同标识的应用，已停止。请先将旧版本移到其他位置，再重新安装。' >&2; exit 1; }
  pluginkit -r "$destination/Contents/PlugIns/PlantUMLPreview.appex" || true
  backup="${destination}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$destination" "$backup"
  echo "旧版本已备份至 $backup"
fi
mkdir -p "$(dirname "$destination")"
ditto "$source_app" "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
pluginkit -a "$destination/Contents/PlugIns/PlantUMLPreview.appex"
pluginkit -e use -i io.github.dlutcat.PlantUMLPreview.Preview
open "$destination"
echo "已安装至 $destination"
echo '若 Finder 尚未显示预览，请在系统设置的快速查看扩展中启用 PlantUML Preview。'
