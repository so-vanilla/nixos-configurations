return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'sindrets/diffview.nvim',
  },
  commands = { 'Neogit' },
  keys = {
    { '<C-x>g', '<CMD>Neogit<CR>' },
  },
  opts = {},
}

