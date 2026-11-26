vim.keymap.set("n", "df", "yyGpo", { buffer = true })
vim.keymap.set("n", "da", "/# Answer<CR>O- ", { buffer = true })

-- v 前缀快捷键
vim.keymap.set("i", "vj", "<Esc>o<space><space><space><C-k>-v<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("n", "vj", "<Esc>o<space><space><space><C-k>-v<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vk", "<Esc>o<space><space><space><C-k>!-<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vl", "<C-k>-><space>", { buffer = 0 })
vim.keymap.set("i", "vh", "<C-k><-", { buffer = 0 })
vim.keymap.set("i", "v*", "<C-k>2*<space>", { buffer = 0 })
vim.keymap.set("i", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`ma", { buffer = 0 })
vim.keymap.set("v", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`m", { buffer = 0 })
vim.keymap.set("n", "<leader>d", "I~~<Esc>A~~<Esc>", { buffer = 0 })

-- 渲染开关：写的时候关掉看原始语法，读的时候打开
vim.keymap.set("n", "<leader>m", "<Cmd>RenderMarkdown toggle<CR>", { buffer = 0, desc = "Toggle markdown render" })

-- list（墨水屏白板）：按白板渲染效果打印到打印机 / 在 Mac 上预览
-- <leader>p 或 :ListPrint 保存并打印当前文件（先确认一次，回车即打印）；:ListPreview 预览不打印
local function list_run(args, done_msg)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("list: 先保存这个文件", vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then vim.cmd("silent write") end
  table.insert(args, file)
  vim.system(vim.list_extend({ vim.fn.expand("~/bin/list") }, args), { text = true }, function(r)
    vim.schedule(function()
      local out = vim.trim((r.stdout or "") .. (r.stderr or ""))
      if r.code == 0 then
        vim.notify(out ~= "" and out or done_msg or "list: ok")
      else
        vim.notify(out ~= "" and out or "list failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

if vim.fn.exists(":ListPrint") ~= 2 then
  vim.api.nvim_create_user_command("ListPrint", function() list_run({ "--p" }) end,
    { desc = "Print the rendered list on paper (list --p)" })
  vim.api.nvim_create_user_command("ListPreview", function()
    list_run({ "-p" }, "list: 预览已打开")
  end, { desc = "Preview the rendered pages on the Mac (list -p)" })
end

vim.keymap.set("n", "<leader>p", function()
  local name = vim.fn.expand("%:t:r")
  if vim.fn.confirm("打印 " .. name .. "？", "&Yes\n&No", 1) == 1 then
    vim.cmd("ListPrint")
  end
end, { buffer = 0, desc = "Print this list on paper (list --p)" })
