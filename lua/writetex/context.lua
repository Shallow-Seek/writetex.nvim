-- Captures the insertion target and the text around the cursor.
local config = require('writetex.config')

local M = {}

local MARKER = '<<<User Cursor Here>>>'
local ns = vim.api.nvim_create_namespace('writetex')

---Byte column where text should go: at the cursor in insert mode, after the
---character under the cursor in normal mode (like `a`).
local function insert_col(line, col, mode)
  if mode:sub(1, 1) == 'i' or line == '' then
    return math.min(col, #line)
  end
  local ch = vim.fn.strpart(line, col, 1, 1)
  return math.min(col + #ch, #line)
end

---Snapshot of the current window. Must run on the main loop.
---@return table
function M.capture()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local mode = vim.api.nvim_get_mode().mode
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  col = insert_col(line, col, mode)

  local opts = config.options.context
  local count = vim.api.nvim_buf_line_count(buf)
  local first = math.max(0, row - opts.line_radius)
  local last = math.min(count - 1, row + opts.line_radius)
  local above = vim.api.nvim_buf_get_lines(buf, first, row, false)
  local below = vim.api.nvim_buf_get_lines(buf, row + 1, last + 1, false)

  table.insert(above, line:sub(1, col))
  local before = table.concat(above, '\n')
  table.insert(below, 1, line:sub(col + 1))
  local after = table.concat(below, '\n')

  local text = before .. '\n' .. MARKER .. '\n' .. after
  if #text > opts.char_limit then
    local half = math.floor(opts.char_limit / 2)
    text = before:sub(-half) .. '\n' .. MARKER .. '\n' .. after:sub(1, half)
  end

  local name = vim.api.nvim_buf_get_name(buf)
  return {
    buf = buf,
    win = win,
    mark = vim.api.nvim_buf_set_extmark(buf, ns, row, col, {}),
    file = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[No Name]',
    filetype = vim.bo[buf].filetype,
    surrounding = text,
  }
end

---Why `target` can't take the text, or nil if it can.
local function refusal(target)
  local buf = target.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return 'the buffer was closed'
  end
  if not vim.bo[buf].modifiable then
    return 'the buffer is not modifiable'
  end
  local fts = config.options.filetypes
  if fts and not vim.tbl_contains(fts, target.filetype) then
    local ft = target.filetype ~= '' and target.filetype or 'no filetype'
    return ('%s is not in the filetypes option'):format(ft)
  end
end

---Insert `text` at the captured position, or put it in the clipboard registers.
---Must run on the main loop.
---@return boolean inserted
---@return string? reason why it was not inserted
function M.insert(target, text)
  local opts = config.options
  local buf = target.buf
  local reason = refusal(target)
  if reason then
    vim.fn.setreg('+', text)
    vim.fn.setreg('"', text)
    return false, reason
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, target.mark, {})
  vim.api.nvim_buf_del_extmark(buf, ns, target.mark)
  local row, col = pos[1], pos[2]
  local lines = vim.split(text, '\n', { plain = true })
  vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)

  if opts.move_cursor and vim.api.nvim_win_is_valid(target.win) and vim.api.nvim_win_get_buf(target.win) == buf then
    local end_row = row + #lines - 1
    local end_col = (#lines == 1 and col or 0) + #lines[#lines]
    if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 'i' and end_col > 0 then
      -- Normal mode: rest on the last inserted character, not past it.
      local last = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ''
      end_col = end_col - 1 + vim.str_utf_start(last, end_col)
    end
    vim.api.nvim_win_set_cursor(target.win, { end_row + 1, end_col })
  end
  return true
end

return M
