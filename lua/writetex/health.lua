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
  vim.health.info(('upstream: %s, model %s'):format(o.api.endpoint, o.api.model))
  if not config.api_key() then
    vim.health.info('no API key set; requests are sent without Authorization')
  end
end

return M
