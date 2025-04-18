require('lazy').setup({
    spec = {
        require("plugin.nvim-lspconfig"),
        require("plugin.nvim-cmp"),
        require("plugin.telescope-nvim"),
        require("plugin.hop-nvim"),
        require("plugin.catppuccin"),
    },
    checker = { enabled = true },
})
