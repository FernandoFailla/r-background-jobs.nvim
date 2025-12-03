-- Configuration management for r-background-jobs.nvim
local M = {}

-- Default configuration
M.defaults = {
  -- Path to Rscript executable
  rscript_path = 'Rscript',
  
  -- Output directory for job logs
  output_dir = vim.fn.stdpath('data') .. '/r-jobs',
  
  -- UI settings
  ui = {
    position = 'botright',      -- Split position
    size = 15,                   -- Lines (horizontal) or columns (vertical)
    orientation = 'horizontal',  -- 'horizontal' or 'vertical'
    show_winbar = true,          -- Show window title bar
    use_colors = true,           -- Use colored status indicators
    min_width = 100,             -- Minimum table width
    max_width = 150,             -- Maximum table width
    
    -- Column widths (set to 'auto' for dynamic calculation, or specify number)
    column_widths = {
      id = 4,
      pipeline = 16,
      name = 30,        -- Default name column width (increase if names are long)
      status = 12,
      depends = 12,
      started = 10,
      duration = 10,
    },
  },
  
  -- Auto-refresh interval for jobs list (milliseconds)
  refresh_interval = 1000,
  
  -- Default keybindings (set to false to disable)
  keybindings = {
    toggle_jobs = '<leader>rj',
    start_job = '<leader>rs',
  },
}

-- Current configuration (will be merged with user config)
M.options = {}

-- Merge user configuration with defaults
function M.setup(user_config)
  user_config = user_config or {}
  
  -- Deep merge function
  local function deep_merge(default, user)
    local result = vim.deepcopy(default)
    for key, value in pairs(user) do
      if type(value) == 'table' and type(result[key]) == 'table' then
        result[key] = deep_merge(result[key], value)
      else
        result[key] = value
      end
    end
    return result
  end
  
  M.options = deep_merge(M.defaults, user_config)
  
  return M.options
end

-- Get current configuration
function M.get()
  return M.options
end

return M
