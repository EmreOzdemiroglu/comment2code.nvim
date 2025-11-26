-- Plugin entry point for comment2code.nvim
if vim.g.loaded_comment2code then
  return
end
vim.g.loaded_comment2code = true

-- User commands
vim.api.nvim_create_user_command("Comment2Code", function()
  require("comment2code").trigger()
end, {
  desc = "Generate code from @ai: comment on current line",
})

vim.api.nvim_create_user_command("Comment2CodeAll", function()
  require("comment2code").process_all()
end, {
  desc = "Process all @ai: comments in current buffer",
})

vim.api.nvim_create_user_command("Comment2CodeToggle", function()
  require("comment2code").toggle()
end, {
  desc = "Toggle comment2code plugin on/off",
})

vim.api.nvim_create_user_command("Comment2CodeEnable", function()
  require("comment2code").enable()
end, {
  desc = "Enable comment2code plugin",
})

vim.api.nvim_create_user_command("Comment2CodeDisable", function()
  require("comment2code").disable()
end, {
  desc = "Disable comment2code plugin",
})

vim.api.nvim_create_user_command("Comment2CodeStatus", function()
  local status = require("comment2code").status()
  local msg = string.format(
    "comment2code: %s | Processing: %d | Processed: %d",
    status.enabled and "enabled" or "disabled",
    status.processing_count,
    status.processed_count
  )
  vim.notify(msg, vim.log.levels.INFO)
end, {
  desc = "Show comment2code status",
})

vim.api.nvim_create_user_command("Comment2CodeCancel", function()
  require("comment2code").cancel_all()
end, {
  desc = "Cancel all running code generation jobs",
})

vim.api.nvim_create_user_command("Comment2CodeReset", function()
  require("comment2code").reset()
end, {
  desc = "Reset comment2code state",
})
