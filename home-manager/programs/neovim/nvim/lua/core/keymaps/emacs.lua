local n = 'n'
local i = 'i'
local c = 'c'
local ic = { i, c }
local default_opts = {
  noremap = true,
  silent = true,
}

local keymaps = {
  { ic, '<C-f>', '<Right>',   default_opts },
  { ic, '<C-b>', '<Left>',    default_opts },
  { ic, '<C-p>', '<Up>',      default_opts },
  { ic, '<C-n>', '<Down>',    default_opts },
  { ic, '<C-a>', '<Home>',    default_opts },
  { ic, '<C-e>', '<End>',     default_opts },
  { ic, '<C-d>', '<Del>',     default_opts },
  { ic, '<M-f>', '<S-Right>', default_opts },
  { ic, '<M-b>', '<S-Left>',  default_opts },
  { n, '<C-x><C-s>', '<CMD>w<CR>', default_opts },
  { n, '<C-e>', '$', default_opts },
  { n, '<C-a>', '^', default_opts },
  { i, '<C-k>', '<C-o>D', default_opts },
}

return keymaps
