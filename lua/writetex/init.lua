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

function M.status()
  local o = config.options
  if not server.is_running() then
    return vim.notify('WriteTex: stopped')
  end
  vim.notify(('WriteTex: running on %s:%d → %s (%s), LAN: %s'):format(
    o.host, o.port, o.api.endpoint, o.api.model, table.concat(addresses(), ', ')))
end

function M.setup(opts)
  config.set(opts)
  local subs = { start = M.start, stop = M.stop, toggle = M.toggle, status = M.status }
  vim.api.nvim_create_user_command('WriteTex', function(args)
    local fn = subs[args.args ~= '' and args.args or 'toggle']
    if not fn then
      return vim.notify('WriteTex: unknown subcommand ' .. args.args, vim.log.levels.ERROR)
    end
    fn()
  end, {
    nargs = '?',
    complete = function()
      return vim.tbl_keys(subs)
    end,
    desc = 'WriteTex server: start | stop | toggle | status',
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
