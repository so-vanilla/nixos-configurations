return {
    'smoka7/hop.nvim',
    config = function()
        require('hop').setup({})
    end,
    keys = {
      { '<C-/>', '<cmd>HopWord<CR>', { 'n', 'v' }},
      { '<M-/>', '<cmd>HopLine<CR>', { 'n', 'v' }},
    };
}
