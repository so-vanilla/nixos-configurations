return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
  },
  cmd = 'Telescope',
  keys = {
    { '<M-x>', function () require('telescope.builtin').commands() end },
    { '<C-s>', function () require('telescope.builtin').current_buffer_fuzzy_find() end },
    { '<C-x>b', function () require('telescope.builtin').buffers() end },
    { '<C-x><C-f>', function () require('telescope').extensions.file_browser.file_browser() end },
  },
}
