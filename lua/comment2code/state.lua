---@class ProcessedEntry
---@field status "pending"|"processing"|"completed"|"error"
---@field timestamp number
---@field code_start_line number?
---@field code_end_line number?
---@field error_msg string?

---@class ManualQueueEntry
---@field bufnr number
---@field comment_text string The full comment line text (used to re-find it)
---@field prompt string The extracted prompt

---@class Comment2CodeState
---@field processed table<string, ProcessedEntry> Hash -> ProcessedEntry
---@field processing table<string, boolean> Currently processing hashes
---@field jobs table<string, any> Active job handles
---@field debounce_timers table<number, any> Buffer -> timer handle
---@field extmarks table<number, table<number, number>> Buffer -> line -> extmark_id
---@field pending_queue table<number, table<number, number>> Buffer -> line_num -> timestamp
---@field active_comment table<number, number> Buffer -> line_num (for auto_linear mode)
---@field last_cursor_line table<number, number> Buffer -> line_num (for auto_nonlinear mode)
---@field manual_queue ManualQueueEntry[] Sequential queue for manual triggers
---@field manual_queue_processing boolean Whether we're currently processing the manual queue

local M = {}

-- Namespace for extmarks
M.ns_id = vim.api.nvim_create_namespace("comment2code")

-- State tables
M.processed = {}
M.processing = {}
M.jobs = {}
M.debounce_timers = {}
M.extmarks = {}
M.pending_queue = {} -- Queue of pending comments to process: bufnr -> {line_num -> timestamp}
M.active_comment = {} -- For auto_linear mode: tracks the comment currently being written
M.last_cursor_line = {} -- For auto_nonlinear mode: tracks last line cursor was on
M.manual_queue = {} -- Sequential queue for manual triggers (stores comment text, not line numbers)
M.manual_queue_processing = false -- Lock to prevent concurrent processing

---Generate a unique hash for a comment
---@param bufnr number
---@param line_num number
---@param text string
---@return string
function M.make_hash(bufnr, line_num, text)
  local trimmed = vim.trim(text)
  return string.format("%d:%d:%s", bufnr, line_num, trimmed)
end

---Check if a comment has been processed
---@param hash string
---@return boolean
function M.is_processed(hash)
  local entry = M.processed[hash]
  return entry ~= nil and entry.status == "completed"
end

---Check if a comment is currently being processed
---@param hash string
---@return boolean
function M.is_processing(hash)
  return M.processing[hash] == true
end

---Mark a comment as processing
---@param hash string
function M.mark_processing(hash)
  M.processing[hash] = true
  M.processed[hash] = {
    status = "processing",
    timestamp = vim.loop.now(),
  }
end

---Mark a comment as completed
---@param hash string
---@param code_start number?
---@param code_end number?
function M.mark_completed(hash, code_start, code_end)
  M.processing[hash] = nil
  M.processed[hash] = {
    status = "completed",
    timestamp = vim.loop.now(),
    code_start_line = code_start,
    code_end_line = code_end,
  }
end

---Mark a comment as errored
---@param hash string
---@param error_msg string
function M.mark_error(hash, error_msg)
  M.processing[hash] = nil
  M.processed[hash] = {
    status = "error",
    timestamp = vim.loop.now(),
    error_msg = error_msg,
  }
end

---Remove a hash from processed (for re-triggering)
---@param hash string
function M.clear_hash(hash)
  M.processed[hash] = nil
  M.processing[hash] = nil
end

---Clear all state for a buffer
---@param bufnr number
function M.clear_buffer(bufnr)
  local prefix = tostring(bufnr) .. ":"

  -- Clear processed entries for this buffer
  for hash, _ in pairs(M.processed) do
    if hash:sub(1, #prefix) == prefix then
      M.processed[hash] = nil
    end
  end

  -- Clear processing entries
  for hash, _ in pairs(M.processing) do
    if hash:sub(1, #prefix) == prefix then
      M.processing[hash] = nil
    end
  end

  -- Cancel any active jobs for this buffer
  for hash, job in pairs(M.jobs) do
    if hash:sub(1, #prefix) == prefix then
      if job and type(job.kill) == "function" then
        pcall(job.kill, job)
      end
      M.jobs[hash] = nil
    end
  end

  -- Clear debounce timer
  if M.debounce_timers[bufnr] then
    pcall(vim.loop.timer_stop, M.debounce_timers[bufnr])
    M.debounce_timers[bufnr] = nil
  end

  -- Clear extmarks
  M.extmarks[bufnr] = nil

  -- Clear pending queue
  M.pending_queue[bufnr] = nil

  -- Clear mode-specific tracking
  M.active_comment[bufnr] = nil
  M.last_cursor_line[bufnr] = nil
  
  -- Clear manual queue entries for this buffer
  local new_queue = {}
  for _, entry in ipairs(M.manual_queue) do
    if entry.bufnr ~= bufnr then
      table.insert(new_queue, entry)
    end
  end
  M.manual_queue = new_queue
end

---Store a job handle
---@param hash string
---@param job any
function M.store_job(hash, job)
  M.jobs[hash] = job
end

---Remove a job handle
---@param hash string
function M.remove_job(hash)
  M.jobs[hash] = nil
end

---Get processing count
---@return number
function M.get_processing_count()
  local count = 0
  for _ in pairs(M.processing) do
    count = count + 1
  end
  return count
end

---Add a comment to the pending queue
---@param bufnr number
---@param line_num number
function M.queue_comment(bufnr, line_num)
  if not M.pending_queue[bufnr] then
    M.pending_queue[bufnr] = {}
  end
  M.pending_queue[bufnr][line_num] = vim.loop.now()
end

---Get and clear all pending comments for a buffer
---@param bufnr number
---@return number[] -- list of line numbers
function M.get_and_clear_pending(bufnr)
  local pending = M.pending_queue[bufnr]
  if not pending then
    return {}
  end

  -- Collect line numbers
  local lines = {}
  for line_num, _ in pairs(pending) do
    table.insert(lines, line_num)
  end

  -- Sort by line number to process in order
  table.sort(lines)

  -- Clear the queue for this buffer
  M.pending_queue[bufnr] = {}

  return lines
end

---Reset all state (for testing/debugging)
function M.reset()
  M.processed = {}
  M.processing = {}
  M.jobs = {}
  M.debounce_timers = {}
  M.extmarks = {}
  M.pending_queue = {}
  M.active_comment = {}
  M.last_cursor_line = {}
  M.manual_queue = {}
  M.manual_queue_processing = false
end

-- Auto-linear mode helpers

---Set the active comment being written (auto_linear mode)
---@param bufnr number
---@param line_num number
function M.set_active_comment(bufnr, line_num)
  M.active_comment[bufnr] = line_num
end

---Get the active comment being written (auto_linear mode)
---@param bufnr number
---@return number|nil
function M.get_active_comment(bufnr)
  return M.active_comment[bufnr]
end

---Clear the active comment (auto_linear mode)
---@param bufnr number
function M.clear_active_comment(bufnr)
  M.active_comment[bufnr] = nil
end

-- Auto-nonlinear mode helpers

---Set the last cursor line (auto_nonlinear mode)
---@param bufnr number
---@param line_num number
function M.set_last_cursor_line(bufnr, line_num)
  M.last_cursor_line[bufnr] = line_num
end

---Get the last cursor line (auto_nonlinear mode)
---@param bufnr number
---@return number|nil
function M.get_last_cursor_line(bufnr)
  return M.last_cursor_line[bufnr]
end

---Clear the last cursor line (auto_nonlinear mode)
---@param bufnr number
function M.clear_last_cursor_line(bufnr)
  M.last_cursor_line[bufnr] = nil
end

-- Manual queue helpers (for sequential processing of manual triggers)

---Add a comment to the manual queue (for sequential processing)
---@param bufnr number
---@param comment_text string The full line text
---@param prompt string The extracted prompt
function M.add_to_manual_queue(bufnr, comment_text, prompt)
  -- Check if this exact comment is already in the queue
  for _, entry in ipairs(M.manual_queue) do
    if entry.bufnr == bufnr and entry.comment_text == comment_text then
      return -- Already queued
    end
  end
  
  table.insert(M.manual_queue, {
    bufnr = bufnr,
    comment_text = comment_text,
    prompt = prompt,
  })
end

---Get the next item from the manual queue
---@return ManualQueueEntry|nil
function M.get_next_manual_queue_item()
  if #M.manual_queue == 0 then
    return nil
  end
  return table.remove(M.manual_queue, 1)
end

---Check if manual queue is empty
---@return boolean
function M.is_manual_queue_empty()
  return #M.manual_queue == 0
end

---Get manual queue length
---@return number
function M.get_manual_queue_length()
  return #M.manual_queue
end

return M
