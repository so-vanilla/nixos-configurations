local l = require('utils.list')

local maps = l.concat(
    require('core.keymaps.emacs'),
    require('core.keymaps.user')
)

for _, map in ipairs(maps) do
    vim.keymap.set(map[1], map[2], map[3], map[4])
end
