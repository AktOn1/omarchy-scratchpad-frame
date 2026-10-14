#!/bin/bash
# Runs inside the Omarchy VM (called from vm-check.sh for Scratchpad Frame). A window of the open pad goes fullscreen (SUPER + F):
# its frame must then cover the whole monitor above the window, and drop back under the bar when the fullscreen ends.
export HOME=${HOME:-/home/tester}
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
hl() { hyprctl dispatch "$1" >/dev/null; }
G=__akton1_scratchpad_frame
MON=$(hyprctl monitors -j | jq -r '.[0].name'); MW=$(hyprctl monitors -j | jq -r '.[0].width'); MH=$(hyprctl monitors -j | jq -r '.[0].height')
# prints "<level> <w>x<h>" of every scratchpad-frame layer of the monitor that is on screen (x within the monitor)
frames() { hyprctl -j layers | jq -r --arg m "$MON" '.[$m].levels|to_entries[]|.key as $l|.value[]|select(.namespace=="scratchpad-frame" and .x>=0 and .x<2000)|"\($l) \(.w)x\(.h)"'; }

pkill foot
hyprctl eval "$G.toggle('scratchpad','bottom')" >/dev/null; sleep 1
foot -T padterm >/dev/null 2>&1 &
sleep 3
sleep 1
f=$(frames)
echo "before fullscreen: $(echo "$f" | tr '\n' ',')"
echo "$f" | grep -q "^3 " && bad "frame already above windows before fullscreen" || ok "frame under the windows before fullscreen"
hl 'hl.dsp.window.fullscreen({ mode = "fullscreen" })'; sleep 2
cl=$(hyprctl -j clients | jq -r '[.[]|select(.fullscreen==2)]|length')
[ "$cl" -ge 1 ] && ok "a pad window is fullscreen" || bad "no window is fullscreen ($cl)"
f=$(frames)
echo "fullscreen: $(echo "$f" | tr '\n' ',')"
echo "$f" | grep -q "^3 ${MW}x${MH}$" && ok "frame covers the whole monitor above the window" || bad "frame not over the fullscreen window ($f)"
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/frame-fullscreen.png"
hl 'hl.dsp.window.fullscreen({ mode = "fullscreen" })'; sleep 2
f=$(frames)
echo "after: $(echo "$f" | tr '\n' ',')"
echo "$f" | grep -q "^3 " && bad "frame still above windows after leaving fullscreen" || ok "frame back under the windows after leaving fullscreen"
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/frame-windowed.png"
hyprctl eval "$G.toggle('scratchpad','bottom')" >/dev/null; sleep 1; pkill foot
exit $fail
