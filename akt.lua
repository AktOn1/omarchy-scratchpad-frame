-- AktOn1 scratchpad runtime inside Hyprland, shared by the AktOn1 plugins (Scratchpad Frame, Fullscreen App Auto Workspace).
-- Loaded by the plugin's service through `hyprctl eval`. Only raw Hyprland Lua (hl.*),
-- no network, no os.execute / io.popen. Everything it registers is tracked so
-- M.stop() puts the desktop back (the Omarchy SUPER + S binding included).
-- Each plugin keeps its own copy in its own Lua global (the name passed to this chunk), so they never touch each other's keys.
--
-- M.start(cfg): cfg.label = text for the binding descriptions (also how the plugin recognises its own bindings)
--               cfg.pads  = { { id, key, moveKey, direction, outDirection, effect, outEffect, label, builtin } ... }
--               cfg.motions = { [id] = { direction, outDirection, effect, outEffect } }  (every pad, also those without a key here: how each one comes in and goes out)
--               cfg.effects = { [id] = { style, speed, curve } }  (the motion effects; "slide" follows the user's own animation settings)
--               cfg.commands = { { key, command, label } ... }  (plain shell commands on a key)
--               cfg.layouts = { { id, layout } ... }  (workspace layout per special workspace, "" = Hyprland's own)
--               cfg.anim  = { specialWorkspaceIn = {enabled, speed, bezier, style}, specialWorkspaceOut = ... }
--               cfg.mode  = "single" (default: opening a pad hides the open one) or "card" (opening a pad leaves the open ones; see Cards below)
--               cfg.move  = windowsMove animation as configured {enabled, speed, bezier, style}; switched off while a pad opens on another monitor
-- M.slide(direction, fn, motion): run fn with the special workspace animation set for that direction (motion = { outDirection, effect, outEffect } optional)
-- M.launch(id, command): start a command on special:<id> without showing it
-- M.close(address): close one window (a normal close request, the app may ask to save)
-- M.shutdown(): stop and also give back the layouts this module set and send every card's windows home
--
-- Cards (cfg.mode = "card"): Hyprland shows one special workspace per monitor, so a second open pad borrows the open one.
-- Its windows are moved (silently) onto the shown special workspace and go home when the card is closed or the stack ends.
-- stack[monitor] = { host = <shown pad>, guests = { { id, addrs = {window addresses} } ... } }
-- Every change is announced to the shell as the Hyprland custom event  akt-cards|<monitor>|<host>|<id>:<addr>,<addr>|<id>:...

return function(global_name)
  local previous = rawget(_G, global_name)
  if previous and previous.stop then
    pcall(previous.stop)
  end

  local M = {}
  -- Layouts set per special workspace; kept across a reload of this file so a cleared one can be undone.
  local layouts = (previous and previous.layouts) or {}
  M.layouts = layouts
  local binds, restores = {}, {}
  local anim = nil
  local move = nil
  local move_off = false
  local prefix = "AktOn1: "
  local restore_id = 0
  local effects = {}
  local motions = {}
  local mode = "single"
  local stack = (previous and previous.stack) or {}
  M.stack = stack
  local subs = {}

  local function set_leaf(leaf, spec, style)
    pcall(hl.animation, {
      leaf = leaf,
      enabled = spec.enabled ~= false,
      speed = tonumber(spec.speed) or 3,
      bezier = spec.bezier or "default",
      style = style or spec.style or "",
    })
  end

  local function restore_move()
    if move_off and move then set_leaf("windowsMove", move) end
    move_off = false
  end

  -- True when the pad's windows still sit on another monitor than the one it is about to open on:
  -- Hyprland then moves them to the new monitor with the window move animation, so they fly in sideways.
  local function pad_elsewhere(id)
    local target = hl.get_active_monitor()
    if not target then return false end
    for _, window in ipairs(hl.get_windows()) do
      if window.workspace and window.workspace.name == "special:" .. id and window.monitor then
        local a, b = window.monitor, target
        if (a.name and b.name and a.name ~= b.name) or (not (a.name and b.name) and a.id ~= b.id) then
          return true
        end
      end
    end
    return false
  end

  -- The animation spec for one leaf (specialWorkspaceIn or Out) of a pad that moves with `effect` on `side`.
  -- Hyprland slides a special workspace from the right ("slide") or the bottom ("slidevert") and ignores any
  -- direction word after the style, so the side picks the style itself.
  local function leaf_spec(leaf, effect, side)
    local base = (anim and anim[leaf]) or {}
    local vert = side ~= "right" and side ~= "left"
    local fx = effects[effect]
    if not fx or effect == "slide" then
      return { enabled = base.enabled ~= false, speed = tonumber(base.speed) or 3, bezier = base.bezier or "default", style = vert and "slidevert" or "slide" }
    end
    if fx.style == "none" then return { enabled = false } end
    local style = fx.style
    if style == "slide" then
      style = vert and "slidevert" or "slide"
    elseif style == "slidefade" then
      style = vert and "slidefadevert" or "slidefade"
    end
    return { enabled = true, speed = tonumber(fx.speed) or 3, bezier = "akt_" .. effect, style = style }
  end

  -- The id of the pad that is open on the monitor in use, or nil.
  local function open_pad()
    local ok, special = pcall(function()
      local monitor = hl.get_active_monitor()
      return monitor and (monitor.active_special_workspace or monitor.special_workspace or monitor.specialWorkspace)
    end)
    if ok and special and type(special.name) == "string" and special.name:sub(1, 8) == "special:" then return special.name:sub(9) end
    return nil
  end

  -- Hyprland's special workspace animation is one setting for all special workspaces, so a pad sets
  -- its own just before it moves and the original comes back after. A pad that comes in uses the
  -- "in" leaf; the one that goes out uses the "out" leaf (the pad that is open, when another one comes in).
  -- Opening on another monitor also switches the window move animation off for the same time.
  -- plan = { enter = { effect, side }, leave = { effect, side } }
  local function with_motion(plan, fn, snap)
    local snapping = snap and move ~= nil
    if not anim and not snapping then
      fn()
      return
    end
    local longest = snapping and 300 or 0
    local specs = {
      specialWorkspaceIn = leaf_spec("specialWorkspaceIn", plan.enter[1], plan.enter[2]),
      specialWorkspaceOut = leaf_spec("specialWorkspaceOut", plan.leave[1], plan.leave[2]),
    }
    for leaf, spec in pairs(specs) do
      if anim and anim[leaf] then
        set_leaf(leaf, spec)
        longest = math.max(longest, (tonumber(spec.speed) or 3) * 100)
      end
    end
    if snapping then
      pcall(hl.animation, { leaf = "windowsMove", enabled = false })
      move_off = true
    end
    fn()
    restore_id = restore_id + 1
    local id = restore_id
    hl.timer(function()
      if id == restore_id then
        for leaf, spec in pairs(anim or {}) do
          set_leaf(leaf, spec)
        end
        restore_move()
      end
    end, { timeout = math.floor(math.min(longest, 5000)) + 200, type = "oneshot" })
  end

  local function motion_of(id, direction)
    local m = motions[id] or {}
    local side = m.direction or direction or "bottom"
    return { direction = side, outDirection = m.outDirection or side, effect = m.effect or "slide", outEffect = m.outEffect or m.effect or "slide" }
  end

  local function add_bind(keys, dispatcher, description)
    local ok, bind = pcall(hl.bind, keys, dispatcher, { description = description })
    if ok and bind then
      binds[#binds + 1] = bind
    end
  end

  -- Runs fn (a toggle that is not a plain special workspace toggle, e.g. the Fullscreen layer's) with this motion.
  function M.slide(direction, fn, extra)
    extra = extra or {}
    local function given(v) return v ~= nil and v ~= "" and v or nil end
    local enter_effect = given(extra.effect) or "slide"
    local leave = { given(extra.outEffect) or enter_effect, given(extra.outDirection) or direction or "bottom" }
    local open = open_pad()
    if open and motions[open] then
      local m = motion_of(open)
      leave = { m.outEffect, m.outDirection }
    end
    with_motion({ enter = { enter_effect, direction or "bottom" }, leave = leave }, fn, false)
  end


  -- ---- cards ------------------------------------------------------------------

  local function monitor_key(monitor)
    return monitor and (monitor.name or tostring(monitor.id)) or nil
  end

  local function announce(key)
    local st = stack[key]
    local parts = { "akt-cards", key, st and st.host or "" }
    if st then
      for _, guest in ipairs(st.guests) do parts[#parts + 1] = guest.id .. ":" .. table.concat(guest.addrs, ",") end
    end
    pcall(hl.dispatch, hl.dsp.event(table.concat(parts, "|")))
  end

  local function window_at(address)
    for _, window in ipairs(hl.get_windows()) do
      if window.address == address then return window end
    end
    return nil
  end

  local function move_silent(window, workspace)
    pcall(hl.dispatch, hl.dsp.window.move({ workspace = workspace, follow = false, window = window }))
  end

  -- Puts a card's windows back on its own pad (only those still on the workspace it borrowed).
  local function send_home(guest, host)
    for _, address in ipairs(guest.addrs) do
      local window = window_at(address)
      if window and window.workspace and window.workspace.name == "special:" .. host then
        move_silent(window, "special:" .. guest.id)
      end
    end
  end

  local function dissolve(key)
    local st = stack[key]
    if not st then return end
    stack[key] = nil
    for _, guest in ipairs(st.guests) do send_home(guest, st.host) end
    announce(key)
  end

  local function guest_index(st, id)
    for i, guest in ipairs(st.guests) do
      if guest.id == id then return i end
    end
    return nil
  end

  -- The pad shown on a monitor right now, or nil.
  local function shown_on(monitor)
    local ok, special = pcall(function()
      return monitor and (monitor.active_special_workspace or monitor.special_workspace or monitor.specialWorkspace)
    end)
    if ok and special and type(special.name) == "string" and special.name:sub(1, 8) == "special:" then return special.name:sub(9) end
    return nil
  end

  -- A stack whose host is no longer the pad shown on its monitor was ended from outside (another key, a workspace switch).
  local function check_stacks()
    for key, st in pairs(stack) do
      local found = nil
      for _, monitor in ipairs(hl.get_monitors and hl.get_monitors() or {}) do
        if monitor_key(monitor) == key then found = monitor end
      end
      if not found or shown_on(found) ~= st.host then dissolve(key) end
    end
  end

  -- A window that appears on (or is moved to) the home of a card joins the card on screen.
  local function adopt(window)
    if not window or not window.workspace then return end
    local name = window.workspace.name
    if type(name) ~= "string" or name:sub(1, 8) ~= "special:" then return end
    local id = name:sub(9)
    for key, st in pairs(stack) do
      local at = guest_index(st, id)
      if at then
        local addrs = st.guests[at].addrs
        addrs[#addrs + 1] = window.address
        move_silent(window, "special:" .. st.host)
        announce(key)
        return
      end
    end
  end

  local function card_toggle(id, direction)
    local mine = motion_of(id, direction)
    local monitor = hl.get_active_monitor()
    local key = monitor_key(monitor)
    local open = open_pad()
    -- a card that sits on another monitor goes home before this monitor uses the pad
    for other, st in pairs(stack) do
      local at = other ~= key and guest_index(st, id)
      if at then
        local gone = table.remove(st.guests, at)
        send_home(gone, st.host)
        if #st.guests == 0 then stack[other] = nil end
        announce(other)
      end
    end
    local st = key and stack[key] or nil
    if st and st.host ~= open then dissolve(key); st = nil end

    if not open then
      with_motion({ enter = { mine.effect, mine.direction }, leave = { mine.outEffect, mine.outDirection } }, function()
        hl.dispatch(hl.dsp.workspace.toggle_special(id))
      end, pad_elsewhere(id))
      return
    end

    if open ~= id then
      if not st then
        st = { host = open, guests = {} }
        stack[key] = st
      end
      local at = guest_index(st, id)
      if at then
        local gone = table.remove(st.guests, at)
        send_home(gone, open)
        if #st.guests == 0 then stack[key] = nil end
      else
        local guest = { id = id, addrs = {} }
        for _, window in ipairs(hl.get_windows()) do
          if window.workspace and window.workspace.name == "special:" .. id then
            guest.addrs[#guest.addrs + 1] = window.address
            move_silent(window, "special:" .. open)
            pcall(hl.dispatch, hl.dsp.window.bring_to_top({ window = window }))
          end
        end
        st.guests[#st.guests + 1] = guest
      end
      announce(key)
      return
    end

    -- the shown pad closes
    if not st or #st.guests == 0 then
      stack[key] = nil
      local leaver = motion_of(open)
      with_motion({ enter = { mine.effect, mine.direction }, leave = { leaver.outEffect, leaver.outDirection } }, function()
        hl.dispatch(hl.dsp.workspace.toggle_special(id))
      end, false)
      announce(key)
      return
    end
    -- other cards stay: the newest card becomes the shown pad and takes the rest of the stack along
    local top = table.remove(st.guests)
    send_home(top, open)
    for _, guest in ipairs(st.guests) do
      for _, address in ipairs(guest.addrs) do
        local window = window_at(address)
        if window and window.workspace and window.workspace.name == "special:" .. open then
          move_silent(window, "special:" .. top.id)
        end
      end
    end
    st.host = top.id
    if #st.guests == 0 then stack[key] = nil end
    with_motion({ enter = { "instant", "bottom" }, leave = { "instant", "bottom" } }, function()
      hl.dispatch(hl.dsp.workspace.toggle_special(top.id))
    end, false)
    announce(key)
  end

  function M.toggle(id, direction)
    if mode == "card" then return card_toggle(id, direction) end
    local mine = motion_of(id, direction)
    local open = open_pad()
    local leaver = mine
    if open and open ~= id and motions[open] then leaver = motion_of(open) end
    with_motion({ enter = { mine.effect, mine.direction }, leave = { leaver.outEffect, leaver.outDirection } }, function()
      hl.dispatch(hl.dsp.workspace.toggle_special(id))
    end, pad_elsewhere(id))
  end

  function M.start(cfg)
    M.stop()
    prefix = "AktOn1 " .. (cfg.label or "plugin") .. ": "
    anim = cfg.anim
    move = cfg.move
    effects = cfg.effects or {}
    motions = cfg.motions or {}
    mode = cfg.mode == "card" and "card" or "single"
    if mode ~= "card" then
      for key in pairs(stack) do dissolve(key) end
    else
      for _, event in ipairs({ "workspace.special_active", "workspace.active", "monitor.removed" }) do
        local ok, sub = pcall(hl.on, event, function() check_stacks() end)
        if ok and sub then subs[#subs + 1] = sub end
      end
      for _, event in ipairs({ "window.open", "window.move_to_workspace" }) do
        local ok, sub = pcall(hl.on, event, function(window) adopt(window) end)
        if ok and sub then subs[#subs + 1] = sub end
      end
      check_stacks()
      for key in pairs(stack) do announce(key) end
    end
    for effect, fx in pairs(effects) do
      local c = fx.curve
      if c and #c == 4 then
        pcall(hl.curve, "akt_" .. effect, { type = "bezier", points = { { c[1], c[2] }, { c[3], c[4] } } })
      end
    end
    for _, item in ipairs(cfg.layouts or {}) do
      local layout = item.layout or ""
      if layout ~= "" then
        pcall(hl.workspace_rule, { workspace = "special:" .. item.id, layout = layout })
        layouts[item.id] = layout
      elseif layouts[item.id] then
        pcall(hl.workspace_rule, { workspace = "special:" .. item.id, layout = "" })
        layouts[item.id] = nil
      end
    end
    for _, item in ipairs(cfg.commands or {}) do
      if item.key and item.key ~= "" and item.command and item.command ~= "" then
        add_bind(item.key, hl.dsp.exec_cmd(item.command), prefix .. (item.label or item.command))
      end
    end
    for _, pad in ipairs(cfg.pads or {}) do
      local id, direction = pad.id, pad.direction or "bottom"
      if pad.key and pad.key ~= "" then
        if pad.builtin then
          -- Take over Omarchy's own SUPER + S so the scratchpad can slide from another side.
          pcall(hl.unbind, pad.key)
          restores[#restores + 1] = function()
            pcall(hl.bind, pad.key, hl.dsp.workspace.toggle_special(id), { description = "Toggle scratchpad" })
          end
        end
        add_bind(pad.key, function() M.toggle(id, direction) end, prefix .. "toggle " .. (pad.label or id))
      end
      if pad.moveKey and pad.moveKey ~= "" and not pad.builtin then
        add_bind(pad.moveKey, hl.dsp.window.move({ workspace = "special:" .. id, follow = false }),
          prefix .. "move window to " .. (pad.label or id))
      end
    end
  end

  function M.launch(id, command)
    hl.exec_cmd(command, { workspace = "special:" .. id .. " silent" })
  end

  function M.close(address)
    for _, window in ipairs(hl.get_windows()) do
      if window.address == address then
        hl.dispatch(hl.dsp.window.close({ window = window }))
        return
      end
    end
  end

  function M.shutdown()
    M.stop()
    for key in pairs(stack) do dissolve(key) end
    for id in pairs(layouts) do
      pcall(hl.workspace_rule, { workspace = "special:" .. id, layout = "" })
      layouts[id] = nil
    end
  end

  function M.stop()
    restore_id = restore_id + 1
    restore_move()
    if anim then
      for leaf, spec in pairs(anim) do
        set_leaf(leaf, spec)
      end
    end
    anim = nil
    move = nil
    effects = {}
    motions = {}
    for _, bind in ipairs(binds) do
      pcall(function() bind:remove() end)
    end
    for _, sub in ipairs(subs) do
      pcall(function() sub:remove() end)
    end
    subs = {}
    for _, restore in ipairs(restores) do
      pcall(restore)
    end
    binds, restores = {}, {}
  end

  _G[global_name] = M
  return M
end
