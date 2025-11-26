# comment2code.nvim

Generate code from AI comments using [OpenCode](https://github.com/sst/opencode).

Inspired by [ThePrimeagen's](https://github.com/theprimeagen) workflow - write a comment like `// @ai: create a function to calculate fibonacci` and watch as the code appears below it automatically!

## Features

- **Automatic Code Generation**: Write `@ai:` comments and code generates automatically
- **Code Refactoring**: Refactor existing code by adding an `@ai:` comment above it
- **Multi-Language Support**: Works with 30+ languages (Lua, Python, JavaScript, TypeScript, Rust, Go, etc.)
- **Smart Deduplication**: Won't regenerate code that already exists
- **Sequential Processing**: Process multiple comments safely - code always inserts at the correct position
- **Manual Re-trigger**: Force regeneration with a keymap
- **Non-blocking**: Async execution keeps your editor responsive

## Requirements

- Neovim 0.10+ (for `vim.system`)
- [OpenCode CLI](https://github.com/sst/opencode) installed and configured

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "EmreOzdemiroglu/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "EmreOzdemiroglu/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'EmreOzdemiroglu/comment2code.nvim'

" In your init.lua or after plugin loads:
lua require("comment2code").setup()
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
3. Move cursor away from the comment line (or wait for debounce)
4. Code automatically generates below the comment!

### Manual Trigger

To generate or regenerate code for a comment:
1. Place your cursor on the comment line
2. Press `<leader>ai` (or your configured keymap)

### Process All Comments

To process all `@ai:` comments in the current buffer:
1. Press `<leader>aA` (or your configured keymap)
2. Comments are processed sequentially from top to bottom
3. Each comment's code is inserted at the correct position

### Refactoring Existing Code

You can use `@ai:` comments to refactor existing code:

1. Add an `@ai:` comment **above** the code you want to refactor
2. The code region extends until the next `@ai:` comment or end of file
3. Press `<leader>ai` to trigger refactoring

```python
# @ai: optimize this function for better performance
def slow_function(items):
    result = []
    for item in items:
        if item not in result:
            result.append(item)
    return result

# @ai: next comment starts here, so the region above will be refactored
```

When you press `<leader>ai` on the first comment, the plugin will:
- Detect the code below (until the next `@ai:` comment)
- Send it to the AI with your refactoring instruction
- Replace the original code with the refactored version

### Keymaps

| Keymap | Description |
|--------|-------------|
| `<leader>ai` | Generate/regenerate code from @ai: comment on current line |
| `<leader>aA` | Process all @ai: comments in buffer (sequentially) |

### Commands

| Command | Description |
|---------|-------------|
| `:Comment2Code` | Generate code from @ai: comment on current line |
| `:Comment2CodeAll` | Process all @ai: comments in current buffer |
| `:Comment2CodeToggle` | Toggle plugin on/off |
| `:Comment2CodeEnable` | Enable plugin |
| `:Comment2CodeDisable` | Disable plugin |
| `:Comment2CodeStatus` | Show current status |
| `:Comment2CodeMode [mode]` | Get/set activation mode |
| `:Comment2CodeCancel` | Cancel all running jobs |
| `:Comment2CodeReset` | Reset plugin state |

### Activation Modes

The plugin supports three activation modes:

| Mode | Description |
|------|-------------|
| `manual` | Only triggers via `<leader>ai` keymap or `:Comment2Code` command |
| `auto_linear` | Triggers the previous @ai: comment when you start writing a new one |
| `auto_nonlinear` | Triggers when cursor moves away from the @ai: comment line (default) |

Change mode at runtime:
```vim
:Comment2CodeMode manual
:Comment2CodeMode auto_linear
:Comment2CodeMode auto_nonlinear
```

## Configuration

```lua
require("comment2code").setup({
  -- Enable/disable the plugin
  enabled = true,
  
  -- Path to opencode CLI (auto-detected if in PATH)
  opencode_path = "opencode",
  
  -- Model to use (provider/model format)
  model = "anthropic/claude-sonnet-4-20250514",
  
  -- Pattern to detect AI comments
  trigger_pattern = "@ai:",
  
  -- Activation mode: "manual", "auto_linear", or "auto_nonlinear"
  mode = "auto_nonlinear",
  
  -- Debounce time in milliseconds (prevents excessive API calls)
  debounce_ms = 500,
  
  -- Show notifications
  notify = true,
  
  -- Keymaps (set to false to disable)
  keymaps = {
    manual_trigger = "<leader>ai",
    process_all = "<leader>aA",
  },
})
```

### Available Models

You can use any model supported by OpenCode:

```lua
-- Anthropic
model = "anthropic/claude-sonnet-4-20250514"
model = "anthropic/claude-opus-4"

-- OpenAI  
model = "openai/gpt-4o"
model = "openai/o1-preview"

-- GitHub Copilot
model = "github-copilot/gpt-4o"
```

## How It Works

1. **Detection**: The plugin monitors text changes and detects `@ai:` comments
2. **Queuing**: Multiple triggers are queued and processed sequentially
3. **Smart Re-finding**: Comments are located by text content (not line number) to handle line shifts
4. **Context Building**: Surrounding code is sent to OpenCode for better context
5. **Async Execution**: `opencode run` executes asynchronously
6. **Code Insertion**: Generated code is inserted below the comment with matching indentation
7. **Tracking**: Processed comments are tracked to avoid regeneration

### Sequential Processing

When you trigger multiple comments (via `<leader>ai` repeatedly or `<leader>aA`), the plugin:
1. Queues all requests
2. Processes them one at a time
3. Re-finds each comment by its text content before inserting code
4. This ensures code always inserts at the correct position, even after previous insertions shift line numbers

### Smart Code Detection

- If there's already code below a comment, the plugin won't overwrite it automatically
- Use `<leader>ai` to force regeneration or trigger refactoring mode
- The plugin strips markdown code fences and `@ai:` comments from AI output

## Supported Languages

The plugin supports comment syntax for:

| Language | Comment Style |
|----------|--------------|
| Lua, SQL, Haskell | `-- @ai:` |
| Python, Ruby, Shell, YAML | `# @ai:` |
| JavaScript, TypeScript, C, C++, Rust, Go, Java | `// @ai:` |
| Vim | `" @ai:` |
| Lisp, Clojure | `; @ai:` |
| HTML, XML | `<!-- @ai: -->` |
| CSS | `/* @ai: */` |

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

- [OpenCode](https://github.com/sst/opencode) - The AI CLI tool that powers code generation
- [ThePrimeagen](https://github.com/theprimeagen) - Inspiration for the workflow
