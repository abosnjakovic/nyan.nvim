--- Animation timer management

local config = require("nyan.config")
local render = require("nyan.render")

local M = {}

-- State
local timer = nil
local is_running = false
local user_stopped = false  -- Track if user explicitly stopped animation

--- Timer callback - advances frame and triggers redraw
local function tick()
  render.next_frame()
  vim.schedule(function()
    vim.cmd("redrawstatus")
  end)
end

--- Internal function to start the timer
local function start_timer()
  if is_running then
    return
  end

  local cfg = config.get()
  local interval = math.floor(1000 / cfg.animation.fps)

  timer = vim.uv.new_timer()
  if timer then
    timer:start(interval, interval, vim.schedule_wrap(tick))
    is_running = true
  end
end

--- Internal function to stop the timer
local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  is_running = false
end

--- Start animation timer (user-initiated)
M.start = function()
  user_stopped = false
  local cfg = config.get()
  if not cfg.animation.enabled then
    return
  end
  start_timer()
end

--- Stop animation timer (user-initiated)
M.stop = function()
  user_stopped = true
  stop_timer()
end

--- Pause animation (system-initiated, e.g., FocusLost)
--- Does not set user_stopped flag
M.pause = function()
  stop_timer()
end

--- Resume animation (system-initiated, e.g., FocusGained)
--- Only resumes if user hasn't explicitly stopped
M.resume = function()
  if user_stopped then
    return
  end
  local cfg = config.get()
  if not cfg.animation.enabled then
    return
  end
  start_timer()
end

--- Toggle animation on/off (user-initiated)
M.toggle = function()
  if is_running then
    user_stopped = true
    stop_timer()
  else
    user_stopped = false
    local cfg = config.get()
    if cfg.animation.enabled then
      start_timer()
    end
  end
end

--- Check if animation is running
---@return boolean
M.is_running = function()
  return is_running
end

--- Cleanup - stop timer and release resources (for VimLeavePre)
M.cleanup = function()
  stop_timer()
end

return M
