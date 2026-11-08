-- Minimal HTTP/1.1 server on libuv for the WriteTex tablet app.
local config = require('writetex.config')
local context = require('writetex.context')
local upstream = require('writetex.upstream')

local uv = vim.uv
local M = {}

local MAX_BODY = 10 * 1024 * 1024
local REASONS = { [200] = 'OK', [204] = 'No Content', [400] = 'Bad Request', [401] = 'Unauthorized',
  [404] = 'Not Found', [413] = 'Payload Too Large', [500] = 'Internal Server Error' }
local CORS = {
  ['Access-Control-Allow-Origin'] = '*',
  ['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS',
  ['Access-Control-Allow-Headers'] = 'Content-Type, Authorization',
}

local server ---@type uv.uv_tcp_t?

local function notify(msg, level)
  vim.schedule(function()
    vim.notify('WriteTex: ' .. msg, level or vim.log.levels.INFO)
  end)
end

local function head(client, code, headers)
  local lines = { ('HTTP/1.1 %d %s'):format(code, REASONS[code] or '') }
  for k, v in pairs(vim.tbl_extend('force', CORS, headers)) do
    table.insert(lines, k .. ': ' .. v)
  end
  client:write(table.concat(lines, '\r\n') .. '\r\n\r\n')
end

local function close(client)
  if not client:is_closing() then
    client:shutdown(function()
      client:close()
    end)
  end
end

local function send(client, code, body, ctype)
  if client:is_closing() then
    return
  end
  head(client, code, {
    ['Content-Type'] = ctype or 'application/json',
    ['Content-Length'] = tostring(#body),
    ['Connection'] = 'close',
  })
  client:write(body)
  close(client)
end

local function send_error(client, code, message)
  send(client, code, vim.json.encode({ error = { message = message } }))
end

---Decodes a complete chunked body; returns nil while incomplete.
local function dechunk(raw)
  local out, pos = {}, 1
  while true do
    local size_end = raw:find('\r\n', pos, true)
    if not size_end then
      return nil
    end
    local size = tonumber(raw:sub(pos, size_end - 1):match('^%x+'), 16)
    if not size then
      return nil
    end
    if size == 0 then
      return table.concat(out)
    end
    local data_end = size_end + 2 + size
    if #raw < data_end + 1 then
      return nil
    end
    table.insert(out, raw:sub(size_end + 2, data_end - 1))
    pos = data_end + 2
  end
end

-- Runs on the main loop: capture context, call upstream, relay, insert.
local function handle_completion(client, req)
  local target = context.capture()
  local provider = config.provider()
  if not (provider.endpoint and provider.model) then
    error(('provider %s needs an endpoint and a model'):format(provider.name))
  end
  local body = upstream.build(req, target, provider)
  local stream = body.stream
  local chunked = function(data)
    if #data > 0 and not client:is_closing() then
      client:write(('%x\r\n%s\r\n'):format(#data, data))
    end
  end

  if stream then
    head(client, 200, {
      ['Content-Type'] = 'text/event-stream',
      ['Cache-Control'] = 'no-cache',
      ['Transfer-Encoding'] = 'chunked',
      ['Connection'] = 'close',
    })
  end

  notify(('recognizing with %s…'):format(provider.name))
  upstream.post(body, provider, stream and chunked or function() end, function(status, raw)
    local text, err
    if status == 200 then
      if stream then
        text = upstream.collect_sse(raw)
      else
        local ok, json = pcall(vim.json.decode, raw)
        text = ok and vim.tbl_get(json, 'choices', 1, 'message', 'content') or nil
      end
    else
      err = status == 0 and raw or ('API error %d: %s'):format(status, raw)
    end

    if stream then
      if err and not client:is_closing() then
        chunked('data: ' .. vim.json.encode({ error = { message = err } }) .. '\n\n')
        chunked('data: [DONE]\n\n')
      end
      if not client:is_closing() then
        client:write('0\r\n\r\n')
        close(client)
      end
    elseif err then
      send_error(client, 500, err)
    else
      send(client, 200, raw)
    end

    vim.schedule(function()
      if err then
        vim.notify('WriteTex: ' .. err, vim.log.levels.ERROR)
        return
      end
      text = upstream.clean(text or '')
      if text == '' then
        vim.notify('WriteTex: empty result', vim.log.levels.WARN)
      else
        local inserted, reason = context.insert(target, text)
        if inserted then
          vim.notify('WriteTex: inserted ' .. text:gsub('\n.*', '…'))
        else
          vim.notify('WriteTex: copied to clipboard, not inserted: ' .. reason, vim.log.levels.WARN)
        end
      end
    end)
  end)
end

local function on_request(client, method, path, headers, body)
  path = path:gsub('%?.*$', '')
  if method == 'OPTIONS' then
    head(client, 204, { ['Content-Length'] = '0', ['Connection'] = 'close' })
    return close(client)
  end
  if method == 'GET' and path == '/health' then
    return send(client, 200, vim.json.encode({ ok = true, service = 'WriteTex Neovim', port = config.options.port }))
  end
  if method ~= 'POST' or (path ~= '/v1/chat/completions' and path ~= '/chat/completions') then
    return send_error(client, 404, 'Not found')
  end

  local ok, req = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
  if not ok or type(req) ~= 'table' or type(req.messages) ~= 'table' then
    return send_error(client, 400, 'Invalid request: messages required')
  end
  local token = (headers['authorization'] or ''):gsub('^[Bb]earer%s+', '')
  if token ~= config.options.token then
    return send_error(client, 401, 'Unauthorized')
  end
  vim.schedule(function()
    local ok2, e = pcall(handle_completion, client, req)
    if not ok2 then
      send_error(client, 500, tostring(e))
      notify(tostring(e), vim.log.levels.ERROR)
    end
  end)
end

local function on_connection(client)
  local buf = ''
  local method, path, headers, header_len
  client:read_start(function(err, data)
    if err or not data then
      return close(client)
    end
    buf = buf .. data
    if not method then
      local stop = buf:find('\r\n\r\n', 1, true)
      if not stop then
        if #buf > 64 * 1024 then
          send_error(client, 400, 'Header too large')
        end
        return
      end
      local lines = vim.split(buf:sub(1, stop - 1), '\r\n', { plain = true })
      method, path = lines[1]:match('^(%u+)%s+(%S+)')
      headers = {}
      for i = 2, #lines do
        local k, v = lines[i]:match('^([^:]+):%s*(.*)$')
        if k then
          headers[k:lower()] = v
        end
      end
      header_len = stop + 3
      if not method then
        return send_error(client, 400, 'Bad request line')
      end
    end

    local raw = buf:sub(header_len + 1)
    if #raw > MAX_BODY then
      client:read_stop()
      return send_error(client, 413, 'Request too large')
    end
    local body
    if (headers['transfer-encoding'] or ''):lower():find('chunked') then
      body = dechunk(raw)
    else
      local len = tonumber(headers['content-length'] or '0') or 0
      body = #raw >= len and raw:sub(1, len) or nil
    end
    if body then
      client:read_stop()
      on_request(client, method, path, headers, body)
    end
  end)
end

function M.is_running()
  return server ~= nil
end

function M.start()
  if server then
    return true
  end
  local opts = config.options
  local tcp = assert(uv.new_tcp())
  local ok, err = tcp:bind(opts.host, opts.port)
  if ok then
    ok, err = tcp:listen(128, function(lerr)
      if lerr then
        return
      end
      local client = assert(uv.new_tcp())
      tcp:accept(client)
      on_connection(client)
    end)
  end
  if not ok then
    tcp:close()
    vim.notify(('WriteTex: cannot listen on %s:%d (%s)'):format(opts.host, opts.port, err), vim.log.levels.ERROR)
    return false
  end
  server = tcp
  return true
end

function M.stop()
  if server then
    server:close()
    server = nil
  end
end

return M
