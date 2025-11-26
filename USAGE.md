# How to Use comment2code.nvim

## The Workflow

1. **Open Neovim**
   ```bash
   nvim test.js
   ```

2. **Enter INSERT mode and type:**
   ```javascript
   // @ai: create a hello world function
   ```

3. **Press ESC to enter NORMAL mode**
   - The 500ms timer starts NOW
   - You can move around, but stay in normal mode

4. **Wait 500ms**
   - You'll see: "[comment2code] Generating code..."
   - Code appears below your comment automatically!

## Important Notes

✅ The colon after `@ai` is REQUIRED:
   - Correct: `// @ai: your prompt`
   - Wrong: `// @ai your prompt`

✅ The timer starts when you press ESC (enter normal mode)
   - While typing in INSERT mode: No trigger (think freely!)
   - After pressing ESC: 500ms countdown begins

✅ Force immediate generation:
   - Place cursor on the `@ai:` line
   - Press `<leader>ai` (default keymap)

## Quick Test

```bash
nvim /Users/mreative/dev/comment2code.nvim/test.js
```

Then try typing the examples in the file!
