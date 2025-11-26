# comment2code.nvim

Generate code from AI comments using [opencode-cli](https://opencode.ai/).

Write a comment like `// @ai: create a function to calculate fibonacci` and watch as the code appears below it automatically!

## Features

- **Automatic Code Generation**: Write `@ai:` comments and code generates automatically
- **Multi-Language Support**: Works with 30+ languages (Lua, Python, JavaScript, TypeScript, Rust, Go, etc.)
- **Smart Deduplication**: Won't regenerate code that already exists
- **Parallel Processing**: Handle multiple AI comments simultaneously
- **Manual Re-trigger**: Force regeneration with a keymap
- **Non-blocking**: Async execution keeps your editor responsive

## Requirements

- Neovim 0.10+ (for `vim.system`)
- [opencode-cli](https://opencode.ai/) installed and configured

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

## Usage

### Basic Usage

Write a comment with `@ai:` followed by your prompt:

```lua
-- @ai: create a function that calculates the nth fibonacci number
```

```javascript
// @ai: create a debounce function with configurable delay
```

```python
# @ai: create a function to validate email addresses using regex
```

**How it works:**
1. Write your `@ai:` comment in INSERT mode
2. Press `ESC` to enter NORMAL mode
3. Wait 500ms (debounce time)
4. Code automatically generates below the comment!

### Manual Trigger

If you want to regenerate code for a comment:
1. Place your cursor on the comment line
2. Press `<leader>ai` (or your configured keymap)

### Commands

| Command | Description |
|---------|-------------|
| `:Comment2Code` | Generate code from @ai: comment on current line |
| `:Comment2CodeAll` | Process all @ai: comments in current buffer |
| `:Comment2CodeToggle` | Toggle plugin on/off |
| `:Comment2CodeEnable` | Enable plugin |
| `:Comment2CodeDisable` | Disable plugin |
| `:Comment2CodeStatus` | Show current status |
| `:Comment2CodeCancel` | Cancel all running jobs |
| `:Comment2CodeReset` | Reset plugin state |

## Configuration

```lua
require("comment2code").setup({
  -- Enable/disable the plugin
  enabled = true,
  
  -- Path to opencode CLI (auto-detected if in PATH)
  opencode_path = "opencode",
  
  -- Model to use (provider/model format)
  -- Default: "opencode/big-pickle"
  -- Examples: "anthropic/claude-sonnet-4-5", "openai/gpt-4o", "github-copilot/gpt-4o"
  model = "opencode/big-pickle",
  
  -- Pattern to detect AI comments
  trigger_pattern = "@ai:",
  
  -- Automatically process comments as you type
  auto_trigger = true,
  
  -- Debounce time in milliseconds (prevents excessive API calls)
  debounce_ms = 500,
  
  -- Show notifications
  notify = true,
  
  -- Keymaps
  keymaps = {
    manual_trigger = "<leader>ai", -- Set to false to disable
  },
})
```

### Available Models

You can use any model supported by opencode:

```lua
-- OpenCode (default)
model = "opencode/big-pickle"

-- Anthropic
model = "anthropic/claude-sonnet-4-5"
model = "anthropic/claude-opus-4"

-- OpenAI  
model = "openai/gpt-4o"
model = "openai/o1-preview"

-- GitHub Copilot
model = "github-copilot/gpt-4o"
```

## How It Works

1. **Detection**: The plugin monitors text changes and detects `@ai:` comments
2. **Deduplication**: Each comment is hashed (buffer + line + content) to prevent duplicate processing
3. **Context Building**: Surrounding code is sent to opencode for better context
4. **Async Execution**: `opencode run` runs asynchronously
5. **Code Insertion**: Generated code is inserted below the comment with matching indentation
6. **Tracking**: Processed comments are tracked to avoid regeneration

### Deduplication Strategy

The plugin uses a hash-based system to track processed comments:
- Hash = `buffer_id:line_number:trimmed_comment_text`
- Prevents automatic re-processing of the same comment
- Manual trigger (`<leader>ai`) bypasses this check for force regeneration

### Smart Code Detection

If there's already code below a comment, the plugin won't overwrite it automatically. Use manual trigger to force regeneration.

## Supported Languages

The plugin supports comment syntax for:

| Language | Comment Style |
|----------|--------------|
| Lua, SQL, Haskell | `-- @ai:` |
| Python, Ruby, Shell, YAML | `# @ai:` |
| JavaScript, TypeScript, C, C++, Rust, Go, Java | `// @ai:` |
| Vim | `" @ai:` |
| Lisp, Clojure | `; @ai:` |

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
