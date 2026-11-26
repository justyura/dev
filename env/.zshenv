# 密钥放在 ~/.zsh_secrets（不进仓库，权限 600）；所有 zsh（含脚本）都会读到。
[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets
# Blink Pro: a mosh-server whose client has been gone this long exits (tools/mosh-keepawake.sh keeps the Mac awake only while one runs)
export MOSH_SERVER_NETWORK_TMOUT=21600
# Blink Pro: on SIGUSR1 a mosh-server exits only if its client has been silent this long; tools/mosh-keepawake.sh signals superseded servers to clean them up
export MOSH_SERVER_SIGNAL_TMOUT=120
