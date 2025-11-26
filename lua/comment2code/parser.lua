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

---@class CodeRegion
---@field start_line number 0-indexed start line (first line of code after comment)
---@field end_line number 0-indexed end line (last line of code before next @ai: or EOF)
---@field code string The code content
---@field line_count number Number of lines in the region

---Get the code region between an @ai: comment and the next @ai: comment or EOF
---This is used for refactoring existing code
---@param bufnr number
---@param comment_line number 0-indexed line of the @ai: comment
---@return CodeRegion? region, nil if no code found
function M.get_code_region(bufnr, comment_line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local filetype = vim.bo[bufnr].filetype
  
  -- Start looking from the line after the comment
  local region_start = nil
  local region_end = nil
  
  for i = comment_line + 1, line_count - 1 do
    local lines = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)
    if #lines == 0 then
      break
    end
    
    local line = lines[1]
    
    -- Check if this line is another @ai: comment - stop here
    local prompt = M.extract_prompt(line, filetype)
    if prompt then
      -- Found next @ai: comment, stop before it
      break
    end
    
    -- Check if line has non-whitespace content
    if line:match("%S") then
      if region_start == nil then
        region_start = i
      end
      region_end = i
    elseif region_start ~= nil then
      -- Empty line after code started - include it in the region
      region_end = i
    end
  end
  
  -- If no code found, return nil
  if region_start == nil then
    return nil
  end
  
  -- Get the code content
  local code_lines = vim.api.nvim_buf_get_lines(bufnr, region_start, region_end + 1, false)
  local code = table.concat(code_lines, "\n")
  
  return {
    start_line = region_start,
    end_line = region_end,
    code = code,
    line_count = region_end - region_start + 1,
  }
end

---Find an @ai: comment in the buffer by its text content
---Used to re-locate comments after buffer modifications (line shifts)
---@param bufnr number
---@param comment_text string The exact comment line text to find
---@return ParsedComment? parsed comment with current line number, nil if not found
function M.find_comment_by_text(bufnr, comment_text)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local trimmed_target = vim.trim(comment_text)
  
  for i = 0, line_count - 1 do
    local lines = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)
    if #lines > 0 and vim.trim(lines[1]) == trimmed_target then
      -- Found the line, parse it to get full info
      return M.parse_line(bufnr, i)
    end
  end
  
  return nil
end

return M
