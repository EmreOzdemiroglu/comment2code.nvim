local comment2code = require("comment2code")
local parser = require("comment2code.parser")
local state = require("comment2code.state")
local config = require("comment2code.config")

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
end)
