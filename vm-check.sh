#!/bin/bash
# Runs inside the Omarchy VM (vm-test). Same script for both AktOn1 layer plugins; it picks the engine from PLUGIN_ID.
# Checks: engine answers over IPC, owns its layer, snapshot published, Connect/Split write and clear, panel opens alone and connected,
# migration from the old Hub state, no second launch of startup apps.
export HOME=${HOME:-/home/tester}
case $PLUGIN_ID in
  *scratchpad-frame) E=scratchpad-frame; OTHER=fullscreen-app-auto-workspace ;;
  *fullscreen-app-auto-workspace) E=fullscreen-app-auto-workspace; OTHER=scratchpad-frame ;;
  *) echo "unknown plugin $PLUGIN_ID"; exit 1 ;;
esac
RT=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
ipc() { omarchy-shell "$@" 2>&1; }
snap() { ipc $E.layers state; }

n=0; until [ -s "$RT/$E/snapshot.json" ] || [ $n -ge 20 ]; do sleep 1; n=$((n+1)); done
[ -s "$RT/$E/snapshot.json" ] && ok "snapshot.json published" || bad "no snapshot.json in $RT/$E"

s=$(snap)
jq -e '.state' <<<"$s" >/dev/null 2>&1 && ok "IPC $E.layers state returns JSON" || bad "IPC state: ${s:0:120}"

if [ $E = scratchpad-frame ]; then
  jq -e '.state.pads|map(.id)|index("scratchpad")' <<<"$s" >/dev/null && ok "built-in scratchpad listed" || bad "no built-in scratchpad"
  r=$(ipc $E.layers padAdd "Check Pad" right); [ "$r" = check-pad ] && ok "padAdd" || bad "padAdd: $r"
  ipc $E.layers padSet check-pad outDirection bottom >/dev/null; ipc $E.layers padSet check-pad effect bounce >/dev/null; ipc $E.layers padSet check-pad outEffect fade >/dev/null
  sleep 2
  jq -e '.state.pads[]|select(.id=="check-pad")|.direction=="right" and .outDirection=="bottom" and .effect=="bounce" and .outEffect=="fade"' <<<"$(snap)" >/dev/null && ok "pad in/out motion in snapshot" || bad "pad motion missing in snapshot"
  sleep 3
  grep -q check-pad ~/.local/state/scratchpad-frame/pads.json 2>/dev/null && ok "new pad reaches Frame (pads.json)" || bad "pad did not reach pads.json"
  r=$(ipc $E.layers padRemove check-pad); [ "$r" = ok ] && ok "padRemove" || bad "padRemove: $r"
else
  jq -e '.state.layer.id' <<<"$s" >/dev/null && ok "fullscreen layer listed" || bad "no fullscreen layer"
  r=$(ipc $E.layers appAdd fullscreen "foot -e sleep 600"); [ "$r" = ok ] && ok "appAdd" || bad "appAdd: $r"
  r=$(ipc $E.layers appRemove fullscreen 0); [ "$r" = ok ] && ok "appRemove" || bad "appRemove: $r"
  r=$(ipc $E.layers padSet fullscreen direction right); [ "$r" = ok ] && ok "layer slide direction set" || bad "padSet direction: $r"
  sleep 2
  jq -e '.state.layer.direction=="right"' <<<"$(snap)" >/dev/null && ok "layer direction in snapshot" || bad "layer direction missing in snapshot"
  ipc $E.layers padSet fullscreen direction bottom >/dev/null
fi

# Frame designer: the AI recipe path over IPC (no AI is called), plus the offline self-tests
if [ $E = scratchpad-frame ]; then
  P=$(jq -r '.pads[0].name' <<<"$(ipc scratchpad-frame state)" 2>/dev/null)
  R='{"name":"Mossy night","style":"FOLIAGE","colors":{"accent":"#2e8b57","background":"#0b1a12"}}'
  r=$(ipc scratchpad-frame previewLook "$P" "$R"); [ "$r" = ok ] && ok "frame designer: recipe previews" || bad "previewLook: $r"
  sleep 1; [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/look-preview.png" 2>/dev/null
  r=$(ipc scratchpad-frame previewLook "$P" '{"style":"NOPE"}'); case $r in error*) ok "frame designer: unknown style rejected";; *) bad "bad style accepted: $r";; esac
  r=$(ipc scratchpad-frame previewLook "$P" '{"style":"FROST","colors":{"accent":"url(x)"}}'); case $r in error*) ok "frame designer: code-like colour rejected";; *) bad "bad colour accepted: $r";; esac
  ipc scratchpad-frame previewEnd >/dev/null
  r=$(ipc scratchpad-frame lookSet "$P" "$R"); [ "$r" = ok ] && ok "frame designer: Apply" || bad "lookSet: $r"
  sleep 1
  jq -e --arg p "$P" '.looks[$p].style=="FOLIAGE" and .looks[$p].colors.accent=="#2e8b57"' <<<"$(ipc scratchpad-frame state)" >/dev/null && ok "frame designer: recipe in state" || bad "recipe missing from state"
  jq -e --arg p "$P" '.[$p].style=="FOLIAGE"' ~/.local/state/scratchpad-frame/looks.json >/dev/null 2>&1 && ok "frame designer: looks.json written" || bad "looks.json not written"
  r=$(ipc scratchpad-frame lookClear "$P"); [ "$r" = ok ] && ok "frame designer: Remove" || bad "lookClear: $r"
  jq -e --arg p "$P" '.looks|has($p)|not' <<<"$(ipc scratchpad-frame state)" >/dev/null && ok "frame designer: recipe gone" || bad "recipe still in state"
  ipc scratchpad-frame.bar pick "$P" >/dev/null; sleep 3
  [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/picker-designer.png" 2>/dev/null
  ipc scratchpad-frame.bar close >/dev/null
  # Ornaments from the user's own image model: a stand-in server plays both the text AI and the image model (nothing real is called)
  if command -v python3 >/dev/null && [ -f "$PLUGIN_DIR/tests/standin.py" ]; then
    FA="python3 $PLUGIN_DIR/bin/frame-ai"; SEEN=/tmp/standin-seen.jsonl; PORT=18199; ST=~/.local/state/scratchpad-frame
    rm -f $SEEN; setsid nohup python3 "$PLUGIN_DIR/tests/standin.py" $PORT --seen $SEEN >/dev/null 2>&1 </dev/null & echo $! >/tmp/standin.pid
    n=0; until (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null || [ $n -ge 10 ]; do sleep 1; n=$((n+1)); done
    if python3 -c "import PIL" 2>/dev/null; then ok "ornaments: picture engine: Pillow"; elif command -v magick >/dev/null; then ok "ornaments: picture engine: ImageMagick (Pillow not installed)"; else bad "ornaments: neither Pillow nor ImageMagick found"; fi
    [ "$($FA image providers --json | jq -r .ornaments)" = false ] && ok "ornaments: box is off by default" || bad "ornaments: box not off by default"
    ipc $E.panel open >/dev/null; sleep 2; ipc $E.cards show edit scratchpad-frame scratchpad >/dev/null; sleep 3
    [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/picker-designer-ornaments-off.png" 2>/dev/null
    ipc $E.panel close >/dev/null
    $FA image use comfyui --comfy-url http://127.0.0.1:$PORT --checkpoint standin-model.safetensors --json >/dev/null
    $FA use endpoint --url http://127.0.0.1:$PORT/v1 --json >/dev/null; $FA use --model m --json >/dev/null
    r=$($FA image test --json); jq -e '.ok and (.message|test("1 checkpoint"))' <<<"$r" >/dev/null && ok "ornaments: Test connection against the stand-in image server" || bad "image test: $r"
    r=$($FA image checkpoints --json); jq -e '.checkpoints==["standin-model.safetensors"]' <<<"$r" >/dev/null && ok "ornaments: checkpoint list from the server" || bad "image checkpoints: $r"
    [ ! -s $SEEN ] && ok "ornaments: nothing sent before Make frame" || bad "something was sent before Make frame: $(head -c 200 $SEEN)"
    $FA image use --ornaments 1 --json >/dev/null
    ipc $E.panel open >/dev/null; sleep 2; ipc $E.cards show edit scratchpad-frame scratchpad >/dev/null; sleep 3
    [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/picker-designer-ornaments-on.png" 2>/dev/null
    ipc $E.panel close >/dev/null
    r=$($FA make "calm night forest in mossy greens" --ornaments --json | tail -1)
    O=$(jq -r '.recipe.ornament // empty' <<<"$r")
    jq -e '.ok and .recipe.style=="OWNART" and (.recipe.ornament|test("^[0-9a-f]{12}$"))' <<<"$r" >/dev/null && ok "ornaments: Make frame (ticked) made an ornament" || bad "make --ornaments: ${r:0:300}"
    [ -n "$O" ] && [ -s "$ST/ornaments/$O.png" ] && ok "ornaments: stored in the state folder by id" || bad "ornament file missing"
    jq -r 'select(.path=="/prompt")|.body|tostring' $SEEN | grep -q "fern fronds" && ! jq -r 'select(.path=="/prompt")|.body|tostring' $SEEN | grep -qi "calm night forest" && ok "ornaments: image model got only the ornament description" || bad "image model request has the wrong content"
    R2=$(jq -c '.recipe' <<<"$r")
    r=$(ipc scratchpad-frame previewLook "$P" "$R2"); [ "$r" = ok ] && ok "ornaments: preview" || bad "previewLook ornament: $r"
    sleep 2; [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/ornament-preview.png" 2>/dev/null
    r=$(ipc scratchpad-frame previewLook "$P" '{"style":"OWNART","ornament":"../../etc/passwd"}'); case $r in ok*) ipc scratchpad-frame state | grep -q passwd && bad "a path was kept as an ornament" || ok "ornaments: a path is never used as an ornament id";; *) ok "ornaments: a path as an ornament id is rejected";; esac
    ipc scratchpad-frame previewEnd >/dev/null
    r=$(ipc scratchpad-frame lookSet "$P" "$R2"); [ "$r" = ok ] && ok "ornaments: Apply" || bad "lookSet ornament: $r"
    sleep 3; [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/ornament-applied.png" 2>/dev/null
    (foot -e sleep 30 >/dev/null 2>&1 &) ; sleep 1
    hyprctl eval "__akton1_scratchpad_frame.toggle('scratchpad','bottom')" >/dev/null; sleep 4
    [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/ornament-applied-pad-open.png" 2>/dev/null
    hyprctl eval "__akton1_scratchpad_frame.toggle('scratchpad','bottom')" >/dev/null; sleep 1; pkill -x foot
    jq -e --arg p "$P" --arg o "$O" '.[$p].ornament==$o' $ST/looks.json >/dev/null 2>&1 && [ -s "$ST/ornaments/$O.png" ] && ok "ornaments: applied look keeps its ornament" || bad "applied ornament missing"
    r=$(ipc scratchpad-frame lookClear "$P"); [ "$r" = ok ] && ok "ornaments: Remove" || bad "lookClear ornament: $r"
    n=0; until [ ! -e "$ST/ornaments/$O.png" ] || [ $n -ge 10 ]; do sleep 1; n=$((n+1)); done
    [ ! -e "$ST/ornaments/$O.png" ] && ok "ornaments: Remove left no orphan file" || bad "orphan ornament left: $(ls $ST/ornaments)"
    r=$($FA make "calm night forest" --ornaments --json | tail -1); O2=$(jq -r '.recipe.ornament // empty' <<<"$r")
    $FA ornaments drop "$O2" --json >/dev/null; [ -n "$O2" ] && [ ! -e "$ST/ornaments/$O2.png" ] && ok "ornaments: Discard deletes the unsaved ornament" || bad "discarded ornament still there"
    $FA image use comfyui --comfy-url http://127.0.0.1:9 --json >/dev/null
    r=$($FA make "calm night forest" --ornaments --json | tail -1)
    jq -e '.ok and .recipe.style=="FOLIAGE" and (.note|test("normal frame"))' <<<"$r" >/dev/null && ok "ornaments: image model down gives the normal frame and a plain note" || bad "fallback: ${r:0:200}"
    kill "$(cat /tmp/standin.pid)" 2>/dev/null
    $FA image use --ornaments 0 --json >/dev/null
  fi
  if command -v python3 >/dev/null; then
    out=$(python3 "$PLUGIN_DIR/bin/frame-ai" selftest 2>&1); case $out in *"selftest: PASS"*) ok "frame designer: offline self-test";; *) bad "frame-ai selftest: ${out: -200}";; esac
  fi
fi

ipc $E.panel open >/dev/null; sleep 2
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/alone.png" 2>/dev/null
if [ $E = scratchpad-frame ]; then
  ipc $E.cards show edit scratchpad-frame scratchpad >/dev/null; sleep 2
  [ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/alone-pad.png" 2>/dev/null
fi
ipc $E.panel close >/dev/null
r=$(ipc $E.cards combine $OTHER on); [ "$r" = ok ] && ok "connect" || bad "connect: $r"
sleep 1
jq -e '.members|length>0' ~/.local/state/akton1/combine.json >/dev/null 2>&1 && ok "combine.json written" || bad "combine.json empty"
ipc $E.cards show grid x x >/dev/null
ipc $E.panel open >/dev/null
sleep 2
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/connected.png" 2>/dev/null
ipc $E.cards show edit scratchpad-frame scratchpad >/dev/null; sleep 1
[ -n "$VM_TEST_OUT" ] && grim "$VM_TEST_OUT/connected-pad.png" 2>/dev/null
ipc $E.panel close >/dev/null
r=$(ipc $E.cards combine $OTHER off); [ "$r" = ok ] && ok "split" || bad "split: $r"
sleep 1
jq -e '.members|length==0' ~/.local/state/akton1/combine.json >/dev/null 2>&1 && ok "combine.json cleared" || bad "combine.json not cleared"

# migration from the Hub: layers.json gone + Hub state present -> engine imports it on the next start
mkdir -p ~/.local/state/akton1-hub
if [ $E = scratchpad-frame ]; then
  echo '{"pads":[{"id":"scratchpad","label":"Scratchpad","builtin":true,"direction":"bottom"},{"id":"hubpad","label":"Hub Pad","direction":"right"}]}' >~/.local/state/akton1-hub/state.json
  want='.state.pads|map(.id)|index("hubpad")'
else
  echo '{"fullscreen":{"label":"Fullscreen","apps":["foot -e sleep 601"]}}' >~/.local/state/akton1-hub/state.json
  want='.state.layer.apps|index("foot -e sleep 601")'
fi
rm -f ~/.local/state/$E/layers.json
omarchy-restart-shell >/dev/null 2>&1; sleep 8
s=$(snap)
jq -e "$want" <<<"$s" >/dev/null 2>&1 && ok "Hub state migrated" || bad "Hub state not migrated: ${s:0:160}"
rm -rf ~/.local/state/akton1-hub

# two-monitor behaviour (no fly-in from the other screen, no re-open after a flyout), Scratchpad Frame only
if [ $E = scratchpad-frame ] && [ -f "$PLUGIN_DIR/tests/vm-check-fullscreen.sh" ]; then
  bash "$PLUGIN_DIR/tests/vm-check-fullscreen.sh" && ok "fullscreen checks passed" || bad "fullscreen checks failed (see lines above)"
fi

if [ $E = scratchpad-frame ] && [ -f "$PLUGIN_DIR/tests/vm-check-instant.sh" ]; then
  bash "$PLUGIN_DIR/tests/vm-check-instant.sh" && ok "instant-pad checks passed" || bad "instant-pad checks failed (see lines above)"
fi

if [ $E = scratchpad-frame ] && [ -f "$PLUGIN_DIR/tests/vm-check-monitors.sh" ]; then
  bash "$PLUGIN_DIR/tests/vm-check-monitors.sh" && ok "two-monitor checks passed" || bad "two-monitor checks failed (see lines above)"
fi

if [ -n "$VM_TEST_OUT" ]; then
  q=$(quickshell log -p /usr/share/omarchy/shell --any-display 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'AktEngine|AktPanel|AktSource|AktTile|AktPresence' | grep -E 'ERROR|TypeError|ReferenceError|unavailable' | head -3)
  [ -z "$q" ] && ok "no Akt* QML errors" || bad "QML errors: $q"
fi
exit $fail
