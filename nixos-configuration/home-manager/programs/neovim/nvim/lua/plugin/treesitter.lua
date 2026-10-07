return {
  'nvim-treesitter/nvim-treesitter',
  config = function ()
    require('nvim-treesitter.configs').setup({
      ensure_installed = 'all',
      auto_install = true,
      highlight = {
        enable = true,
      },
      indent = {
        enable = true,
        disable = { "html" },
      },
    })
  end
}
