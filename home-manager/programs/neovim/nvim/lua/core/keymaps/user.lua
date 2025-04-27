local n = 'n'
local i = 'i'
local v = 'v'
local c = 'c'
local nv = { 'n', 'v' }
local ic = { 'i', 'c' }
local all_modes = { 'n', 'i', 'v', 'c' }

local default_opts = {
  noremap = true,
  silent = true,
}

local keymaps = {
  { c, '<C-[>', '<C-c>', default_opts },
  { c, '<C-g>', '<C-c>', default_opts },
  { v, '=', 'gq', default_opts },
}

return keymaps
