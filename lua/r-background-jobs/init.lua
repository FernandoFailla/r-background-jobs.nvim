-- Main entry point for r-background-jobs.nvim
local M = {}

-- Plugin modules
local config = require('r-background-jobs.config')
local commands = require('r-background-jobs.commands')
local executor = require('r-background-jobs.executor')
local manager = require('r-background-jobs.manager')
local ui = require('r-background-jobs.ui')
local utils = require('r-background-jobs.utils')

-- Plugin state
M.initialized = false

-- Setup function (called by user)
-- @param opts table User configuration options
function M.setup(opts)
  if M.initialized then
    vim.notify('r-background-jobs.nvim is already initialized', vim.log.levels.WARN)
    return
  end
  
  -- Setup configuration
  config.setup(opts or {})
  local cfg = config.get()
  
  -- Ensure output directory exists
  if not utils.ensure_dir(cfg.output_dir) then
    vim.notify(
      'Failed to create output directory: ' .. cfg.output_dir,
      vim.log.levels.ERROR
    )
    return
  end
  
  -- Register commands
  commands.register_commands()
  
  -- Setup default keybindings if enabled
  if cfg.keybindings then
    M.setup_keybindings(cfg.keybindings)
  end
  
  M.initialized = true
  
  -- Show welcome message (optional, can be removed)
  -- vim.notify('r-background-jobs.nvim initialized', vim.log.levels.INFO)
end

-- Setup default keybindings
-- @param keybindings table Keybinding configuration
function M.setup_keybindings(keybindings)
  if not keybindings then
    return
  end
  
  if keybindings.toggle_jobs then
    vim.keymap.set('n', keybindings.toggle_jobs, function()
      ui.toggle()
    end, { desc = 'Toggle R background jobs list' })
  end
  
  if keybindings.start_job then
    vim.keymap.set('n', keybindings.start_job, function()
      commands.start_job({ args = '' })
    end, { desc = 'Start R job from current file' })
  end
end

-- Public API

-- Start a job from script path
-- @param script_path string Path to R script
-- @return table|nil Job object or nil on error
function M.start_job(script_path)
  if not M.initialized then
    vim.notify('Plugin not initialized. Call setup() first.', vim.log.levels.ERROR)
    return nil
  end
  
  local job, err = executor.start_job(script_path)
  return job
end

-- Cancel a job by ID
-- @param job_id number Job ID
-- @return boolean Success
function M.cancel_job(job_id)
  if not M.initialized then
    vim.notify('Plugin not initialized. Call setup() first.', vim.log.levels.ERROR)
    return false
  end
  
  return executor.cancel_job(job_id)
end

-- Get all jobs
-- @return table Array of jobs
function M.get_jobs()
  return manager.get_jobs()
end

-- Get job by ID
-- @param job_id number Job ID
-- @return table|nil Job object or nil if not found
function M.get_job(job_id)
  return manager.get_job(job_id)
end

-- Toggle UI
function M.toggle_ui()
  if not M.initialized then
    vim.notify('Plugin not initialized. Call setup() first.', vim.log.levels.ERROR)
    return
  end
  
  ui.toggle()
end

-- Open UI
function M.open_ui()
  if not M.initialized then
    vim.notify('Plugin not initialized. Call setup() first.', vim.log.levels.ERROR)
    return
  end
  
  ui.open()
end

-- Close UI
function M.close_ui()
  ui.close()
end

-- Clear finished jobs
-- @return number Number of jobs cleared
function M.clear_finished()
  return manager.clear_finished()
end

return M
