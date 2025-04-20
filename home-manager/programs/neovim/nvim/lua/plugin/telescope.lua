return {
    "nvim-telescope/telescope.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    cmd = 'Telescope',
    keys = {
      { '<M-x>', function () require('telescope.builtin').commands() end },
      { '<C-s>', function () require('telescope.builtin').current_buffer_fuzzy_find() end },
      { '<C-x>b', function () require('telescope.builtin').buffers() end },
    },
}
