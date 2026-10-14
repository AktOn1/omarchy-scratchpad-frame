#!/bin/bash
# Runs inside the Omarchy VM (called from vm-check.sh for Scratchpad Frame). Two monitors, slowed animations:
#  1. a pad opened on the second monitor after the first must slide in from its own side only (its windows never sit on the first monitor's side),
#  2. the window move animation is back on afterwards,
#  3. a foreign layer (walker) closing right before the pad opens must not hide the pad again,
#  4. a real flyout of the shell (the style picker) closing must not bring a hidden pad back.
export HOME=${HOME:-/home/tester}
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
hl() { hyprctl dispatch "$1" >/dev/null; }
mons() { hyprctl monitors -j; }
G=__akton1_scratchpad_frame
# Default: the toggle the plugin's SUPER + S binding calls (wtype does not trigger binds in the VM). Manual run with TOG_WAIT=1:
# a host-side loop presses the real key over QMP (omarchy-vm key meta_l-s) whenever /tmp/tog.req appears.
tog() {
  if [ -n "$TOG_WAIT" ]; then rm -f /tmp/tog.ack; touch /tmp/tog.req; until [ -e /tmp/tog.ack ]; do sleep 0.1; done
  else hyprctl eval "$G.toggle('scratchpad','bottom')" >/dev/null; fi
}
active_special() { mons | jq -r --arg m "$1" '.[]|select(.name==$m)|.specialWorkspace.name'; }

pkill foot; for m in $(mons | jq -r '.[]|select(.name|startswith("HEADLESS"))|.name'); do hyprctl output remove "$m" >/dev/null; done
for m in $(mons | jq -r '.[]|select(.specialWorkspace.name!="")|.name'); do hl "hl.dsp.focus({monitor=\"$m\"})"; tog; sleep 1; done
hyprctl output create headless >/dev/null; sleep 1
FIRST=$(mons | jq -r '.[0].name'); SECOND=$(mons | jq -r '[.[]|select(.name|startswith("HEADLESS"))][0].name')
[ -n "$SECOND" ] || { bad "no second monitor"; exit 1; }
hyprctl eval "hl.monitor({ output = \"$FIRST\", mode = \"1280x800@60\", position = \"0x0\", scale = 1 })" >/dev/null
hyprctl eval "hl.monitor({ output = \"$SECOND\", mode = \"1280x800@60\", position = \"1280x0\", scale = 1 })" >/dev/null; sleep 1
SX=$(mons | jq -r --arg m "$SECOND" '.[]|select(.name==$m)|.x'); SW=$(mons | jq -r --arg m "$SECOND" '.[]|select(.name==$m)|.width')

# window move animation slowed to 3 s: a window that still has to travel from the first monitor is easy to catch (the plugin reads this when it starts)
hyprctl eval 'hl.animation({leaf="windowsMove",enabled=true,speed=30,bezier="default"})' >/dev/null
omarchy-restart-shell >/dev/null 2>&1; sleep 9

hyprctl binds -j | jq -e '.[]|select(.description|test("AktOn1.*toggle Scratchpad"))' >/dev/null && ok "SUPER + S is handled by the plugin (move snap applies)" || bad "SUPER + S still Omarchy's plain binding: the fly-in cannot be stopped"
hl "hl.dsp.focus({monitor=\"$FIRST\"})"; sleep 0.3
tog; sleep 0.5
foot -T padterm -o colors-dark.background=ff00ff >/dev/null 2>&1 &
sleep 4
tog; sleep 4
hl "hl.dsp.focus({monitor=\"$SECOND\"})"; sleep 0.3
mkdir -p /tmp/frames; rm -f /tmp/frames/*
tog
i=0
while [ $i -lt 12 ]; do grim -s 0.25 -o "$SECOND" -t ppm /tmp/frames/f$i.ppm; i=$((i+1)); done
# per frame: how many magenta (the pad's terminal) pixels sit left of the second monitor's middle, and the left-most magenta column
res=$(python3 - "$SW" <<'PY'
import sys,glob
W=int(sys.argv[1]); out=[]
for f in sorted(glob.glob('/tmp/frames/f*.ppm'), key=lambda x:int(x.split('/f')[-1][:-4])):
    d=open(f,'rb').read(); parts=d.split(b'\n',3); w,h=map(int,parts[1].split()); px=parts[3]
    mn=None; cnt=0
    for y in range(0,h,8):
        row=px[y*w*3:(y+1)*w*3]
        for x in range(0,w,4):
            r,g,b=row[x*3],row[x*3+1],row[x*3+2]
            if r>200 and g<60 and b>200:
                cnt+=1
                if mn is None or x<mn: mn=x*100//w
    out.append((mn,cnt))
print(' '.join('%s/%d'%(m,c) for m,c in out))
PY
)
echo "frames (left-most magenta column in % of width / samples): $res"
[ -n "$VM_TEST_OUT" ] && grim -o "$SECOND" "$VM_TEST_OUT/second-monitor-after-slide.png"
# from the 4th frame on (the 300 ms slide is over) the window must sit still; a fly-in from the first monitor keeps it moving for the 3 s move animation
late=$(echo "$res" | tr ' ' '\n' | tail -n +4 | cut -d/ -f1)
lo=$(echo "$late" | sort -n | head -1); hi=$(echo "$late" | sort -n | tail -1)
if [ "$lo" = None ] || [ "$hi" = None ]; then bad "pad window not seen in the later frames ($res)"
elif [ $((hi - lo)) -le 1 ]; then ok "pad window sat still once the slide ended (left edge $lo%..$hi%)"
else bad "pad window kept moving after the slide ended (left edge $lo%..$hi%): it flew in from the other monitor"; fi
sleep 3
en=$(hyprctl -j animations | jq -r '.[0][]|select(.name=="windowsMove")|.enabled')
[ "$en" = true ] && ok "window move animation is back on" || bad "window move animation left off ($en)"
tog; sleep 4
[ -z "$(active_special "$SECOND")" ] && ok "pad closes again" || bad "pad did not close"

# 3. foreign layer closing right before the pad opens (focus changes first)
hl "hl.dsp.focus({monitor=\"$FIRST\"})"; sleep 0.5
cat >/tmp/foreign.qml <<'QML'
import Quickshell
import Quickshell.Wayland
PanelWindow {
  anchors.top: true
  implicitWidth: 120; implicitHeight: 40
  WlrLayershell.namespace: "foreign-test"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  exclusionMode: ExclusionMode.Ignore
}
QML
quickshell -n -p /tmp/foreign.qml >/dev/null 2>&1 &
FPID=$!
sleep 3
hyprctl layers | grep -q foreign-test && ok "foreign layer is open" || bad "foreign layer did not open"
kill $FPID; sleep 0.05
hl "hl.dsp.focus({monitor=\"$SECOND\"})"
tog; sleep 5
[ "$(active_special "$SECOND")" = special:scratchpad ] && ok "pad stays open after a foreign layer closed just before" || bad "pad was hidden again after a foreign layer closed"
tog; sleep 4

# 4. real flyout of the shell: closing it must not bring a hidden pad back
hl "hl.dsp.focus({monitor=\"$FIRST\"})"; sleep 0.3
tog; sleep 4
hl 'hl.dsp.focus({window="title:padterm"})'; sleep 0.3
tog; sleep 4
omarchy-shell scratchpad-frame menu >/dev/null 2>&1; sleep 2
wtype -k Escape; sleep 3
[ -z "$(active_special "$FIRST")" ] && ok "hidden pad stays hidden after a shell flyout closes" || bad "hidden pad popped open after the flyout closed"
[ -n "$VM_TEST_OUT" ] && grim -o "$FIRST" "$VM_TEST_OUT/after-flyout.png"
pkill foot
exit $fail
