---@class Comment2CodeConfig
---@field enabled boolean Enable/disable the plugin
---@field opencode_path string Path to opencode CLI
---@field model string|nil Model to use (e.g., "anthropic/claude-sonnet-4-5", "openai/gpt-4o")
---@field trigger_pattern string Pattern to detect AI comments
---@field auto_trigger boolean Automatically process comments
---@field debounce_ms number Debounce time in milliseconds
---@field notify boolean Show notifications
---@field insert_below boolean Insert code below comment (vs replace)
---@field keymaps Comment2CodeKeymaps
---@field comment_patterns table<string, string> Filetype to comment pattern mapping

---@class Comment2CodeKeymaps
---@field manual_trigger string Keymap to manually trigger generation

---@type Comment2CodeConfig
local defaults = {
  enabled = true,
  opencode_path = "opencode",
  model = "opencode/big-pickle", -- default model
  trigger_pattern = "@ai:",
  auto_trigger = true,
  debounce_ms = 500,
  notify = true,
  insert_below = true,
  keymaps = {
    manual_trigger = "<leader>ai",
  },
  -- Comment patterns for different filetypes (Lua patterns)
  comment_patterns = {
    lua = "^%s*%-%-",
    python = "^%s*#",
    javascript = "^%s*//",
    typescript = "^%s*//",
    javascriptreact = "^%s*//",
    typescriptreact = "^%s*//",
    c = "^%s*//",
    cpp = "^%s*//",
    rust = "^%s*//",
    go = "^%s*//",
    java = "^%s*//",
    kotlin = "^%s*//",
    swift = "^%s*//",
    ruby = "^%s*#",
    php = "^%s*//",
    sh = "^%s*#",
    bash = "^%s*#",
    zsh = "^%s*#",
    fish = "^%s*#",
    vim = "^%s*\"",
    sql = "^%s*%-%-",
    haskell = "^%s*%-%-",
    elixir = "^%s*#",
    erlang = "^%s*%%",
    clojure = "^%s*;",
    lisp = "^%s*;",
    scheme = "^%s*;",
    r = "^%s*#",
    julia = "^%s*#",
    perl = "^%s*#",
    yaml = "^%s*#",
    toml = "^%s*#",
    dockerfile = "^%s*#",
    make = "^%s*#",
    cmake = "^%s*#",
    css = "^%s*/%*",
    scss = "^%s*//",
    less = "^%s*//",
    html = "^%s*<!%-%-",
    xml = "^%s*<!%-%-",
    markdown = "^%s*<!%-%-",
  },
}

local M = {}

---@type Comment2CodeConfig
M.values = vim.deepcopy(defaults)

---@param opts Comment2CodeConfig?
function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@return Comment2CodeConfig
function M.get()
  return M.values
end

---Get comment pattern for current filetype
---@param filetype string
---@return string
function M.get_comment_pattern(filetype)
  return M.values.comment_patterns[filetype] or "^%s*//?"
end

return M
