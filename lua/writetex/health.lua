local M = {}

function M.check()
  local config = require('writetex.config')
  local o = config.options
  vim.health.start('writetex.nvim')
  if vim.fn.executable('curl') == 1 then
    vim.health.ok('curl found')
  else
    vim.health.error('curl not found; it is used to call the vision API')
  end
  if not o.mdns then
    vim.health.info('LAN discovery off (mdns = false); enter this computer\'s IP in the app')
  elseif not require('writetex.mdns').available() then
    vim.health.warn('avahi-publish-service not found; install avahi or set mdns = false and enter the IP in the app')
  elseif vim.fn.executable('avahi-daemon') == 1 and vim.system({ 'avahi-daemon', '--check' }):wait().code ~= 0 then
    vim.health.warn('avahi-daemon is not running; start it (systemctl enable --now avahi-daemon) or set mdns = false')
  else
    vim.health.ok('LAN discovery via avahi')
  end
  if require('writetex.server').is_running() then
    vim.health.ok(('server running on %s:%d'):format(o.host, o.port))
  else
    vim.health.info('server stopped (:WriteTex start)')
  end
  local current = config.provider().name
  vim.health.start('writetex.nvim providers')
  for _, name in ipairs(config.names()) do
    local p = config.options.providers[name] or o.api
    local label = ('%s%s: %s at %s'):format(name, name == current and ' (active)' or '', p.model or '?', p.endpoint or '?')
    if not (p.endpoint and p.model) then
      vim.health.error(label .. ' — needs both endpoint and model')
    elseif p.key_env and (vim.env[p.key_env] or '') == '' and not p.key then
      vim.health.warn(('%s — $%s is not set'):format(label, p.key_env))
    elseif not (p.key or p.key_env) then
      vim.health.ok(label .. ' (no API key; sent without Authorization)')
    else
      vim.health.ok(label)
    end
  end
end

return M
