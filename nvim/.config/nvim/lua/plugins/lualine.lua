return {
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        component_separators = { left = "\u{e0b9}", right = "\u{e0bb}" },
        section_separators = { left = "\u{e0b8}", right = "\u{e0ba}" },
      },
      sections = {
        lualine_b = {
          { "branch", icon = "" },
        },
      },
    },
  },
}
