local config = require("comment2code.config")
local state = require("comment2code.state")

local M = {}

---Build the context prompt for code generation
---@param bufnr number
---@param line_num number
---@param prompt string
---@return string
function M.build_prompt(bufnr, line_num, prompt)
  local filetype = vim.bo[bufnr].filetype
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Get more surrounding context (20 lines before, 10 after) for better understanding
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local context_start = math.max(0, line_num - 20)
  local context_end = math.min(line_count, line_num + 10)
  local context_lines = vim.api.nvim_buf_get_lines(bufnr, context_start, context_end, false)
  local context = table.concat(context_lines, "\n")

  local full_prompt = string.format(
    [[You are a precise code generator. Output ONLY executable code, nothing else.

FILE: %s (%s)
LINE: %d

CONTEXT:
%s

TASK: %s

RULES:
1. Output ONLY the code - no comments, no explanations, no markdown fences
2. Do NOT repeat or include the @ai: comment line in your output
3. Do NOT include any comment that describes what the code does
4. Start directly with the implementation code
5. Match the coding style from the context
6. Keep it minimal and focused]],
    filename ~= "" and filename or "untitled",
    filetype ~= "" and filetype or "text",
    line_num + 1,
    context,
    prompt
  )

  return full_prompt
end

---Build the prompt for refactoring existing code
---@param bufnr number
---@param line_num number
---@param prompt string
---@param existing_code string
---@return string
function M.build_refactor_prompt(bufnr, line_num, prompt, existing_code)
  local filetype = vim.bo[bufnr].filetype
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Get surrounding context for better understanding
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local context_start = math.max(0, line_num - 20)
  local context_end = math.min(line_count, line_num + 30)
  local context_lines = vim.api.nvim_buf_get_lines(bufnr, context_start, context_end, false)
  local context = table.concat(context_lines, "\n")

  local full_prompt = string.format(
    [[You are a precise code refactoring assistant. Output ONLY the refactored code, nothing else.

FILE: %s (%s)
LINE: %d

SURROUNDING CONTEXT:
%s

CODE TO REFACTOR:
%s

INSTRUCTION: %s

RULES:
1. Output ONLY the refactored code - no comments, no explanations, no markdown fences
2. Do NOT include the @ai: comment line in your output
3. Do NOT add any comments explaining the changes
4. Preserve the original functionality unless the instruction says otherwise
5. Match the existing coding style
6. Output the complete refactored code that will replace the original]],
    filename ~= "" and filename or "untitled",
    filetype ~= "" and filetype or "text",
    line_num + 1,
    context,
    existing_code,
    prompt
  )

  return full_prompt
end

---Execute opencode CLI asynchronously
---@param prompt string
---@param hash string
---@param callback fun(success: boolean, result: string)
function M.execute_async(prompt, hash, callback)
  local cfg = config.get()
  local opencode_path = cfg.opencode_path
  
  -- Check if opencode exists
  if vim.fn.executable(opencode_path) ~= 1 then
    -- Try common paths
    local common_paths = {
      vim.fn.expand("~/.opencode/bin/opencode"),
      "/usr/local/bin/opencode",
      "/opt/homebrew/bin/opencode",
    }
    
    local found = false
    for _, path in ipairs(common_paths) do
      if vim.fn.executable(path) == 1 then
        opencode_path = path
        found = true
        break
      end
    end
    
    if not found then
      callback(false, "opencode CLI not found. Install it or set opencode_path in config.")
      return
    end
  end
  
  -- Build command - use "run" subcommand to execute prompt and exit
  -- Format: opencode [--model provider/model] run "prompt"
  local cmd = { opencode_path }
  
  -- Add model flag if specified
  if cfg.model and cfg.model ~= "" then
    table.insert(cmd, "--model")
    table.insert(cmd, cfg.model)
  end
  
  -- Add run subcommand and prompt
  table.insert(cmd, "run")
  table.insert(cmd, prompt)
  
  local stdout_chunks = {}
  local stderr_chunks = {}
  
  -- Use vim.system for async execution (Neovim 0.10+)
  local job = vim.system(cmd, {
    stdout = function(err, data)
      if data then
        table.insert(stdout_chunks, data)
      end
    end,
    stderr = function(err, data)
      if data then
        table.insert(stderr_chunks, data)
      end
    end,
  }, function(result)
    -- This callback runs when the process exits
    vim.schedule(function()
      state.remove_job(hash)
      
      local stdout = table.concat(stdout_chunks, "")
      local stderr = table.concat(stderr_chunks, "")
      
      if result.code == 0 and stdout ~= "" then
        -- Clean up the output
        local cleaned = M.clean_output(stdout)
        callback(true, cleaned)
      else
        local error_msg = stderr ~= "" and stderr or ("Exit code: " .. result.code)
        callback(false, error_msg)
      end
    end)
  end)
  
  -- Store the job handle for potential cancellation
  state.store_job(hash, job)
end

---Clean up the output from opencode
---@param output string
---@return string
function M.clean_output(output)
  local result = output
  
  -- Trim leading/trailing whitespace first
  result = result:gsub("^%s+", "")
  result = result:gsub("%s+$", "")
  
  -- Check if the entire output is wrapped in a code block
  -- Pattern: ```language\n...\n``` (greedy match to get the first complete block)
  local code_block_pattern = "^```[%w%-_]*\n(.-)```"
  local extracted = result:match(code_block_pattern)
  
  if extracted then
    -- Use only the first code block content
    result = extracted
  else
    -- Try pattern without initial newline: ```language ...```
    extracted = result:match("^```[%w%-_]*%s*(.-)```")
    if extracted then
      result = extracted
    end
  end
  
  -- If there are still code fences in the middle (multiple blocks), take content before them
  -- This handles cases where model returns code + explanation + more code
  local first_fence = result:find("\n```")
  if first_fence then
    result = result:sub(1, first_fence - 1)
  end
  
  -- Remove any remaining ``` markers that might be at the start/end
  result = result:gsub("^```[%w%-_]*%s*", "")
  result = result:gsub("%s*```%s*$", "")
  
  -- Remove any @ai: comment lines that the model might have included
  -- Handle various comment styles: //, #, --, ;, ", etc.
  local lines = vim.split(result, "\n", { plain = true })
  local filtered_lines = {}
  for _, line in ipairs(lines) do
    -- Skip lines that contain @ai: pattern (the trigger comment)
    if not line:match("@ai:") then
      table.insert(filtered_lines, line)
    end
  end
  result = table.concat(filtered_lines, "\n")
  
  -- Final trim
  result = result:gsub("^%s*\n", "")
  result = result:gsub("\n%s*$", "")
  
  return result
end

---Cancel a running job
---@param hash string
function M.cancel_job(hash)
  local job = state.jobs[hash]
  if job then
    pcall(function()
      job:kill(9) -- SIGKILL
    end)
    state.remove_job(hash)
    state.clear_hash(hash)
  end
end

---Cancel all running jobs
function M.cancel_all()
  for hash, job in pairs(state.jobs) do
    pcall(function()
      job:kill(9)
    end)
  end
  state.jobs = {}
end

return M
