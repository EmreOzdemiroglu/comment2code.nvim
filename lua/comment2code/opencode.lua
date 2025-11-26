local config = require("comment2code.config")
local state = require("comment2code.state")

local M = {}

---Build the context prompt with file information
---@param bufnr number
---@param line_num number
---@param prompt string
---@return string
function M.build_prompt(bufnr, line_num, prompt)
  local filetype = vim.bo[bufnr].filetype
  local filename = vim.api.nvim_buf_get_name(bufnr)
  
  -- Get surrounding context (10 lines before, 5 after)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local context_start = math.max(0, line_num - 10)
  local context_end = math.min(line_count, line_num + 5)
  local context_lines = vim.api.nvim_buf_get_lines(bufnr, context_start, context_end, false)
  local context = table.concat(context_lines, "\n")
  
  local full_prompt = string.format(
    [[You are a code generator. Generate ONLY code, no explanations or markdown.

File: %s
Language: %s
Context around line %d:
```
%s
```

Task: %s

Requirements:
- Output ONLY the code, no markdown code blocks, no explanations
- Match the indentation style of the surrounding code
- Keep it concise and functional
- Do not include the original comment in your output]],
    filename ~= "" and filename or "untitled",
    filetype ~= "" and filetype or "text",
    line_num + 1,
    context,
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
  
  -- Remove markdown code blocks if present
  result = result:gsub("^```[%w]*\n", "")
  result = result:gsub("\n```%s*$", "")
  result = result:gsub("^```[%w]*", "")
  result = result:gsub("```%s*$", "")
  
  -- Trim leading/trailing whitespace but preserve internal structure
  result = result:gsub("^%s+", "")
  result = result:gsub("%s+$", "")
  
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
