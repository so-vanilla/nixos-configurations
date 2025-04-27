local opts = {
  shiftwidth = 2,
  tabstop = 2,
  expandtab = true,
  smartindent = true,
  autoindent = true,
  swapfile = false,
}

for k, v in pairs(opts) do
  vim.opt[k] = v
end
