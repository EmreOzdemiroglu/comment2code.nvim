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
---@param force boolean? Force re-generation (also enables refactoring mode)
---@param on_complete function? Optional callback when processing completes
function M.process_comment(bufnr, parsed_comment, force, on_complete)
  local hash = state.make_hash(bufnr, parsed_comment.line_num, parsed_comment.full_line)

  -- Check if already processed or processing (unless forced)
  if not force then
    if state.is_processing(hash) then
      if on_complete then on_complete() end
      return
    end
    if state.is_processed(hash) then
      if on_complete then on_complete() end
      return
    end
  else
    -- Clear previous state for force re-run
    state.clear_hash(hash)
  end

  -- Check for existing code below the comment
  local code_region = parser.get_code_region(bufnr, parsed_comment.line_num)
  local is_refactor_mode = force and code_region ~= nil

  -- For auto-trigger (not forced), skip if there's already code below
  if not force then
    if code_region then
      -- Mark as processed to avoid checking again
      state.mark_completed(hash)
      if on_complete then on_complete() end
      return
    end
  end

  -- Mark as processing
  state.mark_processing(hash)
  
  local full_prompt
  if is_refactor_mode then
    notify("Refactoring code...", vim.log.levels.INFO)
    full_prompt = opencode.build_refactor_prompt(
      bufnr,
      parsed_comment.line_num,
      parsed_comment.prompt,
      code_region.code
    )
  else
    notify("Generating code...", vim.log.levels.INFO)
    full_prompt = opencode.build_prompt(bufnr, parsed_comment.line_num, parsed_comment.prompt)
  end

  -- Execute opencode asynchronously
  opencode.execute_async(full_prompt, hash, function(success, result)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      state.clear_hash(hash)
      if on_complete then on_complete() end
      return
    end

    if success then
      local start_line, end_line
      
      if is_refactor_mode then
        -- Replace the existing code region with refactored code
        start_line, end_line = inserter.replace_code(
          bufnr,
          parsed_comment.line_num,
          result,
          parsed_comment.indent,
          code_region.start_line,
          code_region.end_line
        )
        notify("Code refactored successfully!", vim.log.levels.INFO)
      else
        -- Check if there's an existing generated region (for re-generation)
        local old_start, old_end = inserter.get_generated_region(bufnr, parsed_comment.line_num)

        if force and old_start and old_end then
          -- Replace existing generated code
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
        notify("Code generated successfully!", vim.log.levels.INFO)
      end

      state.mark_completed(hash, start_line, end_line)
    else
      state.mark_error(hash, result)
      notify("Error: " .. result, vim.log.levels.ERROR)
    end
    
    -- Call completion callback
    if on_complete then on_complete() end
  end)
end

---Process all queued comments for a buffer
---@param bufnr number
function M.process_queued_comments(bufnr)
  local pending_lines = state.get_and_clear_pending(bufnr)

  for _, line_num in ipairs(pending_lines) do
    local parsed = parser.parse_line(bufnr, line_num)
    if parsed then
      M.process_comment(bufnr, parsed, false)
    end
  end
end

---Process a single comment by line number with debounce
---@param bufnr number
---@param line_num number
function M.process_line_debounced(bufnr, line_num)
  local cfg = config.get()

  -- Queue this comment
  state.queue_comment(bufnr, line_num)

  -- Cancel existing timer
  if state.debounce_timers[bufnr] then
    pcall(vim.loop.timer_stop, state.debounce_timers[bufnr])
    state.debounce_timers[bufnr] = nil
  end

  -- Create new timer to process all queued comments
  local timer = vim.loop.new_timer()
  state.debounce_timers[bufnr] = timer

  timer:start(cfg.debounce_ms, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.process_queued_comments(bufnr)
    end

    -- Clean up timer
    if state.debounce_timers[bufnr] == timer then
      state.debounce_timers[bufnr] = nil
    end
    timer:stop()
    timer:close()
  end))
end

---Check for auto_linear mode trigger
---When user starts writing a NEW @ai: comment, trigger the previous one
---@param bufnr number
function M.check_linear_trigger(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1] - 1 -- 0-indexed

  -- Check if current line is an @ai: comment
  local current_parsed = parser.parse_line(bufnr, current_line)

  if current_parsed then
    -- Current line is an @ai: comment
    local prev_active = state.get_active_comment(bufnr)

    if prev_active ~= nil and prev_active ~= current_line then
      -- We have a different active comment - trigger it immediately (no debounce)
      local prev_parsed = parser.parse_line(bufnr, prev_active)
      if prev_parsed then
        M.process_comment(bufnr, prev_parsed, false)
      end
      -- Clear the previous active comment after triggering
      state.clear_active_comment(bufnr)
    end

    -- Set current as the new active comment
    state.set_active_comment(bufnr, current_line)
  end
end

---Check for auto_nonlinear mode trigger
---When user moves cursor away from an @ai: comment line, trigger it
---@param bufnr number
function M.check_nonlinear_trigger(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1] - 1 -- 0-indexed

  -- Get the previous line we were tracking
  local prev_line = state.get_last_cursor_line(bufnr)

  -- Check if we moved away from a comment line
  if prev_line ~= nil and prev_line ~= current_line then
    -- Check if the previous line was an @ai: comment
    local prev_parsed = parser.parse_line(bufnr, prev_line)
    if prev_parsed then
      -- Trigger the comment we moved away from
      M.process_line_debounced(bufnr, prev_line)
    end
  end

  -- Update tracking: only track if current line is an @ai: comment
  local current_parsed = parser.parse_line(bufnr, current_line)
  if current_parsed then
    state.set_last_cursor_line(bufnr, current_line)
  else
    -- Clear tracking if we're not on a comment line
    state.clear_last_cursor_line(bufnr)
  end
end

---Manual trigger for the current line
---Adds to sequential queue to prevent race conditions with line numbers
function M.trigger_current_line()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1] - 1

  local parsed = parser.parse_line(bufnr, line_num)
  if parsed then
    -- Queue the comment by its TEXT (not line number) for sequential processing
    state.add_to_manual_queue(bufnr, parsed.full_line, parsed.prompt)
    local queue_len = state.get_manual_queue_length()
    if queue_len > 1 then
      notify(string.format("Queued (%d pending)", queue_len), vim.log.levels.INFO)
    end
    
    -- Start processing the queue (if not already running)
    M.process_manual_queue()
  else
    notify("No @ai: comment found on current line", vim.log.levels.WARN)
  end
end

---Process the manual queue sequentially
---Re-finds comments by text before processing to handle line shifts
function M.process_manual_queue()
  -- Prevent concurrent processing
  if state.manual_queue_processing then
    return
  end
  
  local item = state.get_next_manual_queue_item()
  if not item then
    return  -- Queue empty
  end
  
  state.manual_queue_processing = true
  
  -- Check if buffer is still valid
  if not vim.api.nvim_buf_is_valid(item.bufnr) then
    notify("Buffer no longer valid, skipping", vim.log.levels.WARN)
    state.manual_queue_processing = false
    -- Try next item
    vim.schedule(function()
      M.process_manual_queue()
    end)
    return
  end
  
  -- RE-FIND the comment by its text (gets current line number!)
  local parsed = parser.find_comment_by_text(item.bufnr, item.comment_text)
  
  if not parsed then
    notify("Comment no longer found in buffer", vim.log.levels.WARN)
    state.manual_queue_processing = false
    -- Try next item
    vim.schedule(function()
      M.process_manual_queue()
    end)
    return
  end
  
  -- Process with a callback that continues the queue
  M.process_comment(item.bufnr, parsed, true, function()
    state.manual_queue_processing = false
    -- Process next item in queue
    vim.schedule(function()
      M.process_manual_queue()
    end)
  end)
end

---Process all AI comments in the current buffer sequentially
---Uses the same queue mechanism as manual triggers to prevent race conditions
function M.process_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local comments = parser.find_all_comments(bufnr)

  if #comments == 0 then
    notify("No @ai: comments found in buffer", vim.log.levels.INFO)
    return
  end

  -- Queue all comments (sorted from top to bottom by find_all_comments)
  for _, parsed in ipairs(comments) do
    state.add_to_manual_queue(bufnr, parsed.full_line, parsed.prompt)
  end

  notify(string.format("Queued %d comment(s) for processing...", #comments), vim.log.levels.INFO)

  -- Start processing the queue sequentially
  M.process_manual_queue()
end

---Setup autocmds for automatic triggering based on mode
function M.setup()
  -- Create augroup
  augroup = vim.api.nvim_create_augroup("Comment2Code", { clear = true })

  local cfg = config.get()
  local mode = cfg.mode

  -- Mode-specific autocmds
  if mode == "auto_linear" then
    -- Auto-linear: trigger previous comment when starting a new one
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.check_linear_trigger(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-linear trigger on InsertLeave",
    })

    vim.api.nvim_create_autocmd("TextChanged", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.check_linear_trigger(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-linear trigger on TextChanged",
    })

    -- TextChangedI: trigger while still in insert mode when typing a new @ai: comment
    vim.api.nvim_create_autocmd("TextChangedI", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.check_linear_trigger(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-linear trigger on TextChangedI",
    })

    -- Process the active comment when leaving the buffer
    vim.api.nvim_create_autocmd("BufLeave", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          local active_line = state.get_active_comment(args.buf)
          if active_line then
            local parsed = parser.parse_line(args.buf, active_line)
            if parsed then
              M.process_comment(args.buf, parsed, false)
            end
            state.clear_active_comment(args.buf)
          end
        end
      end,
      desc = "Comment2Code: Process active comment on BufLeave",
    })

  elseif mode == "auto_nonlinear" then
    -- Auto-nonlinear: trigger when cursor moves away from comment line
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.check_nonlinear_trigger(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-nonlinear trigger on CursorMoved",
    })

    vim.api.nvim_create_autocmd("CursorMovedI", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          M.check_nonlinear_trigger(args.buf)
        end
      end,
      desc = "Comment2Code: Auto-nonlinear trigger on CursorMovedI",
    })

    -- Also check on InsertLeave to catch the line we were on
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if config.get().enabled then
          -- Update tracking when leaving insert mode
          local cursor = vim.api.nvim_win_get_cursor(0)
          local current_line = cursor[1] - 1
          local parsed = parser.parse_line(args.buf, current_line)
          if parsed then
            state.set_last_cursor_line(args.buf, current_line)
          end
        end
      end,
      desc = "Comment2Code: Track comment line on InsertLeave",
    })
  end
  -- mode == "manual": no auto-trigger autocmds

  -- Clean up state when buffer is deleted (always active)
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      state.clear_buffer(args.buf)
    end,
    desc = "Comment2Code: Cleanup on buffer delete",
  })

  -- Setup keymaps (always active regardless of mode)
  local keymaps = cfg.keymaps
  if keymaps.manual_trigger then
    vim.keymap.set("n", keymaps.manual_trigger, M.trigger_current_line, {
      desc = "Comment2Code: Generate code from AI comment (current line)",
      silent = true,
    })
  end
  if keymaps.process_all then
    vim.keymap.set("n", keymaps.process_all, M.process_all, {
      desc = "Comment2Code: Process all AI comments in buffer",
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

---Set mode at runtime
---@param new_mode Comment2CodeMode
function M.set_mode(new_mode)
  local valid_modes = { manual = true, auto_linear = true, auto_nonlinear = true }
  if not valid_modes[new_mode] then
    notify("Invalid mode: " .. tostring(new_mode) .. ". Use: manual, auto_linear, auto_nonlinear", vim.log.levels.ERROR)
    return
  end

  local cfg = config.get()
  local old_mode = cfg.mode
  cfg.mode = new_mode

  -- Re-setup autocmds with new mode
  M.disable()
  M.setup()

  notify(string.format("Mode changed: %s -> %s", old_mode, new_mode), vim.log.levels.INFO)
end

---Get current mode
---@return Comment2CodeMode
function M.get_mode()
  return config.get().mode
end

return M
