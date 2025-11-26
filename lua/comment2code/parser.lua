local config = require("comment2code.config")

local M = {}

---@class ParsedComment
---@field line_num number 0-indexed line number
---@field prompt string The AI prompt extracted from comment
---@field indent string The indentation string
---@field full_line string The complete original line
---@field comment_prefix string The comment syntax used

---Check if a line is a comment for the given filetype
---@param line string
---@param filetype string
---@return boolean
function M.is_comment(line, filetype)
  local pattern = config.get_comment_pattern(filetype)
  return line:match(pattern) ~= nil
end

---Extract the AI trigger and prompt from a comment line
---@param line string
---@param filetype string
---@return string? prompt, string? comment_prefix
function M.extract_prompt(line, filetype)
  local trigger = config.get().trigger_pattern
  -- Escape special Lua pattern characters in trigger
  local escaped_trigger = trigger:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  
  -- Common comment prefixes to try
  local prefixes = {
    "//",      -- C-style
    "#",       -- Shell/Python/Ruby
    "%-%-",    -- Lua/SQL/Haskell (escaped for pattern)
    ";",       -- Lisp/Clojure
    "\"",      -- Vim
    "%%",      -- Erlang
    "/%*",     -- CSS block comment start
    "<!%-%-",  -- HTML/XML
  }
  
  for _, prefix in ipairs(prefixes) do
    -- Pattern: whitespace, comment prefix, whitespace, @ai:, capture rest
    local pattern = "^(%s*)" .. prefix .. "%s*" .. escaped_trigger .. "%s*(.+)$"
    local indent, prompt = line:match(pattern)
    if prompt then
      -- Unescape the prefix for storage
      local clean_prefix = prefix:gsub("%%", ""):gsub("%-%-", "--")
      return vim.trim(prompt), clean_prefix
    end
  end
  
  return nil, nil
end

---Parse a line and return structured comment info if it's an AI comment
---@param bufnr number
---@param line_num number 0-indexed
---@return ParsedComment?
function M.parse_line(bufnr, line_num)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)
  if #lines == 0 then
    return nil
  end
  
  local line = lines[1]
  local filetype = vim.bo[bufnr].filetype
  
  local prompt, comment_prefix = M.extract_prompt(line, filetype)
  if not prompt then
    return nil
  end
  
  -- Extract indentation
  local indent = line:match("^(%s*)") or ""
  
  return {
    line_num = line_num,
    prompt = prompt,
    indent = indent,
    full_line = line,
    comment_prefix = comment_prefix,
  }
end

---Find all AI comments in a buffer
---@param bufnr number
---@return ParsedComment[]
function M.find_all_comments(bufnr)
  local comments = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  for i = 0, line_count - 1 do
    local parsed = M.parse_line(bufnr, i)
    if parsed then
      table.insert(comments, parsed)
    end
  end
  
  return comments
end

---Check if there's existing non-empty code after a line
---@param bufnr number
---@param start_line number 0-indexed line to check after
---@param max_lines number? Max lines to check (default 5)
---@return boolean has_code, number? first_code_line
function M.has_code_below(bufnr, start_line, max_lines)
  max_lines = max_lines or 5
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local end_line = math.min(start_line + max_lines + 1, line_count)
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line + 1, end_line, false)
  local filetype = vim.bo[bufnr].filetype
  
  for i, line in ipairs(lines) do
    -- Check if line has non-whitespace content
    if line:match("%S") then
      -- Make sure it's not another AI comment
      local prompt = M.extract_prompt(line, filetype)
      if not prompt then
        return true, start_line + i
      end
    end
  end
  
  return false, nil
end

---Get the comment prefix for the current filetype
---@param filetype string
---@return string
function M.get_comment_prefix(filetype)
  local prefixes = {
    lua = "--",
    python = "#",
    javascript = "//",
    typescript = "//",
    javascriptreact = "//",
    typescriptreact = "//",
    c = "//",
    cpp = "//",
    rust = "//",
    go = "//",
    java = "//",
    kotlin = "//",
    swift = "//",
    ruby = "#",
    php = "//",
    sh = "#",
    bash = "#",
    zsh = "#",
    vim = '"',
    sql = "--",
    haskell = "--",
    elixir = "#",
    r = "#",
    julia = "#",
    perl = "#",
    yaml = "#",
    toml = "#",
  }
  
  return prefixes[filetype] or "//"
end

return M
