-- Auto-load file for r-background-jobs.nvim
-- This file is automatically sourced by Neovim when the plugin is loaded

-- Prevent loading twice
if vim.g.loaded_r_background_jobs then
  return
end
vim.g.loaded_r_background_jobs = 1

-- The actual plugin code is in lua/r-background-jobs/init.lua
-- Users will call require('r-background-jobs').setup() to initialize
