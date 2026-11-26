-- 主题固定为 Tokyo Night Storm（tmux、sketchybar 用同一套颜色，见 scripts/lib/themes）。
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("tokyonight-storm")
  end,
}
