return {
    'smoka7/hop.nvim',
    config = function()
        require('hop').setup({})
    end,
    keys = {
      { '<C-/>', '<cmd>HopWord<CR>' },
      { '<M-/>', '<cmd>HopLine<CR>' },
    };
}
