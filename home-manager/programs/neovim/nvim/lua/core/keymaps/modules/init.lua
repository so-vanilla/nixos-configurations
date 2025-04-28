local M = {}

function M.lazy_0 ()
  line = vim.fn.getline('.')
  col = vim.fn.col('.')
  left = line:sub(1, col-1)
  if left:match('^%s+$') ~= nil then
    vim.api.nvim_feedkeys('0', 'n', true)
  else
    vim.api.nvim_feedkeys('^', 'n', true)
  end
end

return M
