-- Telescope extension: :Telescope vallow
--   require("telescope").load_extension("vallow")
return require("telescope").register_extension({
  exports = {
    vallow = function(opts)
      require("vallow.picker").open_telescope(opts)
    end,
  },
})
