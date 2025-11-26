-- comment2code.nvim - Generate code from AI comments using opencode-cli
-- Main entry point

local config = require("comment2code.config")
local autocmd = require("comment2code.autocmd")
local inserter = require("comment2code.inserter")
local state = require("comment2code.state")
local opencode = require("comment2code.opencode")

---@class Comment2Code
local M = {}

-- Re-export config for external access
M.config = config.values

---Setup the plugin
---@param opts Comment2CodeConfig?
function M.setup(opts)
  -- Merge config
  config.setup(opts)
  M.config = config.values

  -- Setup highlight groups
  inserter.setup_highlights()

  -- Setup autocmds and keymaps
  autocmd.setup()
end

---Manually trigger code generation for current line
function M.trigger()
  autocmd.trigger_current_line()
end

---Process all @ai: comments in current buffer
function M.process_all()
  autocmd.process_all()
end

---Toggle the plugin on/off
function M.toggle()
  autocmd.toggle()
end

---Enable the plugin
function M.enable()
  config.values.enabled = true
  vim.notify("[comment2code] Enabled", vim.log.levels.INFO)
end

---Disable the plugin
function M.disable()
  config.values.enabled = false
  vim.notify("[comment2code] Disabled", vim.log.levels.INFO)
end

---Set the activation mode
---@param mode Comment2CodeMode "manual", "auto_linear", or "auto_nonlinear"
function M.set_mode(mode)
  autocmd.set_mode(mode)
end

---Get the current activation mode
---@return Comment2CodeMode
function M.get_mode()
  return autocmd.get_mode()
end

---Get current status
---@return table
function M.status()
  return {
    enabled = config.values.enabled,
    mode = config.values.mode,
    processing_count = state.get_processing_count(),
    processed_count = vim.tbl_count(state.processed),
  }
end

---Cancel all running jobs
function M.cancel_all()
  opencode.cancel_all()
  vim.notify("[comment2code] Cancelled all running jobs", vim.log.levels.INFO)
end

---Reset all state (useful for debugging)
function M.reset()
  opencode.cancel_all()
  state.reset()
  vim.notify("[comment2code] State reset", vim.log.levels.INFO)
end

return M
