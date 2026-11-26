-- rime-ls：把 Rime（和鼠须管同一个引擎、同一套小鹤双拼 + rime-ice 词库）当作 LSP，
-- 只在 markdown 里启用，拼音候选出现在 blink.cmp 的补全菜单里。
-- 用户目录是 ~/.local/share/rime-ls（从 ~/Library/Rime 同步的副本，不和鼠须管共用词库数据库）。
return {
  cmd = { vim.fn.expand("~/.local/bin/rime_ls") },
  filetypes = { "markdown" },
  -- 二进制动态链接 librime，直接用鼠须管自带的 librime 1.16（含 lua/octagram/predict 插件）
  cmd_env = { DYLD_LIBRARY_PATH = "/Library/Input Methods/Squirrel.app/Contents/Frameworks" },
  init_options = {
    enabled = true,
    shared_data_dir = "/Library/Input Methods/Squirrel.app/Contents/SharedSupport",
    user_data_dir = vim.fn.expand("~/.local/share/rime-ls"),
    log_dir = vim.fn.expand("~/.local/share/rime-ls/log"),
    trigger_characters = {},
    schema_trigger_character = "&",
    paging_characters = { "-", "=" }, -- 逗号句号已经映射成中文标点，不拿来翻页
    always_incomplete = true, -- 双拼必须：每次按键都重建候选，而不是在旧列表里过滤
    long_filter_text = true, -- blink.cmp 过滤严格，需要长 filter_text
    show_order_in_label = true, -- 候选前面带序号
    preselect_first = false,
  },
}
