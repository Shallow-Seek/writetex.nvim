-- Default options; setup() deep-merges user opts over these.
local M = {}

M.defaults = {
  -- Local server the tablet app talks to (same protocol as writetex-vscode).
  host = '0.0.0.0',
  port = 50905,
  -- Bearer token the app must send as its "API Key". The app's default is "writetex".
  token = 'writetex',
  -- Start the server when setup() runs.
  autostart = false,
  -- Advertise the server on the LAN with avahi-publish-service (Linux), if installed.
  mdns = true,
  -- Upstream OpenAI-compatible vision model.
  api = {
    endpoint = 'https://api.openai.com/v1',
    model = 'gpt-4o',
    key = nil, -- literal key; prefer key_env
    key_env = nil, -- name of an environment variable holding the key
    timeout = 300, -- seconds
  },
  -- Extra JSON fields merged into every upstream request, e.g.
  -- { chat_template_kwargs = { enable_thinking = false } }.
  -- model, messages and stream cannot be overridden; max_tokens can.
  extra_body = {},
  -- Appended to the system prompt.
  custom_prompt = '',
  context = {
    line_radius = 20,
    char_limit = 2000,
  },
  -- Results are inserted at the cursor only in these filetypes; elsewhere they go
  -- to the + register (and the unnamed one). Set to false to insert in any modifiable buffer.
  filetypes = { 'tex', 'plaintex', 'latex', 'bib', 'markdown', 'rmd', 'quarto', 'typst', 'pandoc' },
  -- Clean up model output before inserting.
  strip_think = true, -- drop a leading <think>...</think> block
  strip_code_fences = true, -- unwrap a single ```lang ... ``` block
  -- Move the cursor to the end of the inserted text.
  move_cursor = true,
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  -- extra_body is replaced, not merged, so a user can clear the default table.
  if opts and opts.extra_body ~= nil then
    M.options.extra_body = opts.extra_body
  end
  return M.options
end

function M.api_key()
  local api = M.options.api
  if api.key_env and api.key_env ~= '' then
    local v = vim.env[api.key_env]
    if v and v ~= '' then
      return v
    end
  end
  return api.key
end

return M
