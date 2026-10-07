# Use the checked-in theme without writing universal variables.
status is-interactive; or return
set -l theme_file (path dirname (status filename))/../themes/catppuccin-latte.theme
while read --line line
    if string match --quiet --regex '^fish_(color|pager_color)_[a-z_]+ ' -- $line
        set -l parts (string split --no-empty ' ' -- $line)
        set --global -- $parts[1] $parts[2..-1]
    end
end < "$theme_file"
