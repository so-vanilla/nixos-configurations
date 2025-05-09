return {
  "neovim/nvim-lspconfig",
  lazy = false,
  keys = {
    { '<M-n>', function() vim.diagnostic.goto_next() end },
    { '<M-p>', function() vim.diagnostic.goto_prev() end },
  },
  config = function ()
    vim.lsp.enable('cssls')
    vim.lsp.enable('html')
    vim.lsp.config('lua_ls', {
      on_init = function(client)
        if client.workspace_folders then
          local path = client.workspace_folders[1].name
          if path ~= vim.fn.stdpath('config') and (vim.uv.fs_stat(path..'/.luarc.json') or vim.uv.fs_stat(path..'/.luarc.jsonc')) then
            return
          end
        end

        client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
          runtime = {
            version = 'LuaJIT'
          },
          workspace = {
            checkThirdParty = false,
            library = {
              vim.env.VIMRUNTIME
            }
          }
        })
      end,
      settings = {
        Lua = {}
      }
    })
    vim.lsp.enable('nixd')
    vim.lsp.enable('pyright')

    vim.diagnostic.config({
      signs = false,
    })
  end
}
