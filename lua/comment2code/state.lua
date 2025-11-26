---@class ProcessedEntry
---@field status "pending"|"processing"|"completed"|"error"
---@field timestamp number
---@field code_start_line number?
---@field code_end_line number?
---@field error_msg string?

---@class Comment2CodeState
---@field processed table<string, ProcessedEntry> Hash -> ProcessedEntry
---@field processing table<string, boolean> Currently processing hashes
---@field jobs table<string, any> Active job handles
---@field debounce_timers table<number, any> Buffer -> timer handle
---@field extmarks table<number, table<number, number>> Buffer -> line -> extmark_id

local M = {}

-- Namespace for extmarks
M.ns_id = vim.api.nvim_create_namespace("comment2code")

-- State tables
M.processed = {}
M.processing = {}
M.jobs = {}
M.debounce_timers = {}
M.extmarks = {}

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

---Reset all state (for testing/debugging)
function M.reset()
  M.processed = {}
  M.processing = {}
  M.jobs = {}
  M.debounce_timers = {}
  M.extmarks = {}
end

return M
