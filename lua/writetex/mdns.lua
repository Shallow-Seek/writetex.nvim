-- Advertises the server as _writetex-vscode._tcp, the service type the app looks for.
local M = {}

local proc ---@type vim.SystemObj?

function M.available()
  return vim.fn.executable('avahi-publish-service') == 1
end

function M.start(port)
  if proc or not M.available() then
    return
  end
  local name = 'WriteTex Neovim @ ' .. vim.uv.os_gethostname()
  local this
  this = vim.system({ 'avahi-publish-service', name, '_writetex-vscode._tcp', tostring(port), 'fork=Neovim' }, {}, function(obj)
    if proc == this then
      proc = nil
    end
    -- 0 or killed by stop(): nothing to report.
    if obj.code ~= 0 and obj.signal == 0 then
      vim.schedule(function()
        vim.notify('WriteTex: LAN discovery unavailable (' .. vim.trim(obj.stderr or '') .. '); enter this computer\'s IP in the app',
          vim.log.levels.WARN)
      end)
    end
  end)
  proc = this
end

function M.stop()
  if proc then
    proc:kill('sigterm')
    proc = nil
  end
end

return M
