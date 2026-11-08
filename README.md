# writetex.nvim

Write math by hand on your tablet and get LaTeX at your Neovim cursor.

writetex.nvim works with the [WriteTex](https://www.writetex.com) app for Android tablets and iPad. You write a formula in the app and send it. Neovim passes the drawing, along with the text around your cursor, to a vision model of your choice (OpenAI, or your own local model). The LaTeX it returns is inserted where your cursor is.

It's a Neovim port of the [WriteTex VS Code extension](https://github.com/jacklitstar/writetex-vscode) and runs the same local server, so the app works with it unchanged.

```
┌──────────────┐  image   ┌──────────────────────────┐  image + context  ┌──────────────────┐
│ WriteTex app │ ───────▶ │ Neovim (writetex.nvim)   │ ────────────────▶ │ vision model     │
│ tablet       │  :50905  │ inserts LaTeX at cursor  │ ◀──────────────── │ (OpenAI-compat.) │
└──────────────┘          └──────────────────────────┘      LaTeX        └──────────────────┘
```

## Features

- **Uses your file as context.** The lines around the cursor are sent with the image, so the model matches your notation and knows whether it's inside math mode.
- **Works with any OpenAI-compatible vision model:** OpenAI, OpenRouter, or a local llama.cpp, vLLM, SGLang or Ollama server.
- **Several providers, switch any time.** Set up a local model and a cloud one (Groq, OpenAI, …) and switch with `:WriteTex provider`, even while the server is running.
- **`extra_body` option** for provider-specific settings, such as turning off reasoning so recognition is fast.
- **Inserts at the right place:** where the cursor was when the image arrived, even if you move afterwards. The cursor then moves past the new text, so the next formula follows it.
- **Cleans up the output:** removes `<think>` blocks and ```` ```latex ```` fences.
- **No plugin dependencies.** Pure Lua plus `curl`.

## Requirements

- Neovim 0.10 or newer
- `curl`
- The WriteTex app on an Android tablet or iPad, on the same network as your computer
- An OpenAI-compatible model that accepts images
- Optional: [Avahi](https://avahi.org/) (`avahi-publish-service` with `avahi-daemon` running), so the app can find your computer by itself. Without it, you type the computer's IP into the app.

## Installation

### lazy.nvim

```lua
{
  "Shallow-Seek/writetex.nvim",
  cmd = "WriteTex",
  opts = {
    api = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o",
      key_env = "OPENAI_API_KEY", -- name of the environment variable that holds your key
    },
  },
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/Shallow-Seek/writetex.nvim" })
require("writetex").setup({
  api = { endpoint = "https://api.openai.com/v1", model = "gpt-4o", key_env = "OPENAI_API_KEY" },
})
```

### Manually

```sh
git clone https://github.com/Shallow-Seek/writetex.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/writetex.nvim
```

Then call `require("writetex").setup({ ... })` in your config.

After installing, run `:checkhealth writetex`.

## Quick start

1. **Start the server** in Neovim with `:WriteTex start`. It shows the port and your computer's LAN addresses:
   ```
   WriteTex: listening on port 50905 (192.168.1.104)
   ```
2. **Set up the app.** Open the WriteTex app's settings and fill in:

   | Field | Value |
   |---|---|
   | API Endpoint | `http://<your computer's IP>:50905`, for example `http://192.168.1.104:50905` |
   | API Key | `writetex` (it must match the plugin's `token` option) |
   | Model Name | anything; the plugin uses the active provider's model |

3. **Write a formula.** Open a `.tex` (or Markdown, Typst, …) file and put the cursor where the formula should go. Write it in the app and send it. The LaTeX appears at the cursor, and the app shows the result too.

Run `:WriteTex stop` when you're done.

## Commands

| Command | |
|---|---|
| `:WriteTex start` | Start the server (and LAN discovery, if enabled) |
| `:WriteTex stop` | Stop it |
| `:WriteTex toggle` | Start or stop. This is also what `:WriteTex` with no argument does |
| `:WriteTex status` | Show the port, active provider and LAN addresses |
| `:WriteTex provider` | Pick the provider from a menu |
| `:WriteTex provider <name>` | Switch to that provider (names complete with <kbd>Tab</kbd>) |

The same functions are available from Lua, for keymaps and statuslines:

```lua
vim.keymap.set("n", "<leader>wt", function() require("writetex").toggle() end, { desc = "WriteTex server" })
vim.keymap.set("n", "<leader>wp", function() require("writetex").provider() end, { desc = "WriteTex provider" })
-- require("writetex").current() returns the active provider's name
```

## Configuration

All options, with their defaults:

```lua
require("writetex").setup({
  host = "0.0.0.0",       -- address to listen on; set your LAN IP to accept only that interface
  port = 50905,           -- the port the app sends to
  token = "writetex",     -- the app must send this as its "API Key"
  autostart = false,      -- start the server when setup() runs
  mdns = true,            -- advertise on the LAN via avahi-publish-service

  -- Named providers to switch between; see "Providers" below. When empty,
  -- `api` is the only provider.
  providers = {},
  provider = nil,           -- provider to start with (default: the first by name)
  remember_provider = true, -- the last one picked with :WriteTex provider wins after a restart

  -- The provider used when `providers` is empty. Its `timeout` is also the
  -- default for named providers.
  api = {
    endpoint = "https://api.openai.com/v1", -- base URL; /chat/completions is appended
    model = "gpt-4o",
    key = nil,            -- the API key itself
    key_env = nil,        -- or the name of an environment variable holding it (tried first)
    timeout = 300,        -- seconds
  },

  -- Extra JSON fields merged into every request to the model, for every provider.
  -- model, messages and stream can't be overridden; max_tokens can.
  extra_body = {},

  custom_prompt = "",     -- appended to the system prompt

  context = {
    line_radius = 20,     -- lines above and below the cursor sent as context
    char_limit = 2000,    -- maximum characters of context
  },

  -- Only these filetypes get the result inserted. In other buffers it goes to
  -- the + and " registers. Set to false to insert into any modifiable buffer.
  filetypes = { "tex", "plaintex", "latex", "bib", "markdown", "rmd", "quarto", "typst", "pandoc" },

  strip_think = true,       -- remove a leading <think>...</think> block
  strip_code_fences = true, -- unwrap a single ```lang ... ``` block
  move_cursor = true,       -- move the cursor to the end of the inserted text
})
```

### Providers

For one model, `api` is enough. To switch between several, list them under `providers`. Each one takes:

| Field | |
|---|---|
| `endpoint` | Base URL of the OpenAI-compatible API (required) |
| `model` | Model name (required) |
| `key_env` / `key` | Environment variable holding the API key, or the key itself. Named providers never use `api`'s key, so one service's key isn't sent to another. |
| `timeout` | Seconds (default: `api.timeout`) |
| `extra_body` | Extra request fields for this provider, merged over the top-level `extra_body`. Set a field to `vim.NIL` to remove a shared one. |

This example has a local model and Groq, both with reasoning off:

```lua
require("writetex").setup({
  provider = "local", -- start with this one
  providers = {
    ["local"] = {
      endpoint = "http://127.0.0.1:8080/v1",
      model = "your-model-name", -- as listed by GET /v1/models
      key = "dummy",             -- if the server doesn't check keys
      extra_body = { chat_template_kwargs = { enable_thinking = false } },
    },
    groq = {
      endpoint = "https://api.groq.com/openai/v1",
      model = "qwen/qwen3.8-27b",
      key_env = "GROQ_API_KEY",
      extra_body = { reasoning_effort = "none" },
    },
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o",
      key_env = "OPENAI_API_KEY",
    },
  },
})
```

Then `:WriteTex provider groq`, or `:WriteTex provider` for a menu. The switch applies to the next image; the server keeps running.

#### Turning reasoning off

Reasoning models think before answering, which can make each formula take many times longer. Each API has its own switch, set through `extra_body`:

| Where the model runs | `extra_body` |
|---|---|
| llama.cpp, vLLM, SGLang (Qwen3-style chat templates) | `{ chat_template_kwargs = { enable_thinking = false } }` |
| Groq, Qwen3 models | `{ reasoning_effort = "none" }` ([Groq docs](https://console.groq.com/docs/reasoning)) |
| Other APIs with `reasoning_effort` | the lowest value they accept, e.g. `{ reasoning_effort = "low" }` |

An API may reject fields it doesn't know (Groq doesn't take `chat_template_kwargs`, for example). That's why each provider has its own `extra_body`.

## Where the text goes

- **Insert mode:** at the cursor.
- **Normal mode:** after the character under the cursor, like `a`.
- **Moving the cursor while the model works:** the text still goes where the cursor was when the request arrived.
- **Buffers that can't take it** (filetype not in `filetypes`, not modifiable, or closed): the text goes to the `+` and `"` registers instead, and the notification says why.

## LAN discovery

With `mdns = true`, the plugin advertises itself as `_writetex-vscode._tcp`, the same service the app looks for from the VS Code extension. It does this through `avahi-publish-service`. On most Linux distributions:

```sh
sudo systemctl enable --now avahi-daemon
```

If Avahi isn't available, you'll see `LAN discovery unavailable` when you start the server. Either start the daemon, or set `mdns = false` and type the IP into the app. Discovery isn't needed once the app has the IP.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App shows `Unauthorized` / `401` | The app's **API Key** must equal `token` (default `writetex`). |
| `cannot listen on 0.0.0.0:50905 (EADDRINUSE)` | Something else is on that port, usually the VS Code extension or another Neovim. Stop it, or set a different `port` and change the app's endpoint to match. |
| App times out or can't connect | Check the tablet and computer are on the same network and the IP is right (`:WriteTex status`). Allow the port in your firewall, for example `sudo ufw allow 50905/tcp` or `sudo firewall-cmd --add-port=50905/tcp`. |
| `copied to clipboard, not inserted: … is not in the filetypes option` | Add the filetype to `filetypes`, or set `filetypes = false`. |
| `API error 401` / `404` from the model | Check the active provider's `endpoint` (it should end in `/v1` for most servers), `model` and key. `:checkhealth writetex` shows which key variables are unset. |
| `API error 400` after adding `extra_body` fields | The API doesn't accept one of them. Put provider-specific fields in that provider's `extra_body`. |
| `provider … needs an endpoint and a model` | Add both to that entry in `providers`. |
| Recognition is slow | Turn off reasoning (see [Turning reasoning off](#turning-reasoning-off)). |
| `LAN discovery unavailable` | See [LAN discovery](#lan-discovery). |

`:checkhealth writetex` checks `curl`, Avahi, and each provider's settings and key.

## How it works

The server speaks the OpenAI chat completions protocol, like the VS Code extension:

1. The app sends `POST /v1/chat/completions` with `Authorization: Bearer <token>` and the drawing as a base64 `image_url`.
2. The plugin notes the cursor position and builds a new request for the active provider: a system prompt with the text around the cursor (marked `<<<User Cursor Here>>>`), the image, the provider's model, and `extra_body`.
3. The model's answer streams back to the app as it arrives, so the app shows the result as usual.
4. When it's finished, the plugin cleans up the text and inserts it.

`GET /health` returns `{"ok": true}`, which is handy for checking the server from another device.

## Security

Anyone on your network who can reach the port and knows the token can send images. Each request uses your API key and types text into your editor. The default token is the app's default, `writetex`, so on shared networks:

- set your own `token` and enter the same value as the API Key in the app,
- set `host` to your LAN IP instead of `0.0.0.0`,
- only run the server while you're using it.

## Credits

- [WriteTex](https://www.writetex.com) and the [WriteTex VS Code extension](https://github.com/jacklitstar/writetex-vscode) by jacklitstar. This plugin follows the extension's protocol and adapts its OCR prompt.
- This plugin isn't affiliated with WriteTex.

## License

MIT. See [LICENSE](LICENSE).
