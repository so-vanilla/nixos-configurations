# Shared shell settings. Native commands are supplied by the host package manager.
set -gx EDITOR "zed --wait"
set -gx VISUAL "$EDITOR"

status is-interactive; or return
set -g fish_greeting
if type -q python3
    set -gx PYTHON_HOME (python3 -c 'import sys; print(sys.prefix, end="")')
end
if type -q gh
    set -l github_token (gh auth token 2>/dev/null)
    if test -n "$github_token"
        set -gx GITHUB_PERSONAL_ACCESS_TOKEN "$github_token"
    end
end
set -l config_dir (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)
for name in general links
    if test -f "$config_dir/fish/$name.fish"
        source "$config_dir/fish/$name.fish"
    end
end
for directory in $HOME/.local/bin /opt/homebrew/bin $HOME/.rd/bin
    if test -d $directory
        fish_add_path --path --prepend $directory
    end
end
abbr --add ls eza
abbr --add cat bat
abbr --add grep rg
abbr --add rm trash-put
alias h cd
alias q exit
alias e zed
alias ec 'zed --wait'
alias kills 'killall slack .Discord-wrapped'
