-- Builds the upstream request and runs it through curl.
local config = require('writetex.config')

local M = {}

local PROMPT = [[You are an OCR expert for LaTeX/TikZ/Markdown/Typst. The user is working in their code editor with file: %s. Your output will be placed at the user's cursor. When extracting content from images, return ONLY the exact code necessary. Prefer formatting consistent with the provided editor context. Do not include preamble/packages. If TikZ content is detected, output ONLY the body unless the context indicates the absence of a tikzpicture wrapper. If a variable is ambiguous, match the surrounding context.
Surrounding Context:---------------
%s
---------------No commentary, no explanations, no prose, no code blocks. If the context is not relevant to the image, perform a simple OCR.]]

local function has_image(msg)
  if type(msg.content) ~= 'table' then
    return false
  end
  for _, part in ipairs(msg.content) do
    if part.type == 'image_url' then
      return true
    end
  end
  return false
end

---Turns the app's request into the upstream request: injects the editor
---context, keeps only the images from user messages, applies the provider's
---model and extra_body (`provider` comes from config.provider()).
function M.build(req, ctx, provider)
  local opts = config.options
  local messages = req.messages
  if ctx and vim.iter(messages):any(has_image) then
    local system = PROMPT:format(ctx.file, ctx.surrounding)
    if opts.custom_prompt and opts.custom_prompt ~= '' then
      system = system .. '\n\nCustom User Instructions:\n' .. opts.custom_prompt
    end
    messages = { { role = 'system', content = system } }
    for _, msg in ipairs(req.messages) do
      if msg.role == 'user' and has_image(msg) then
        msg = vim.tbl_extend('force', msg, {
          content = vim.tbl_filter(function(p)
            return p.type == 'image_url'
          end, msg.content),
        })
      end
      table.insert(messages, msg)
    end
  end

  local body = vim.deepcopy(provider.extra_body)
  body.model = provider.model
  body.messages = messages
  body.stream = req.stream ~= false
  body.max_tokens = body.max_tokens or req.max_tokens or 10000
  return body
end

---Joins the `delta.content` of an OpenAI SSE stream.
function M.collect_sse(raw)
  local out = {}
  for line in raw:gmatch('[^\r\n]+') do
    local data = line:match('^data:%s*(.*)$')
    if data and data ~= '[DONE]' then
      local ok, chunk = pcall(vim.json.decode, data)
      local content = ok and type(chunk) == 'table' and vim.tbl_get(chunk, 'choices', 1, 'delta', 'content')
      if type(content) == 'string' then
        table.insert(out, content)
      end
    end
  end
  return table.concat(out)
end

function M.clean(text)
  local opts = config.options
  text = vim.trim(text)
  if opts.strip_think then
    text = vim.trim((text:gsub('^<think>.-</think>', '')))
  end
  if opts.strip_code_fences then
    local inner = text:match('^```[%w_+-]*\n(.-)\n?```$')
    if inner then
      text = vim.trim(inner)
    end
  end
  return text
end

---POSTs `body` to the provider's chat/completions endpoint.
---`on_data(chunk)` receives the response body as it arrives when the status is 200;
---`on_done(status, body_or_error)` runs once at the end. Both run in a fast (luv) context.
---@return vim.SystemObj
function M.post(body, provider, on_data, on_done)
  local url = provider.endpoint:gsub('/+$', '') .. '/chat/completions'
  local cmd = {
    'curl', '-sS', '-N', '-i', '--max-time', tostring(provider.timeout),
    '-X', 'POST', url,
    '-H', 'Content-Type: application/json',
    '-H', 'Expect:',
    '--data-binary', '@-',
  }
  if provider.key and provider.key ~= '' then
    vim.list_extend(cmd, { '-H', 'Authorization: Bearer ' .. provider.key })
  end

  local head, status, rest = '', nil, {}
  return vim.system(cmd, {
    stdin = vim.json.encode(body),
    stdout = function(_, data)
      if not data then
        return
      end
      if not status then
        head = head .. data
        local stop = head:find('\r\n\r\n', 1, true)
        if not stop then
          return
        end
        status = tonumber(head:match('^HTTP/%S+%s+(%d+)')) or 0
        data = head:sub(stop + 4)
      end
      if status == 200 then
        on_data(data)
      end
      table.insert(rest, data)
    end,
  }, function(obj)
    if obj.code ~= 0 then
      on_done(0, 'curl: ' .. vim.trim(obj.stderr or ('exit ' .. obj.code)))
    else
      on_done(status or 0, table.concat(rest))
    end
  end)
end

return M
