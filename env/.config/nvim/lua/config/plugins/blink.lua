return {
  "saghen/blink.cmp",
  dependencies = { "rafamadriz/friendly-snippets" },
  version = "1.*",

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    keymap = {
      preset = "super-tab",

      -- rime-ls（markdown 中文输入）：空格上屏首选，分号次选，和鼠须管里的习惯一致。
      -- 只对「中文候选」生效：英文候选、菜单已关闭（⌃e）、rime 关着时全部回落到原本行为。
      -- 第三个及以后的候选用数字键。单引号不做选词键，英文的 don't 会撞上。
      ["<space>"] = {
        function(cmp)
          local rime = require("config.rime")
          if not rime.enabled() then
            return false
          end
          local idx = rime.first_rime_items(1)
          if #idx ~= 1 then
            return false
          end
          return cmp.accept({ index = idx[1] })
        end,
        "fallback",
      },
      [";"] = {
        function(cmp)
          local rime = require("config.rime")
          if not rime.enabled() then
            return false
          end
          local idx = rime.first_rime_items(2)
          if #idx ~= 2 then
            return false
          end
          return cmp.accept({ index = idx[2] })
        end,
        "fallback",
      },
      -- ⌃g：rime-ls 附加在这个 buffer 时切中英，其他 buffer 里保持 ⌃g 原本行为
      ["<C-g>"] = {
        function()
          local rime = require("config.rime")
          if not rime.attached(0) then
            return false
          end
          rime.toggle()
          return true
        end,
        "fallback",
      },
    },
    signature = { enabled = true },

    appearance = {
      -- “Nerd Font Mono”使用“mono”（默认值），“Nerd Font”使用“normal”
      -- 调整间距以确保图标对齐
      nerd_font_variant = "mono",
    },

    completion = {
      documentation = { auto_show = true },
      accept = {
        auto_brackets = { enabled = true },
      },
    },

    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      per_filetype = {
        -- markdown 里只要 snippets 和 lsp（lsp 就是 rime-ls 的中文候选）
        markdown = { "lsp", "snippets" },
      },
      providers = {
        lsp = {
          -- blink 默认会把 LSP 的 Text 类型补全过滤掉，rime-ls 的候选正是 Text 类型，所以自己接管：
          -- 只做默认的 snippet 降权，其余原样保留
          transform_items = function(ctx, items)
            -- rime-ls：输入里带大写字母的单词是英文，不给中文候选
            items = require("config.rime").filter_items(ctx, items)
            local snippet_kind = require("blink.cmp.types").CompletionItemKind.Snippet
            for _, item in ipairs(items) do
              if item.kind == snippet_kind then
                item.score_offset = item.score_offset - 3
              end
            end
            return items
          end,
        },
      },
    },

    fuzzy = { implementation = "prefer_rust_with_warning" },

    enabled = function()
      return not vim.tbl_contains({ "text" }, vim.bo.filetype)
    end,
  },
  opts_extend = { "sources.default" },
}
