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
  -- Named OpenAI-compatible vision providers to switch between with :WriteTex provider.
  -- Each takes endpoint, model, key, key_env, timeout and extra_body (fields missing
  -- here fall back to `api` and the top-level `extra_body`). Leave empty to use only `api`.
  providers = {},
  -- Provider used at startup. nil: the remembered one, else the first by name.
  provider = nil,
  -- Remember the last provider picked with :WriteTex provider across restarts.
  remember_provider = true,
  -- The provider used when `providers` is empty, and defaults for the named ones.
  api = {
    endpoint = 'https://api.openai.com/v1',
    model = 'gpt-4o',
    key = nil, -- literal key; prefer key_env
    key_env = nil, -- name of an environment variable holding the key
    timeout = 300, -- seconds
  },
  -- Extra JSON fields merged into every upstream request, e.g.
  -- { chat_template_kwargs = { enable_thinking = false } }. A provider's own
  -- extra_body is merged over this one.
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

-- Name used for `api` when no providers are configured.
local DEFAULT = 'default'
local state_file = vim.fn.stdpath('state') .. '/writetex.json'
local active ---@type string?

local function read_state()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(state_file), '\n'))
  end)
  return ok and type(data) == 'table' and data or {}
end

local function write_state(data)
  pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(state_file, ':h'), 'p')
    vim.fn.writefile({ vim.json.encode(data) }, state_file)
  end)
end

---Configured provider names, sorted.
---@return string[]
function M.names()
  local names = vim.tbl_keys(M.options.providers or {})
  if #names == 0 then
    return { DEFAULT }
  end
  table.sort(names)
  return names
end

-- Drops vim.NIL values, so a provider can remove a field from the shared extra_body.
local function drop_nil(t)
  for k, v in pairs(t) do
    if v == vim.NIL then
      t[k] = nil
    elseif type(v) == 'table' then
      drop_nil(v)
    end
  end
  return t
end

local function exists(name)
  return name ~= nil and vim.tbl_contains(M.names(), name)
end

function M.set(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  -- extra_body is replaced, not merged, so a user can clear the default table.
  if opts and opts.extra_body ~= nil then
    M.options.extra_body = opts.extra_body
  end

  local remembered = M.options.remember_provider and read_state().provider or nil
  if M.options.provider and not exists(M.options.provider) then
    vim.notify(('WriteTex: provider %q is not configured'):format(M.options.provider), vim.log.levels.WARN)
  end
  -- An explicit `provider` wins only when nothing was remembered, so a pick
  -- made with :WriteTex provider survives restarts.
  active = (exists(remembered) and remembered)
    or (exists(M.options.provider) and M.options.provider)
    or M.names()[1]
  return M.options
end

---Switch the active provider.
---@return boolean ok
function M.use(name)
  if not exists(name) then
    return false
  end
  active = name
  if M.options.remember_provider then
    write_state({ provider = name })
  end
  return true
end

---The active provider with its key resolved. A named provider takes only
---`timeout` from `api` (never its endpoint or key, so a key can't leak to
---another service) and has its extra_body merged over the top-level one.
---@return { name: string, endpoint: string?, model: string?, key: string?, key_env: string?, timeout: number, extra_body: table }
function M.provider()
  local o = M.options
  local name = exists(active) and active or M.names()[1]
  local p = (o.providers or {})[name] or o.api
  local key = p.key
  if p.key_env and p.key_env ~= '' and (vim.env[p.key_env] or '') ~= '' then
    key = vim.env[p.key_env]
  end
  return {
    name = name,
    endpoint = p.endpoint,
    model = p.model,
    key = key,
    key_env = p.key_env,
    timeout = p.timeout or o.api.timeout,
    extra_body = drop_nil(vim.tbl_deep_extend('force', vim.deepcopy(o.extra_body or {}),
      p == o.api and {} or vim.deepcopy(p.extra_body or {}))),
  }
end

return M
