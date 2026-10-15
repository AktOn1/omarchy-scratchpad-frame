#!/bin/bash
# Runs inside the Omarchy VM (called from vm-check.sh for Scratchpad Frame). Card mode: a second scratchpad opens beside the
# first instead of closing it, closing the first hands the screen to the second, closing the last one empties the screen.
# Reload: a listed app of a pad with "Reload in the background" comes back hidden on its pad when its window is closed.
export HOME=${HOME:-/home/tester}
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
G=__akton1_scratchpad_frame
L="omarchy-shell scratchpad-frame.layers"
tog() { hyprctl eval "$G.toggle('$1','$2')" >/dev/null; }
special() { hyprctl monitors -j | jq -r '.[0].specialWorkspace.name'; }
wsof() { hyprctl clients -j | jq -r --arg t "$1" '.[]|select(.title==$t)|.workspace.name' | head -1; }
addr() { hyprctl clients -j | jq -r --arg t "$1" '.[]|select(.title==$t)|.address' | head -1; }
send() { hyprctl dispatch "hl.dsp.window.move({workspace=\"$2\", follow=false, window=\"address:$(addr "$1")\"})" >/dev/null; }

pkill -x foot; sleep 1
[ -n "$(special)" ] && { tog scratchpad bottom; sleep 2; }
$L padAdd Cardtwo right >/dev/null; sleep 1
$L mode card >/dev/null; sleep 1
[ "$($L state | jq -r .state.mode)" = card ] && ok "cards: mode switch is saved" || bad "cards: mode not saved"

foot -T cardone -e sleep 900 >/dev/null 2>&1 &
foot -T cardtwo -e sleep 900 >/dev/null 2>&1 &
sleep 3
send cardone special:scratchpad; send cardtwo special:cardtwo; sleep 1

tog scratchpad bottom; sleep 2
tog cardtwo right; sleep 3
[ "$(special)" = special:scratchpad ] && [ "$(wsof cardone)" = special:scratchpad ] && [ "$(wsof cardtwo)" = special:scratchpad ] && ok "cards: second pad opens beside the first" || bad "cards: open=$(special) one=$(wsof cardone) two=$(wsof cardtwo)"
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/cards-two-open.png" 2>/dev/null

tog scratchpad bottom; sleep 3
[ "$(special)" = special:cardtwo ] && [ "$(wsof cardone)" = special:scratchpad ] && [ "$(wsof cardtwo)" = special:cardtwo ] && ok "cards: closing the first leaves the second open, first goes home" || bad "cards: after closing first: open=$(special) one=$(wsof cardone) two=$(wsof cardtwo)"
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/cards-first-closed.png" 2>/dev/null

tog cardtwo right; sleep 2
[ -z "$(special)" ] && ok "cards: closing the last card empties the screen" || bad "cards: still open: $(special)"

$L mode single >/dev/null; sleep 1
tog scratchpad bottom; sleep 2
tog cardtwo right; sleep 2
[ "$(special)" = special:cardtwo ] && [ "$(wsof cardone)" = special:scratchpad ] && ok "cards: single mode still closes the other pad" || bad "single mode: open=$(special) one=$(wsof cardone)"
tog cardtwo right; sleep 1
pkill -x foot; sleep 1

# reload
$L padSet cardtwo reload on >/dev/null
$L appAdd cardtwo "foot -T reloaded -e sleep 900" >/dev/null
$L appsStart cardtwo >/dev/null; sleep 5
p1=$(hyprctl clients -j | jq -r '.[]|select(.title=="reloaded")|.pid' | head -1)
[ "$(wsof reloaded)" = special:cardtwo ] && ok "reload: the app is on its pad" || bad "reload: app not on its pad ($(wsof reloaded))"
hyprctl dispatch "hl.dsp.window.close({window=\"address:$(addr reloaded)\"})" >/dev/null; sleep 5
p2=$(hyprctl clients -j | jq -r '.[]|select(.title=="reloaded")|.pid' | head -1)
[ -n "$p2" ] && [ "$p2" != "$p1" ] && [ "$(wsof reloaded)" = special:cardtwo ] && [ -z "$(special)" ] && ok "reload: closed app came back hidden on its pad" || bad "reload: p1=$p1 p2=$p2 ws=$(wsof reloaded) open=$(special)"
$L padSet cardtwo reload off >/dev/null; sleep 1
hyprctl dispatch "hl.dsp.window.close({window=\"address:$(addr reloaded)\"})" >/dev/null; sleep 5
[ -z "$(addr reloaded)" ] && ok "reload: off means the app stays closed" || bad "reload: came back with reload off"
$L padRemove cardtwo >/dev/null
pkill -x foot
exit $fail
