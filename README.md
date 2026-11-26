# dev

整套开发环境：配置、装软件的脚本、自己写的小工具。
做法照 [ThePrimeagen/dev](https://github.com/ThePrimeagen/dev)，改成同时支持 macOS 和 Arch Linux。

## 结构

```
env/.config/<程序>/   配置源头：nvim tmux tmux-sessionizer scripts（Mac：karabiner sketchybar skhd yabai）
env/.local/bin/       自己的命令：tmux-sessionizer
env/.zshrc .zshenv .zprofile
runs/                 一个装软件的脚本一件事：brew（Mac）pacman（Arch）things（Mac）
dev-env               把 env/ 复制到家目录
run                   依次执行 runs/
```

## 用法

```bash
./dev-env --dry   # 先看会改哪些地方
./dev-env         # 应用配置
./run --dry       # 看会装什么
./run brew        # 只跑名字里带 brew 的脚本
```

## 规矩

- **源头只在这里。** `~/.config` 只是复制出来的结果，程序会往里写东西，不要在那里改。
  改配置：在这里改 → `./dev-env`。sessionizer 里直接能选到 `nvim`、`tmux` 这些目录。
- **dev-env 只替换它管的目录**，`~/.config` 里其他程序自己的东西不碰。
- **密钥不进仓库。** zsh 的密钥在 `~/.zsh_secrets`（权限 600），由 `.zshenv` 读取。
  各程序自己的 token 留在 `~/.config/<程序>/` 原位（这些目录不归 dev-env 管）。
- **同步到别的机器**：这里 `git push`，那边 `git pull && ./dev-env`。
- **两种模式**：`desktop` 管全部（这台 Mac）；`server` 只管 nvim、tmux、sessionizer 和 `~/.local/bin`，不碰 zsh 和桌面（arch、mini）。
  每台机器在 `~/.config/dev-env.local` 写 `DEV_PROFILE=server`；不写时 macOS 默认 desktop，Linux 默认 server。

## 新机器

```bash
git clone <本仓库> ~/personal/dev && cd ~/personal/dev
./run && ./dev-env
# 再把 ~/.zsh_secrets 从旧机器拷过来
```
