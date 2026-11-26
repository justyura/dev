-- rime-ls 的辅助函数：判断补全项是否来自 rime、取前 n 个 rime 候选、开关、中文标点。
-- 开关状态放在 vim.g.rime_enabled（rime-ls 的开关是服务端全局的，不是按 buffer 的）。
local M = {}

local function client_is_rime(client_id)
  local c = client_id and vim.lsp.get_client_by_id(client_id)
  return c ~= nil and c.name == "rime_ls"
end

function M.is_rime_item(item)
  if item == nil then
    return false
  end
  if item.source_id ~= "lsp" and item.source_name ~= "LSP" then
    return false
  end
  return client_is_rime(item.client_id)
end

local function insert_text(item)
  return (item.textEdit and item.textEdit.newText) or item.insertText or item.label or ""
end

-- 候选里有非 ASCII 字符（中文、表情等）才算「中文候选」；英文词库给出的候选不会被空格/分号/数字自动上屏
function M.is_cjk_item(item)
  return insert_text(item):find("[\128-\255]") ~= nil
end

-- 返回补全列表里前 n 个 rime 候选的下标。只在补全菜单可见时有效（按 ⌃e 关掉菜单后空格就是空格）。
-- 引擎把英文候选排在第一位（neovim → Neovim、code → code）就说明它认为这是英文，整段不自动上屏；
-- 前 n 个候选里出现英文的也不自动上屏。
function M.first_rime_items(n, items)
  local result = {}
  if items == nil then
    local ok, blink = pcall(require, "blink.cmp")
    if not ok or not blink.is_visible() then
      return result
    end
    items = require("blink.cmp.completion.list").items
  end
  if items == nil then
    return result
  end
  for i, item in ipairs(items) do
    if M.is_rime_item(item) then
      if not M.is_cjk_item(item) then
        return {}
      end
      result[#result + 1] = i
      if #result == n then
        break
      end
    end
  end
  return result
end

-- 给 blink 的 transform_items 用：输入里带大写字母（Neovim、API、I'm）明显是英文，不要给 rime 候选，
-- 否则候选会把整个单词替换掉。
function M.filter_items(ctx, items)
  local line = ctx and ctx.line
  if not line then
    return items
  end
  local out = {}
  for _, item in ipairs(items) do
    local keep = true
    if M.is_rime_item(item) and item.textEdit and item.textEdit.range then
      local r = item.textEdit.range
      local ok, sb, eb = pcall(function()
        return vim.str_byteindex(line, "utf-16", r.start.character), vim.str_byteindex(line, "utf-16", r["end"].character)
      end)
      if ok and sb and eb and line:sub(sb + 1, eb):find("%u") then
        keep = false
      end
    end
    if keep then
      out[#out + 1] = item
    end
  end
  return out
end

function M.enabled()
  return vim.g.rime_enabled == true
end

function M.attached(bufnr)
  return #vim.lsp.get_clients({ bufnr = bufnr or 0, name = "rime_ls" }) > 0
end

function M.toggle()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = "rime_ls" })
  if #clients == 0 then
    vim.notify("rime-ls 只在 markdown 里启用", vim.log.levels.WARN, { title = "rime-ls" })
    return
  end
  clients[1]:request("workspace/executeCommand", { command = "rime-ls.toggle-rime" }, function(err, result)
    if err then
      vim.notify("rime-ls 切换失败: " .. tostring(err.message or err), vim.log.levels.ERROR, { title = "rime-ls" })
      return
    end
    vim.g.rime_enabled = result == true
    vim.notify(vim.g.rime_enabled and "中文：开" or "中文：关", vim.log.levels.INFO, { title = "rime-ls" })
  end, 0)
end

-- 接受第 idx 个 rime 候选（如果有），然后把 keys 送进去
local function accept_then_feed(keys)
  local blink = require("blink.cmp")
  local idx = M.first_rime_items(1)
  if blink.is_visible() and #idx == 1 then
    blink.accept({ index = idx[1] })
    vim.schedule(function()
      vim.api.nvim_feedkeys(keys, "n", false)
    end)
  else
    vim.api.nvim_feedkeys(keys, "n", false)
  end
end

-- 中文标点：rime 开着时 , . ? ! : \ 直接出中文标点；正在打拼音时先上屏首选再出标点
local punct = {
  [","] = "，",
  ["."] = "。",
  ["?"] = "？",
  ["!"] = "！",
  [":"] = "：",
  ["\\"] = "、",
}

local function setup_buffer(bufnr)
  for key, zh in pairs(punct) do
    vim.keymap.set("i", key, function()
      if M.enabled() then
        accept_then_feed(zh)
      else
        vim.api.nvim_feedkeys(key, "n", false)
      end
    end, { buffer = bufnr, desc = "rime 中文标点 " .. zh })
  end
end

-- 用数字键选词后直接上屏：rime-ls 处理完数字只剩一个候选时自动接受
local function setup_number_commit()
  local ok, list = pcall(require, "blink.cmp.completion.list")
  if not ok then
    return
  end
  list.show_emitter:on(function(event)
    if not M.enabled() then
      return
    end
    local col = vim.fn.col(".") - 1
    if event.context.line:sub(col, col):match("%d") == nil then
      return
    end
    local idx = M.first_rime_items(2, event.items)
    if #idx ~= 1 then
      return
    end
    -- 注意："mp3" 这类字母加数字在 rime 开着时会被当成选词，写这类内容先按 ⌃g 关掉或 ⌃e 关菜单
    require("blink.cmp").accept({ index = idx[1] })
  end)
end

local seen_clients = {}

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("rime_ls_attach", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= "rime_ls" then
        return
      end
      if not seen_clients[client.id] then
        seen_clients[client.id] = true
        vim.g.rime_enabled = true -- init_options.enabled = true
      end
      setup_buffer(args.buf)
    end,
  })

  -- rime-ls 的中英开关：⌃g（插入模式的 ⌃g 在 blink 的 keymap 里处理，这样和补全菜单不打架）
  vim.keymap.set("n", "<C-g>", M.toggle, { desc = "rime-ls 中英切换" })

  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == "blink.cmp" then
        setup_number_commit()
      end
    end,
  })
  -- blink 可能已经加载
  if package.loaded["blink.cmp"] then
    setup_number_commit()
  end
end

return M
