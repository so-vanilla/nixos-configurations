local n = 'n'
local i = 'i'
local nv = { 'n', 'v' }
local ic = { 'i', 'c' }
local all_modes = { 'n', 'i', 'v', 'c' }

local default_opts = {
    noremap = true,
    silent = true,
}

local keymaps = {
    { nv, 'w', '<Nop>', default_opts },
    { nv, 'e', '<Nop>', default_opts },
    { nv, 'b', '<Nop>', default_opts },
}

return keymaps
