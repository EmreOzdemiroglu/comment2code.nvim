local state = require("comment2code.state")
local config = require("comment2code.config")

local M = {}

---Apply indentation to generated code
---@param code string
---@param indent string
---@return string[]
function M.apply_indent(code, indent)
  local lines = vim.split(code, "\n", { plain = true })
  local result = {}
  
  for i, line in ipairs(lines) do
    if line == "" then
      -- Keep empty lines empty
      table.insert(result, "")
    else
      -- Apply indent to non-empty lines
      table.insert(result, indent .. line)
    end
  end
  
  return result
end

---Insert generated code below the comment
---@param bufnr number
---@param line_num number 0-indexed comment line
---@param code string Generated code
---@param indent string Indentation to apply
---@return number start_line, number end_line
function M.insert_code(bufnr, line_num, code, indent)
  -- Apply indentation
  local indented_lines = M.apply_indent(code, indent)
  
  -- Add a blank line before the code for readability
  table.insert(indented_lines, 1, "")
  
  -- Insert after the comment line
  local insert_line = line_num + 1
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, indented_lines)
  
  -- Calculate the range of inserted code
  local start_line = insert_line
  local end_line = insert_line + #indented_lines - 1
  
  -- Add extmark to track the generated code region
  M.mark_generated_region(bufnr, start_line, end_line)
  
  return start_line, end_line
end

---Replace existing code (for re-generation)
---@param bufnr number
---@param line_num number 0-indexed comment line
---@param code string New generated code
---@param indent string Indentation to apply
---@param old_start number Previous code start line
---@param old_end number Previous code end line
---@return number start_line, number end_line
function M.replace_code(bufnr, line_num, code, indent, old_start, old_end)
  -- Validate that old_start <= old_end (can happen if buffer was modified and extmarks are stale)
  if old_start > old_end then
    -- Fallback to insert mode if the region is invalid
    return M.insert_code(bufnr, line_num, code, indent)
  end
  
  -- Validate that the region is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if old_start >= line_count or old_end >= line_count then
    -- Region is out of bounds, fallback to insert
    return M.insert_code(bufnr, line_num, code, indent)
  end
  
  -- Remove old extmarks
  M.clear_region_marks(bufnr, old_start, old_end)
  
  -- Apply indentation
  local indented_lines = M.apply_indent(code, indent)
  
  -- Add a blank line before the code for readability
  table.insert(indented_lines, 1, "")
  
  -- Replace the old code region
  vim.api.nvim_buf_set_lines(bufnr, old_start, old_end + 1, false, indented_lines)
  
  -- Calculate new range
  local start_line = old_start
  local end_line = old_start + #indented_lines - 1
  
  -- Mark new region
  M.mark_generated_region(bufnr, start_line, end_line)
  
  return start_line, end_line
end

---Mark a region as generated code using extmarks
---@param bufnr number
---@param start_line number
---@param end_line number
function M.mark_generated_region(bufnr, start_line, end_line)
  -- Initialize extmarks table for buffer if needed
  if not state.extmarks[bufnr] then
    state.extmarks[bufnr] = {}
  end
  
  -- Create an extmark at the start of the region
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, start_line, 0, {
    end_row = end_line,
    end_col = 0,
    hl_group = "Comment2CodeGenerated",
    priority = 100,
  })
  
  -- Store the extmark
  state.extmarks[bufnr][start_line] = mark_id
end

---Clear extmarks in a region
---@param bufnr number
---@param start_line number
---@param end_line number
function M.clear_region_marks(bufnr, start_line, end_line)
  if not state.extmarks[bufnr] then
    return
  end
  
  for line = start_line, end_line do
    local mark_id = state.extmarks[bufnr][line]
    if mark_id then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id, mark_id)
      state.extmarks[bufnr][line] = nil
    end
  end
end

---Check if a line is within a generated region
---@param bufnr number
---@param line_num number
---@return boolean, number?, number? -- is_generated, region_start, region_end
function M.is_in_generated_region(bufnr, line_num)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    state.ns_id,
    { 0, 0 },
    { -1, -1 },
    { details = true }
  )
  
  for _, mark in ipairs(marks) do
    local start_row = mark[2]
    local details = mark[4]
    local end_row = details.end_row or start_row
    
    if line_num >= start_row and line_num <= end_row then
      return true, start_row, end_row
    end
  end
  
  return false, nil, nil
end

---Get the generated region associated with a comment
---@param bufnr number
---@param comment_line number 0-indexed
---@return number?, number? -- start_line, end_line
function M.get_generated_region(bufnr, comment_line)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    state.ns_id,
    { comment_line + 1, 0 },
    { comment_line + 50, 0 },
    { details = true, limit = 1 }
  )
  
  if #marks > 0 then
    local mark = marks[1]
    local start_row = mark[2]
    local details = mark[4]
    local end_row = details.end_row or start_row
    
    -- Validate the region is still valid (can become invalid if buffer was edited)
    if start_row <= end_row then
      return start_row, end_row
    end
  end
  
  return nil, nil
end

---Setup highlight groups
function M.setup_highlights()
  -- Define a subtle highlight for generated code regions
  vim.api.nvim_set_hl(0, "Comment2CodeGenerated", {
    bg = "#1a1a2e",
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "Comment2CodeProcessing", {
    fg = "#f0a500",
    italic = true,
    default = true,
  })
end

return M
