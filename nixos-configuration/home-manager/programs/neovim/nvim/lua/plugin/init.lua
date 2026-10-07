require('lazy').setup({
  spec = {
    require('plugin.lspconfig'),
    require('plugin.treesitter'),
    require('plugin.cmp'),
    require('plugin.telescope'),
    require('plugin.autopairs'),
    require('plugin.ts-autotag'),
    require('plugin.surround'),
    require('plugin.hop'),
    require('plugin.toggleterm'),
    require('plugin.orgmode'),
    require('plugin.neogit'),
    require('plugin.lualine'),
    require('plugin.catppuccin'),
  },
  checker = { enabled = false, },
})
