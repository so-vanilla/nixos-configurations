#!/usr/bin/env bash

alacritty --option 'window.dimensions = { columns = 70, lines = 10}'\
          --option 'window.opacity=0.2'\
          --option 'colors.transparent_background_colors = true'\
          --class vime\
          --command bash -c 'VIME=1 nvim /tmp/clip' || exit 1
if [[ -e /tmp/clip ]]; then
  head -c -1 /tmp/clip | wl-copy
  notify-send -t 1000 copied
  rm -f /tmp/clip
fi
