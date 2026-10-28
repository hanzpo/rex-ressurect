local M = {}

local HOME = os.getenv("HOME") or "~"
local TERMINAL = "com.superlogical.terminal.shell"

M.config = {
  dir = HOME .. "/.local/share/rex-resurrect",
  keep = 20,
  interval = 300,
  auto_restore = true,
  scrollback = true,
  scrollback_lines = 5000,
  prompt_lines = 1,
  shell = os.getenv("SHELL") or "/bin/zsh",
  shells = { zsh = true, bash = true, fish = true, sh = true, dash = true, ksh = true, tcsh = true, csh = true, nu = true, login = true },
  programs = {
    vi = true,
    vim = true,
    nvim = true,
    emacs = true,
    nano = true,
    htop = true,
    btop = true,
    top = true,
    lazygit = true,
    claude = "claude --continue",
    codex = "codex resume --last",
  },
  keys = {},
}

local function run(argv)
  local ok, res = pcall(rex.exec, argv)
  if ok and res and res.ok then return res.stdout or "" end
  return ""
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, data)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(data)
  f:close()
  assert(os.rename(tmp, path))
end

local function basename(p)
  return (p or ""):match("([^/]+)/*$") or p
end

local function snapshots_dir() return M.config.dir .. "/snapshots" end
local function last_path() return M.config.dir .. "/last" end

local function call(method, params)
  local res, err = rex.call(method, params)
  if err ~= nil then error(method .. ": " .. tostring(err), 0) end
  return res
end

local function try(method, params)
  local ok, res, err = pcall(rex.call, method, params)
  if ok and err == nil then return res end
  return nil
end

local function block_call(sid, bid, method, args)
  return try("block.method", { session_id = sid, block_id = bid, method = method, args = args })
end

local function program_name(fg)
  return basename(((fg and (fg.argv0 or fg.name)) or ""):gsub("^%-", ""))
end

local function is_shell(fg)
  local name = program_name(fg)
  return name == "" or M.config.shells[name] == true
end

local function program_of(fg)
  if is_shell(fg) then return nil end
  local name = program_name(fg)
  local rule = M.config.programs[name]
  if rule == true then return name end
  if type(rule) == "string" then return rule end
  if type(rule) == "function" then return rule(fg) end
  return nil
end

local function cwd_of(proc)
  if not proc then return nil end
  if proc.foreground and proc.foreground.cwd then return proc.foreground.cwd end
  for _, a in ipairs(proc.ancestors or {}) do
    if a.cwd then return a.cwd end
  end
  return nil
end

local function read_screen(sid, bid)
  local modes = block_call(sid, bid, "modes")
  if modes and modes.screen == "alternate" then return nil end
  local res = block_call(sid, bid, "format", { format = "text", trim = true, max_bytes = 983040 })
  if not res or not res.content then return nil end
  local parts = { res.content }
  local offset = #res.content
  local id = res.id
  while id do
    local chunk = block_call(sid, bid, "blob_read", { id = id, offset = offset, max_bytes = 983040 })
    if not chunk or not chunk.data or chunk.data == "" then break end
    parts[#parts + 1] = chunk.data
    offset = offset + #chunk.data
    if chunk.eof then break end
  end
  return table.concat(parts)
end

local function tidy_scrollback(text, at_prompt)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  if at_prompt then
    for _ = 1, M.config.prompt_lines do lines[#lines] = nil end
  end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  local first = math.max(1, #lines - M.config.scrollback_lines + 1)
  if #lines == 0 then return nil end
  return table.concat(lines, "\n", first) .. "\n"
end

local function capture_block(sid, info, ctx)
  if info.flavor ~= TERMINAL then return nil end
  local proc = block_call(sid, info.block_id, "process")
  local pane = { id = info.block_id, label = info.label, cwd = cwd_of(proc) }
  ctx.panes = ctx.panes + 1
  pane.program = program_of(proc and proc.foreground)
  if M.config.scrollback then
    local text = read_screen(sid, info.block_id)
    text = text and tidy_scrollback(text, is_shell(proc and proc.foreground))
    if text then
      ctx.n = ctx.n + 1
      local file = ctx.scroll_dir .. "/" .. ctx.n .. ".txt"
      local f = io.open(file, "wb")
      if f then
        f:write(text)
        f:close()
        pane.scrollback = file
      end
    end
  end
  return pane
end

local function capture_node(sid, node, blocks, ctx)
  if not node then return nil end
  if node.block_id then
    local info = blocks[node.block_id]
    local pane = info and capture_block(sid, info, ctx)
    return pane and { block = pane } or nil
  end
  if node.split then
    local s = node.split
    local before = capture_node(sid, s.before, blocks, ctx)
    local after = capture_node(sid, s.after, blocks, ctx)
    if before and after then
      return { split = { direction = s.direction, ratio = s.ratio, before = before, after = after } }
    end
    return before or after
  end
  return nil
end

function M.save()
  local stamp = os.date("%Y%m%dT%H%M%S")
  local scroll_dir = snapshots_dir() .. "/" .. stamp
  run{ "mkdir", "-p", scroll_dir }
  local ctx = { n = 0, panes = 0, scroll_dir = scroll_dir }
  local list = call("session.list")
  local snapshot = { version = 1, saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"), sessions = {} }
  for _, s in ipairs(list.sessions or {}) do
    try("session.attach", { session_id = s.session_id })
    local view = call("session.view", { session_id = s.session_id })
    local saved = { label = view.label, windows = {} }
    for _, w in ipairs(view.windows or {}) do
      local win = { label = w.label, layers = {} }
      if w.window_id == view.active_window_id then saved.active = #saved.windows + 1 end
      for _, layer in ipairs(w.layers or {}) do
        local blocks = {}
        for _, b in ipairs(layer.blocks or {}) do blocks[b.block_id] = b end
        local layout = capture_node(s.session_id, layer.layout, blocks, ctx)
        if layout then
          win.layers[#win.layers + 1] = { kind = layer.kind, bounds = layer.bounds, layout = layout }
        end
      end
      if #win.layers > 0 then
        win.focused = w.focused_block_id
        win.zoomed = w.zoomed_block_id
        saved.windows[#saved.windows + 1] = win
      end
    end
    if #saved.windows > 0 then snapshot.sessions[#snapshot.sessions + 1] = saved end
  end
  if ctx.panes == 0 then
    run{ "rm", "-rf", scroll_dir }
    return { saved = false, reason = "nothing to save" }
  end
  local path = snapshots_dir() .. "/" .. stamp .. ".json"
  write_file(path, rex.json.encode(snapshot))
  write_file(last_path(), path)
  M.prune()
  return { saved = true, path = path, sessions = #snapshot.sessions, panes = ctx.panes }
end

function M.prune()
  local files = {}
  for name in run{ "ls", "-1", snapshots_dir() }:gmatch("[^\n]+") do
    if name:match("%.json$") then files[#files + 1] = name end
  end
  table.sort(files)
  for i = 1, #files - M.config.keep do
    local stamp = files[i]:gsub("%.json$", "")
    os.remove(snapshots_dir() .. "/" .. files[i])
    run{ "rm", "-rf", snapshots_dir() .. "/" .. stamp }
  end
end

local function build_node(node, order)
  if node.block then
    local p = node.block
    local options = {}
    if p.cwd then options.cwd = p.cwd end
    if p.scrollback and read_file(p.scrollback) then
      options.shell = "none"
      options.command = { "/bin/sh", "-c", 'cat "$1"; exec "$2" -l', "sh", p.scrollback, M.config.shell }
    end
    if p.program then options.initial_input = p.program .. "\n" end
    order[#order + 1] = p.id
    local block = { flavor = TERMINAL, options = options }
    if p.label and p.label ~= "" then block.label = p.label end
    return { block = block }
  end
  local s = node.split
  local before = build_node(s.before, order)
  local after = build_node(s.after, order)
  return { split = { direction = s.direction, ratio = s.ratio, before = before, after = after } }
end

local function map_ids(map, old, new)
  for i, id in ipairs(old) do
    if new[i] then map[id] = new[i] end
  end
end

local function restore_session(saved)
  local map = {}
  local initial, plans = {}, {}
  for wi, w in ipairs(saved.windows) do
    local order = {}
    local layout = build_node(w.layers[1].layout, order)
    local label = w.label and not w.label:match("^Window %%x+$") and w.label or nil
    initial[wi] = { window_label = label, layout = layout }
    plans[wi] = order
  end
  local created = call("session.create", { label = saved.label, initial_windows = initial })
  local sid = created.session_id
  try("session.attach", { session_id = sid })
  for wi, w in ipairs(saved.windows) do
    local cw = created.initial_windows[wi]
    map_ids(map, plans[wi], cw.block_ids)
    for li = 2, #w.layers do
      local layer = w.layers[li]
      local order = {}
      local res = try("session.new_layer", {
        session_id = sid,
        window_id = cw.window_id,
        bounds = layer.bounds,
        layout = build_node(layer.layout, order),
      })
      if res then map_ids(map, order, res.block_ids) end
    end
  end
  for wi, w in ipairs(saved.windows) do
    if w.zoomed and map[w.zoomed] then
      try("session.zoom_block", { session_id = sid, block_id = map[w.zoomed], zoom = true })
    end
    if w.focused and map[w.focused] and wi ~= saved.active then
      try("session.focus_block", { session_id = sid, block_id = map[w.focused] })
    end
  end
  local active = saved.windows[saved.active or #saved.windows]
  if active then
    local cw = created.initial_windows[saved.active or #saved.windows]
    try("session.focus_window", { session_id = sid, window_id = cw.window_id })
    if active.focused and map[active.focused] then
      try("session.focus_block", { session_id = sid, block_id = map[active.focused] })
    end
  end
  return sid
end

function M.load(path)
  path = path or (read_file(last_path()) or ""):gsub("%s+$", "")
  if path == "" then return nil, "no snapshot saved yet" end
  local data = read_file(path)
  if not data then return nil, "can't read " .. path end
  return rex.json.decode(data), path
end

function M.restore(args)
  args = args or {}
  local snapshot, path = M.load(args.path)
  if not snapshot then return { restored = 0, reason = path } end
  local existing = {}
  for _, s in ipairs(call("session.list").sessions or {}) do
    if s.label then existing[s.label] = true end
  end
  local restored, skipped, failed = {}, {}, {}
  for _, saved in ipairs(snapshot.sessions or {}) do
    if saved.label and existing[saved.label] then
      skipped[#skipped + 1] = saved.label
    else
      local ok, err = pcall(restore_session, saved)
      if ok then
        restored[#restored + 1] = saved.label
      else
        failed[#failed + 1] = (saved.label or "?") .. ": " .. tostring(err)
      end
    end
  end
  return { snapshot = path, restored = restored, skipped = skipped, failed = failed }
end

M.config_file = os.getenv("REX_RESURRECT_CONFIG")
  or ((os.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")) .. "/rex/resurrect.lua")

local function merge(opts)
  for k, v in pairs(opts or {}) do
    if type(v) == "table" and type(M.config[k]) == "table" then
      for kk, vv in pairs(v) do M.config[k][kk] = vv end
    else
      M.config[k] = v
    end
  end
end

function M.configure(opts)
  if read_file(M.config_file) then merge(dofile(M.config_file)) end
  merge(opts)
  return M
end

function M.setup(opts)
  M.configure(opts)
  rex.action{ name = "resurrect_save", title = "Save sessions", run = function() return M.save() end }
  rex.action{ name = "resurrect_restore", title = "Restore sessions", run = function(_, args) return M.restore(args) end }
  if M.config.keys.save then rex.bind(M.config.keys.save, "resurrect_save") end
  if M.config.keys.restore then rex.bind(M.config.keys.restore, "resurrect_restore") end
  return M
end

return M
