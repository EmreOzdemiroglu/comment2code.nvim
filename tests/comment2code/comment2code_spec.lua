local comment2code = require("comment2code")
local parser = require("comment2code.parser")
local state = require("comment2code.state")
local config = require("comment2code.config")
local opencode = require("comment2code.opencode")

describe("comment2code", function()
  before_each(function()
    state.reset()
    config.setup()
  end)

  describe("setup", function()
    it("works with default config", function()
      comment2code.setup()
      assert.is_true(config.get().enabled)
      assert.equals("@ai:", config.get().trigger_pattern)
    end)

    it("works with custom config", function()
      comment2code.setup({
        trigger_pattern = "@generate:",
        debounce_ms = 1000,
      })
      assert.equals("@generate:", config.get().trigger_pattern)
      assert.equals(1000, config.get().debounce_ms)
    end)
  end)

  describe("parser", function()
    it("extracts prompt from // style comments", function()
      local prompt = parser.extract_prompt("// @ai: create a function", "javascript")
      assert.equals("create a function", prompt)
    end)

    it("extracts prompt from # style comments", function()
      local prompt = parser.extract_prompt("# @ai: create a function", "python")
      assert.equals("create a function", prompt)
    end)

    it("extracts prompt from -- style comments", function()
      local prompt = parser.extract_prompt("-- @ai: create a function", "lua")
      assert.equals("create a function", prompt)
    end)

    it("handles indented comments", function()
      local prompt = parser.extract_prompt("    // @ai: create a function", "javascript")
      assert.equals("create a function", prompt)
    end)

    it("returns nil for non-AI comments", function()
      local prompt = parser.extract_prompt("// just a regular comment", "javascript")
      assert.is_nil(prompt)
    end)
  end)

  describe("state", function()
    it("tracks processed comments", function()
      local hash = state.make_hash(1, 10, "// @ai: test")
      assert.is_false(state.is_processed(hash))

      state.mark_completed(hash, 11, 15)
      assert.is_true(state.is_processed(hash))
    end)

    it("tracks processing status", function()
      local hash = state.make_hash(1, 10, "// @ai: test")
      assert.is_false(state.is_processing(hash))

      state.mark_processing(hash)
      assert.is_true(state.is_processing(hash))
    end)

    it("clears hash for re-trigger", function()
      local hash = state.make_hash(1, 10, "// @ai: test")
      state.mark_completed(hash, 11, 15)
      assert.is_true(state.is_processed(hash))

      state.clear_hash(hash)
      assert.is_false(state.is_processed(hash))
    end)
  end)

  describe("status", function()
    it("returns correct status info", function()
      comment2code.setup()
      local status = comment2code.status()
      assert.is_true(status.enabled)
      assert.equals(0, status.processing_count)
    end)
  end)

  describe("clean_output", function()
    it("removes markdown code fences with language", function()
      local input = "```python\nprint('hello')\n```"
      local result = opencode.clean_output(input)
      assert.equals("print('hello')", result)
    end)

    it("removes markdown code fences without language", function()
      local input = "```\nprint('hello')\n```"
      local result = opencode.clean_output(input)
      assert.equals("print('hello')", result)
    end)

    it("handles output without code fences", function()
      local input = "print('hello')"
      local result = opencode.clean_output(input)
      assert.equals("print('hello')", result)
    end)

    it("handles multiline code", function()
      local input = "```python\ndef foo():\n    return 42\n```"
      local result = opencode.clean_output(input)
      assert.equals("def foo():\n    return 42", result)
    end)

    it("extracts only first code block when multiple exist", function()
      local input = "```python\nfirst_code()\n```\n\nSome explanation\n\n```python\nsecond_code()\n```"
      local result = opencode.clean_output(input)
      assert.equals("first_code()", result)
    end)

    it("trims whitespace", function()
      local input = "  \n```python\ncode()\n```\n  "
      local result = opencode.clean_output(input)
      assert.equals("code()", result)
    end)

    it("removes @ai: comment lines from output", function()
      local input = "# @ai: create a while loop\ncount = 0\nwhile count < 5:\n    count += 1"
      local result = opencode.clean_output(input)
      assert.equals("count = 0\nwhile count < 5:\n    count += 1", result)
    end)

    it("removes @ai: comment from code block", function()
      local input = "```python\n# @ai: example\nprint('hello')\n```"
      local result = opencode.clean_output(input)
      assert.equals("print('hello')", result)
    end)
  end)

  describe("get_code_region", function()
    local bufnr

    before_each(function()
      -- Create a scratch buffer for testing
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = "python"
    end)

    after_each(function()
      -- Clean up buffer
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("returns nil when no code below comment", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: create a function",
        "",
        "",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_nil(region)
    end)

    it("captures single line of code", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: refactor this",
        "print('hello')",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(1, region.start_line)
      assert.equals(1, region.end_line)
      assert.equals("print('hello')", region.code)
      assert.equals(1, region.line_count)
    end)

    it("captures multiple lines of code", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: optimize this function",
        "def foo():",
        "    x = 1",
        "    return x",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(1, region.start_line)
      assert.equals(3, region.end_line)
      assert.equals("def foo():\n    x = 1\n    return x", region.code)
      assert.equals(3, region.line_count)
    end)

    it("stops at next @ai: comment", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: refactor this",
        "def foo():",
        "    return 1",
        "# @ai: and this too",
        "def bar():",
        "    return 2",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(1, region.start_line)
      assert.equals(2, region.end_line)
      assert.equals("def foo():\n    return 1", region.code)
      assert.equals(2, region.line_count)
    end)

    it("includes empty lines within code block", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: refactor this",
        "def foo():",
        "    x = 1",
        "",
        "    return x",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(1, region.start_line)
      assert.equals(4, region.end_line)
      assert.equals("def foo():\n    x = 1\n\n    return x", region.code)
      assert.equals(4, region.line_count)
    end)

    it("skips leading empty lines", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: refactor",
        "",
        "",
        "code_here()",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(3, region.start_line)
      assert.equals(3, region.end_line)
      assert.equals("code_here()", region.code)
    end)

    it("works with comment in middle of file", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "import os",
        "",
        "# @ai: improve this",
        "def legacy():",
        "    pass",
        "# @ai: next section",
      })
      local region = parser.get_code_region(bufnr, 2)
      assert.is_not_nil(region)
      assert.equals(3, region.start_line)
      assert.equals(4, region.end_line)
      assert.equals("def legacy():\n    pass", region.code)
    end)

    it("captures code until EOF when no trailing @ai:", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: refactor",
        "line1()",
        "line2()",
        "line3()",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals(1, region.start_line)
      assert.equals(3, region.end_line)
      assert.equals("line1()\nline2()\nline3()", region.code)
    end)

    it("handles different comment styles", function()
      -- Test with JavaScript style
      vim.bo[bufnr].filetype = "javascript"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "// @ai: refactor",
        "const x = 1;",
        "// @ai: next comment",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals("const x = 1;", region.code)
    end)

    it("handles Lua comment style", function()
      vim.bo[bufnr].filetype = "lua"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "-- @ai: optimize",
        "local x = 1",
        "return x",
      })
      local region = parser.get_code_region(bufnr, 0)
      assert.is_not_nil(region)
      assert.equals("local x = 1\nreturn x", region.code)
    end)
  end)

  describe("find_comment_by_text", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = "python"
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("finds comment by exact text", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# some code",
        "# @ai: create a function",
        "# more code",
      })
      local parsed = parser.find_comment_by_text(bufnr, "# @ai: create a function")
      assert.is_not_nil(parsed)
      assert.equals(1, parsed.line_num)
      assert.equals("create a function", parsed.prompt)
    end)

    it("finds comment with leading/trailing whitespace", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "  # @ai: indented comment  ",
        "code()",
      })
      local parsed = parser.find_comment_by_text(bufnr, "  # @ai: indented comment  ")
      assert.is_not_nil(parsed)
      assert.equals(0, parsed.line_num)
    end)

    it("returns nil when comment not found", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: existing comment",
      })
      local parsed = parser.find_comment_by_text(bufnr, "# @ai: nonexistent comment")
      assert.is_nil(parsed)
    end)

    it("finds correct line after buffer modification", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# @ai: first comment",
        "# @ai: second comment",
      })
      -- Simulate insertion of code after first comment (shifts second comment down)
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, {
        "",
        "def generated():",
        "    pass",
      })
      -- Now second comment is at line 4, not line 1
      local parsed = parser.find_comment_by_text(bufnr, "# @ai: second comment")
      assert.is_not_nil(parsed)
      assert.equals(4, parsed.line_num)
    end)
  end)

  describe("manual_queue", function()
    before_each(function()
      state.reset()
    end)

    it("adds items to queue", function()
      state.add_to_manual_queue(1, "# @ai: test", "test")
      assert.equals(1, state.get_manual_queue_length())
    end)

    it("prevents duplicate items", function()
      state.add_to_manual_queue(1, "# @ai: test", "test")
      state.add_to_manual_queue(1, "# @ai: test", "test")
      assert.equals(1, state.get_manual_queue_length())
    end)

    it("allows different comments", function()
      state.add_to_manual_queue(1, "# @ai: first", "first")
      state.add_to_manual_queue(1, "# @ai: second", "second")
      assert.equals(2, state.get_manual_queue_length())
    end)

    it("gets items in FIFO order", function()
      state.add_to_manual_queue(1, "# @ai: first", "first")
      state.add_to_manual_queue(1, "# @ai: second", "second")
      
      local item1 = state.get_next_manual_queue_item()
      assert.equals("first", item1.prompt)
      
      local item2 = state.get_next_manual_queue_item()
      assert.equals("second", item2.prompt)
      
      assert.is_true(state.is_manual_queue_empty())
    end)

    it("resets queue on state reset", function()
      state.add_to_manual_queue(1, "# @ai: test", "test")
      state.reset()
      assert.is_true(state.is_manual_queue_empty())
      assert.is_false(state.manual_queue_processing)
    end)
  end)
end)
