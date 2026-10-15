#!/bin/bash
# Runs inside the Omarchy VM (called from vm-check.sh for Scratchpad Frame). A pad whose way in and out is "instant"
# must take its frame away again when it closes (the frame once stayed on screen forever).
export HOME=${HOME:-/home/tester}
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
G=__akton1_scratchpad_frame
MON=$(hyprctl monitors -j | jq -r '.[0].name')
tog() { hyprctl eval "$G.toggle('scratchpad','bottom')" >/dev/null; }
# sampled pixels of the left half, below the bar, that differ between two screenshots
shotdiff() {
  python3 - "$1" "$2" <<'PY'
import sys
def load(f):
    d=open(f,'rb').read(); p=d.split(b'\n',3); w,h=map(int,p[1].split()); return w,h,p[3]
w,h,a=load(sys.argv[1]); _,_,b=load(sys.argv[2]); n=0
for y in range(60,h,3):
    for x in range(0,w//2,3):
        i=(y*w+x)*3
        if abs(a[i]-b[i])+abs(a[i+1]-b[i+1])+abs(a[i+2]-b[i+2])>60: n+=1
print(n)
PY
}
pkill foot
[ -n "$(hyprctl monitors -j | jq -r '.[0].specialWorkspace.name')" ] && { tog; sleep 2; }
omarchy-shell scratchpad-frame.layers padSet scratchpad effect instant >/dev/null; sleep 2
grim -t ppm -o "$MON" /tmp/instant-base.ppm
tog; sleep 1.5
foot -T padterm >/dev/null 2>&1 &
sleep 3
grim -t ppm -o "$MON" /tmp/instant-open.ppm
d=$(shotdiff /tmp/instant-base.ppm /tmp/instant-open.ppm)
[ "$d" -gt 200 ] && ok "frame and window show while the instant pad is open ($d differing samples)" || bad "instant pad shows nothing ($d differing samples)"
tog; sleep 2
pkill foot; sleep 1
grim -t ppm -o "$MON" /tmp/instant-closed.ppm
[ -n "$VM_TEST_OUT" ] && grim -o "$MON" "$VM_TEST_OUT/instant-closed.png"
d=$(shotdiff /tmp/instant-base.ppm /tmp/instant-closed.ppm)
[ "$d" -lt 200 ] && ok "no frame left behind after the instant pad closed ($d differing samples)" || bad "frame left hanging after the instant pad closed ($d differing samples)"
omarchy-shell scratchpad-frame.layers padSet scratchpad effect "" >/dev/null
exit $fail
