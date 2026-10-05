#!/bin/bash
# Dev helper: the shell runs with QS_DISABLE_FILE_WATCHER=1 and `shell rescanPlugins` does not
# re-read changed QML/JS, so restart the shell to load edits to this plugin.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
omarchy-restart-shell && sleep 8 && omarchy-shell scratchpad-frame list
