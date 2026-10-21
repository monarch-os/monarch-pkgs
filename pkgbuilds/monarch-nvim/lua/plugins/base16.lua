return {
  { "RRethy/base16-nvim", lazy = true },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local ok, matugen = pcall(require, "matugen")
        if ok then
          matugen.setup()
        else
          require("tokyonight").load()
        end
      end,
    },
  },
}
