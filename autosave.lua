
local resurrect = require("resurrect").configure()

local function log(...)
  io.stderr:write(os.date("%Y-%m-%d %H:%M:%S "), table.concat({ ... }, " "), "\n")
end

local function state_path() return resurrect.config.dir .. "/restored_instance" end

local function maybe_restore()
  if not resurrect.config.auto_restore then return end
  local instance = rex.call("server.status").instance_id
  local h = io.open(state_path(), "r")
  local last = h and h:read("*l")
  if h then h:close() end
  if last == instance then return end
  local res = resurrect.restore()
  log("restore", rex.json.encode(res))
  rex.exec{ "mkdir", "-p", resurrect.config.dir }
  local w = io.open(state_path(), "w")
  if w then
    w:write(instance, "\n")
    w:close()
  end
end

local function save()
  local ok, res = pcall(resurrect.save)
  log("save", ok and rex.json.encode(res) or tostring(res))
end

maybe_restore()
save()
rex.every(resurrect.config.interval, save)
