-- writetex.nvim: receive handwritten math from the WriteTex tablet app,
-- OCR it with an OpenAI-compatible vision model, insert the LaTeX at the cursor.
local config = require('writetex.config')
local server = require('writetex.server')
local mdns = require('writetex.mdns')

local M = {}

local function addresses()
  local out = {}
  for _, list in pairs(vim.uv.interface_addresses()) do
    for _, a in ipairs(list) do
      if a.family == 'inet' and not a.internal then
        table.insert(out, a.ip)
      end
    end
  end
  return out
end

function M.start()
  if not server.start() then
    return
  end
  if config.options.mdns then
    mdns.start(config.options.port)
  end
  local ips = table.concat(addresses(), ', ')
  vim.notify(('WriteTex: listening on port %d (%s)'):format(config.options.port, ips ~= '' and ips or 'no LAN address'))
end

function M.stop()
  server.stop()
  mdns.stop()
  vim.notify('WriteTex: stopped')
end

function M.toggle()
  if server.is_running() then
    M.stop()
  else
    M.start()
  end
end

local function describe(p)
  return ('%s (%s at %s)'):format(p.name, p.model or '?', p.endpoint or '?')
end

function M.status()
  local o = config.options
  local p = describe(config.provider())
  if not server.is_running() then
    return vim.notify('WriteTex: stopped; provider ' .. p)
  end
  vim.notify(('WriteTex: running on %s:%d → %s, LAN: %s'):format(o.host, o.port, p, table.concat(addresses(), ', ')))
end

---Name of the active provider, e.g. for a statusline.
function M.current()
  return config.provider().name
end

---Switch to provider `name`, or pick one from a menu when `name` is nil.
function M.provider(name)
  if name then
    if not config.use(name) then
      return vim.notify(('WriteTex: no provider %q (have: %s)'):format(name, table.concat(config.names(), ', ')),
        vim.log.levels.ERROR)
    end
    return vim.notify('WriteTex: using ' .. describe(config.provider()))
  end
  local current = M.current()
  vim.ui.select(config.names(), {
    prompt = 'WriteTex provider',
    format_item = function(n)
      local p = config.options.providers[n] or config.options.api
      return ('%s%s  %s'):format(n == current and '● ' or '  ', n, p.model or '')
    end,
  }, function(choice)
    if choice then
      M.provider(choice)
    end
  end)
end

function M.setup(opts)
  config.set(opts)
  local subs = { start = M.start, stop = M.stop, toggle = M.toggle, status = M.status, provider = M.provider }
  vim.api.nvim_create_user_command('WriteTex', function(args)
    local sub, arg = args.fargs[1] or 'toggle', args.fargs[2]
    local fn = subs[sub]
    if not fn then
      return vim.notify('WriteTex: unknown subcommand ' .. sub, vim.log.levels.ERROR)
    end
    fn(arg)
  end, {
    nargs = '*',
    complete = function(lead, line)
      local words = vim.split(line:sub(1, -#lead - 1), '%s+', { trimempty = true })
      local items = #words <= 1 and vim.tbl_keys(subs) or (words[2] == 'provider' and #words == 2) and config.names() or {}
      return vim.tbl_filter(function(s)
        return vim.startswith(s, lead)
      end, items)
    end,
    desc = 'WriteTex: start | stop | toggle | status | provider [name]',
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('writetex', { clear = true }),
    callback = function()
      server.stop()
      mdns.stop()
    end,
  })
  if config.options.autostart then
    M.start()
  end
end

return M
