if vim.v.vim_did_enter == 0 then
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("VallowStartup", {}),
    once = true,
    callback = function()
      require("vallow").setup()
    end,
  })
end

vim.api.nvim_create_user_command("Vallow", function()
  require("vallow").toggle()
end, {})

vim.api.nvim_create_user_command("VallowRefresh", function()
  require("vallow").refresh()
end, {})

vim.api.nvim_create_user_command("VallowSearch", function()
  local results = require("vallow.panel").state.results
  if not results then
    vim.notify("vallow: run :Vallow first", vim.log.levels.WARN)
    return
  end
  require("vallow.picker").open(results)
end, { desc = "Search vallow findings with telescope/fzf-lua" })
