#!/bin/zsh
# 用 Chrome 无头模式把 HTML 导出为 2 倍清晰度 PNG：./render.sh 01-cover 1600 900
cd "${0:A:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=$2,$3 --virtual-time-budget=3000 --allow-file-access-from-files --default-background-color=00000000 \
    --screenshot="../images/$1.png" "file://$PWD/$1.html" 2>/dev/null
}
if [[ -n $1 ]]; then render $1 $2 $3; exit; fi
render 01-cover 1600 900
render 02-platforms 1600 1000
render 03-iphone-widgets 1600 1000
render 04-apple-watch 1600 1000
render 05-square 1200 1200
render 06-app-icon 512 512
