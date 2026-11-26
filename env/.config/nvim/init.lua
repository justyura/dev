if vim.fn.has("nvim-0.12") == 0 then
  vim.api.nvim_echo({ { "This configuration requires Neovim 0.12 or newer.", "ErrorMsg" } }, true, {})
  return
end

vim.diagnostic.config({ virtual_text = true })

require("config.lazy")
require("config.keymaps")
require("config.options")
require("config.rime").setup()

vim.lsp.enable("lua_ls")
vim.lsp.enable("gopls")
vim.lsp.enable("html")
-- rime-ls：markdown 里的中文输入（装好二进制后自动启用）
-- if vim.fn.executable(vim.fn.expand("~/.local/bin/rime_ls")) == 1 then
--   vim.lsp.enable("rime_ls")
-- end
