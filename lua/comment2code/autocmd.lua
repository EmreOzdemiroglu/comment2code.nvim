local config = require("comment2code.config")
local state = require("comment2code.state")
local parser = require("comment2code.parser")
local opencode = require("comment2code.opencode")
local inserter = require("comment2code.inserter")

local M = {}

-- Augroup for the plugin
local augroup = nil

---Notify the user (respects config)
---@param msg string
---@param level number
local function notify(msg, level)
  if config.get().notify then
    vim.notify("[comment2code] " .. msg, level)
  end
end

---Process a single comment
---@param bufnr number
---@param parsed_comment table ParsedComment
---@param force boolean? Force re-generation
function M.process_comment(bufnr, parsed_comment, force)
  local hash = state.make_hash(bufnr, parsed_comment.line_num, parsed_comment.full_line)
  
  -- Check if already processed or processing (unless forced)
  if not force then
    if state.is_processing(hash) then
      return
    end
    if state.is_processed(hash) then
      return
    end
  else
    -- Clear previous state for force re-run
    state.clear_hash(hash)
  end
  
  -- Check if there's already code below (unless forced)
  if not force then
    local has_code = parser.has_code_below(bufnr, parsed_comment.line_num, 3)
    if has_code then
      -- Mark as processed to avoid checking again
      state.mark_completed(hash)
      return
    end
  end
  
  -- Mark as processing
  state.mark_processing(hash)
  notify("Generating code...", vim.log.levels.INFO)
  
  -- Build the full prompt with context
  local full_prompt = opencode.build_prompt(bufnr, parsed_comment.line_num, parsed_comment.prompt)
  
  -- Execute opencode asynchronously
  opencode.execute_async(full_prompt, hash, function(success, result)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      state.clear_hash(hash)
      return
    end
    
    if success then
      -- Get the current generated region if it exists (for replacement)
      local old_start, old_end = inserter.get_generated_region(bufnr, parsed_comment.line_num)
      
      local start_line, end_line
      if force and old_start and old_end then
        -- Replace existing code
        start_line, end_line = inserter.replace_code(
          bufnr,
          parsed_comment.line_num,
          result,
          parsed_comment.indent,
          old_start,
          old_end
        )
      else
        -- Insert new code
        start_line, end_line = inserter.insert_code(
          bufnr,
          parsed_comment.line_num,
          result,
          parsed_comment.indent
        )
      end
      
      state.mark_completed(hash, start_line, end_line)
      notify("Code generated successfully!", vim.log.levels.INFO)
    else
      state.mark_error(hash, result)
      notify("Error: " .. result, vim.log.levels.ERROR)
    end
  end)
end

---Check the current line for AI comments and process
---@param bufnr number
function M.check_current_line(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1] - 1 -- Convert to 0-indexed
  
  -- Check current line
  local parsed = parser.parse_line(bufnr, line_num)
  if parsed then
    M.process_comment(bufnr, parsed, false)
    return
  end
  
  -- Also check previous line (in case cursor moved after typing)
  if line_num > 0 then
    parsed = parser.parse_line(bufnr, line_num - 1)
    if parsed then
      M.process_comment(bufnr, parsed, false)
    end
  end
end

---Debounced check for auto-triggering
---@param bufnr number
function M.debounced_check(bufnr)
  local cfg = config.get()
  
  -- Cancel existing timer
  if state.debounce_timers[bufnr] then
    pcall(vim.loop.timer_stop, state.debounce_timers[bufnr])
    state.debounce_timers[bufnr] = nil
  end
  
  -- Create new timer
  local timer = vim.loop.new_timer()
  state.debounce_timers[bufnr] = timer
  
  timer:start(cfg.debounce_ms, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.check_current_line(bufnr)
    end
    
    -- Clean up timer
    if state.debounce_timers[bufnr] == timer then
      state.debounce_timers[bufnr] = nil
    end
    timer:stop()
    timer:close()
  end))
end

---Manual trigger for the current line
function M.trigger_current_line()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1] - 1
  
  local parsed = parser.parse_line(bufnr, line_num)
  if parsed then
    M.process_comment(bufnr, parsed, true) -- Force re-generation
  else
    notify("No @ai: comment found on current line", vim.log.levels.WARN)
  end
end

---Process all AI comments in the current buffer
function M.process_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local comments = parser.find_all_comments(bufnr)
  
  if #comments == 0 then
    notify("No @ai: comments found in buffer", vim.log.levels.INFO)
    return
  end
  
  notify(string.format("Processing %d comment(s)...", #comments), vim.log.levels.INFO)
  
  for _, parsed in ipairs(comments) do
    M.process_comment(bufnr, parsed, false)
  end
end

---Setup autocmds for automatic triggering
function M.setup()
  -- Create augroup
  augroup = vim.api.nvim_create_augroup("Comment2Code", { clear = true })
  
  -- Auto-trigger on text change (if enabled)
  if config.get().auto_trigger then
    -- Trigger with debounce when entering normal mode after editing
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          -- Start debounce timer when entering normal mode
          M.debounced_check(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-trigger after leaving insert mode",
    })
    
    -- Also trigger on normal mode text change (e.g., paste, undo)
    vim.api.nvim_create_autocmd("TextChanged", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.debounced_check(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-trigger on normal mode text change",
    })
  end
  
  -- Clean up state when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      state.clear_buffer(args.buf)
    end,
    desc = "Comment2Code: Cleanup on buffer delete",
  })
  
  -- Setup keymaps
  local keymaps = config.get().keymaps
  if keymaps.manual_trigger then
    vim.keymap.set("n", keymaps.manual_trigger, M.trigger_current_line, {
      desc = "Comment2Code: Generate code from AI comment",
      silent = true,
    })
  end
end

---Disable autocmds
function M.disable()
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end
end

---Toggle enabled state
function M.toggle()
  local cfg = config.get()
  cfg.enabled = not cfg.enabled
  notify(cfg.enabled and "Enabled" or "Disabled", vim.log.levels.INFO)
end

return M
