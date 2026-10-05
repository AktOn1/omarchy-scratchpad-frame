#!/bin/bash
# Create an Omarchy theme from a wallpaper with Aether and apply it.
# Usage: make-theme.sh [image]      (no argument: pick the image in a file dialog)
# Writes ~/.config/omarchy/themes/<image-name>/ (colors.toml, the wallpaper, preview) and runs omarchy-theme-set.
# It never overwrites a theme that was not made by Aether.

export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
THEMES="$HOME/.config/omarchy/themes"
notify() { omarchy-notification-send "$@" -t 4000 >/dev/null 2>&1 || echo "$*"; }

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/scratchpad-frame-make-theme.lock"
flock -n 9 || { notify "A theme is already being created"; exit 1; }

img="$1"
if [[ -z $img ]]; then
  start="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null)"
  [[ -n $start && -f $start ]] && start="$(dirname "$start")/" || start="$HOME/Pictures/"
  img="$(zenity --file-selection --title="Create theme from wallpaper" --filename="$start" \
    --file-filter='Images | *.png *.jpg *.jpeg *.webp *.bmp *.PNG *.JPG *.JPEG *.WEBP' 2>/dev/null)" || exit 0
fi
[[ -f $img ]] || { notify "Not an image file" "$img"; exit 1; }
img="$(readlink -f "$img")"
ext="${img##*.}"; ext="${ext,,}"

base="$(basename "${img%.*}")"
slug="$(echo "$base" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
[[ -n $slug ]] || slug="wallpaper-theme"
if [[ -e $THEMES/$slug && ! -f $THEMES/$slug/.aether-managed ]]; then
  slug="$slug-wallpaper"
  if [[ -e $THEMES/$slug && ! -f $THEMES/$slug/.aether-managed ]]; then
    notify "Theme name taken" "$slug exists and was not made by Aether"
    exit 1
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

notify "Creating theme from wallpaper" "$base"
if ! aether --generate "$img" --no-apply --output "$work/gen" >"$work/log" 2>&1 || [[ ! -f $work/gen/colors.toml ]]; then
  notify "Could not create a theme" "$(tail -n 2 "$work/log" | tr '\n' ' ')"
  exit 1
fi

# Aether writes bg/fg names; Omarchy's templates want background/dark_background/bright_foreground...
new="$work/theme"
mkdir -p "$new/backgrounds"
awk -F'"' '
  /^[a-z_0-9]+ *= *"/ { split($1, k, " "); v[k[1]] = tolower($2) }
  END {
    alias["dark_background"] = "dark_bg"; alias["darker_background"] = "darker_bg"; alias["lighter_background"] = "lighter_bg"
    alias["dark_foreground"] = "dark_fg"; alias["light_foreground"] = "light_fg"; alias["bright_foreground"] = "bright_fg"
    printf "# Generated from a wallpaper with Aether (Scratchpad Frame).\n"
    printf "mode = \"%s\"\n\n", (("mode" in v) ? v["mode"] : "dark")
    order = "accent selection selection_foreground muted|background dark_background darker_background lighter_background|foreground dark_foreground light_foreground bright_foreground|red yellow orange green cyan blue magenta brown|bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta"
    ng = split(order, groups, "|")
    for (g = 1; g <= ng; g++) {
      m = split(groups[g], names, " ")
      for (i = 1; i <= m; i++) {
        key = names[i]; val = (key in v) ? v[key] : v[alias[key]]
        if (val != "") printf "%s = \"%s\"\n", key, val
      }
      printf "\n"
    }
  }' "$work/gen/colors.toml" >"$new/colors.toml"

for key in accent background foreground bright_foreground dark_background; do
  grep -q "^$key = " "$new/colors.toml" || { notify "Could not create a theme" "missing colour: $key"; exit 1; }
done

cp --reflink=auto "$img" "$new/backgrounds/$slug.$ext"
cp --reflink=auto "$img" "$new/preview.$ext"
[[ -f $work/gen/icons.theme ]] && cp "$work/gen/icons.theme" "$new/icons.theme"
echo aether >"$new/.aether-managed"

mkdir -p "$THEMES"
if [[ -d $THEMES/$slug ]]; then
  mv "$THEMES/$slug" "$work/old"
fi
mv "$new" "$THEMES/$slug"

omarchy-theme-set "$slug" && notify "Theme created" "$slug"
