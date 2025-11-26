# comment2code.nvim

Write a comment, get code. Powered by [OpenCode](https://github.com/sst/opencode).

```lua
-- @ai: create a function that calculates fibonacci
```

Move your cursor away, and the code appears below. That's it.

Inspired by [ThePrimeagen's](https://github.com/theprimeagen) workflow.

## Requirements

- Neovim 0.10+
- [OpenCode CLI](https://github.com/sst/opencode) installed and configured

## Installation

**lazy.nvim**
```lua
{
  "EmreOzdemiroglu/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

**packer.nvim**
```lua
use {
  "EmreOzdemiroglu/comment2code.nvim",
  config = function()
    require("comment2code").setup()
  end,
}
```

**vim-plug**
```vim
Plug 'EmreOzdemiroglu/comment2code.nvim'
lua require("comment2code").setup()
```

## Quick Start

Write an `@ai:` comment in any language:

```javascript
// @ai: create a debounce function with configurable delay
```

```python
# @ai: validate email addresses using regex
```

Leave the line. Code generates automatically.

Want to regenerate? Press `<leader>ai` on the comment.
Process all comments in a file? Press `<leader>aA`.

## Refactoring

Add a comment above existing code to refactor it:

```python
# @ai: optimize this for performance
def slow_function(items):
    result = []
    for item in items:
        if item not in result:
            result.append(item)
    return result
```

Press `<leader>ai` and the code below gets replaced with the optimized version.

## Modes

The plugin has three modes that control when code generation triggers:

### manual

Nothing happens automatically. You control everything with `<leader>ai`.

Good for: expensive API calls, reviewing prompts before sending.

### auto_linear

When you start writing a *new* `@ai:` comment, the *previous* one triggers.

```lua
-- @ai: create a helper function
-- ^ triggers when you start typing below

-- @ai: create the main function
```

Good for: writing multiple prompts in sequence, building up code incrementally.

### auto_nonlinear (default)

Code generates when your cursor leaves the comment line.

Good for: exploratory coding, jumping around a file.

---

Switch modes anytime:
```vim
:Comment2CodeMode manual
:Comment2CodeMode auto_linear
:Comment2CodeMode auto_nonlinear
```

## Configuration

```lua
require("comment2code").setup({
  enabled = true,
  opencode_path = "opencode",
  model = "anthropic/claude-sonnet-4-20250514",
  trigger_pattern = "@ai:",
  mode = "auto_nonlinear",
  debounce_ms = 500,
  notify = true,
  keymaps = {
    manual_trigger = "<leader>ai",
    process_all = "<leader>aA",
  },
})
```

### Models

Any model OpenCode supports:

```lua
model = "anthropic/claude-sonnet-4-20250514"
model = "openai/gpt-4o"
model = "github-copilot/gpt-4o"
```

## Commands

| Command | What it does |
|---------|--------------|
| `:Comment2Code` | Generate code from comment on current line |
| `:Comment2CodeAll` | Process all comments in buffer |
| `:Comment2CodeToggle` | Toggle on/off |
| `:Comment2CodeStatus` | Show status |
| `:Comment2CodeMode` | Get or set mode |
| `:Comment2CodeCancel` | Cancel running jobs |
| `:Comment2CodeReset` | Reset state |

## Supported Languages

Works with any language that has comments:

| Style | Languages |
|-------|-----------|
| `-- @ai:` | Lua, SQL, Haskell |
| `# @ai:` | Python, Ruby, Shell, YAML |
| `// @ai:` | JavaScript, TypeScript, C, C++, Rust, Go, Java |
| `" @ai:` | Vim |
| `; @ai:` | Lisp, Clojure |
| `<!-- @ai: -->` | HTML, XML |
| `/* @ai: */` | CSS |

## How It Works

1. Detects `@ai:` comments
2. Queues them (multiple triggers are processed one at a time)
3. Sends context to OpenCode
4. Inserts generated code below the comment
5. Tracks what's been processed to avoid duplicates

The plugin re-finds comments by their text content before inserting, so code always lands in the right place even when line numbers shift.

## License

MIT

## Credits

- [OpenCode](https://github.com/sst/opencode) - powers the code generation
- [ThePrimeagen](https://github.com/theprimeagen) - the workflow inspiration
