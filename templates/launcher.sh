#!/usr/bin/env bash

cmd="$*"

font_size="${OMARCHY_SYNCD_LAUNCHER_FONT_SIZE:-${OMARCHY_SYNCD_LAUNCHER_FONT_SIZE_DEFAULT}}"
if [[ -z "$font_size" ]]; then
  font_size=9
fi

term=${OMARCHY_SYNCD_LAUNCHER_TERMINAL:-alacritty}
case "$term" in
  alacritty)
    exec setsid uwsm-app -- alacritty -o font.size="$font_size" --class=OmarchySyncd --title=OmarchySyncd -e bash -lc "omarchy-syncd-show-logo; $cmd; omarchy-syncd-show-done"
    ;;
  kitty)
    exec setsid uwsm-app -- kitty --class OmarchySyncd --title OmarchySyncd -e bash -lc "omarchy-syncd-show-logo; $cmd; omarchy-syncd-show-done"
    ;;
  *)
    exec setsid uwsm-app -- "$term" -e bash -lc "omarchy-syncd-show-logo; $cmd; omarchy-syncd-show-done"
    ;;
esac
