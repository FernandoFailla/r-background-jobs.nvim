-- User commands for r-background-jobs.nvim
local executor = require('r-background-jobs.executor')
local manager = require('r-background-jobs.manager')
local telescope = require('r-background-jobs.telescope')
local ui = require('r-background-jobs.ui')
local utils = require('r-background-jobs.utils')

local M = {}

-- Command: Start a new job
function M.start_job(args)
  local script_path = args.args
  
  -- If no argument provided, use current buffer
  if not script_path or script_path == '' then
    script_path = vim.api.nvim_buf_get_name(0)
    
    if script_path == '' then
      vim.notify('No file specified and current buffer has no name', vim.log.levels.ERROR)
      return
    end
  end
  
  -- Expand path
  script_path = vim.fn.expand(script_path)
  
  -- Validate it's an R file
  local valid, err = utils.validate_script_path(script_path)
  if not valid then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  
  -- Start the job
  local job, start_err = executor.start_job(script_path)
  if not job then
    vim.notify('Failed to start job: ' .. (start_err or 'unknown error'), vim.log.levels.ERROR)
  end
end

-- Command: Toggle jobs list
function M.toggle_list()
  ui.toggle()
end

-- Command: Cancel a job
function M.cancel_job(args)
  local job_id = tonumber(args.args)
  
  if job_id then
    -- Job ID provided, cancel directly
    local success, err = executor.cancel_job(job_id)
    if success then
      vim.notify('Job ' .. job_id .. ' cancelled', vim.log.levels.INFO)
    else
      vim.notify('Failed to cancel job: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end
  else
    -- No ID provided, use picker
    telescope.pick_and_cancel()
  end
end

-- Command: View job output
function M.view_output(args)
  local job_id = tonumber(args.args)
  
  if job_id then
    -- Job ID provided, open directly
    local job = manager.get_job(job_id)
    if not job then
      vim.notify('Job not found: ' .. job_id, vim.log.levels.ERROR)
      return
    end
    
    if not job.output_file or not utils.file_exists(job.output_file) then
      vim.notify('Output file not found for job ' .. job_id, vim.log.levels.WARN)
      return
    end
    
    vim.cmd('rightbelow split ' .. vim.fn.fnameescape(job.output_file))
    vim.api.nvim_buf_set_option(0, 'filetype', 'r')
    vim.api.nvim_buf_set_option(0, 'modifiable', false)
    
    if job:is_running() then
      vim.cmd('normal! G')
    end
  else
    -- No ID provided, use picker
    telescope.pick_and_view_output()
  end
end

-- Command: Clear finished jobs
function M.clear_jobs()
  -- Ask for confirmation
  vim.ui.input({
    prompt = 'Clear all finished jobs? (y/n): ',
  }, function(input)
    if input and input:lower() == 'y' then
      local count = manager.clear_finished()
      vim.notify('Cleared ' .. count .. ' finished job(s)', vim.log.levels.INFO)
      
      -- Refresh UI if open
      if ui.state.is_open then
        ui.refresh()
      end
    end
  end)
end

-- Command: Show job info
function M.show_info(args)
  local job_id = tonumber(args.args)
  
  if job_id then
    -- Job ID provided, show directly
    local job = manager.get_job(job_id)
    if not job then
      vim.notify('Job not found: ' .. job_id, vim.log.levels.ERROR)
      return
    end
    
    local info = job:get_info()
    local lines = {
      'Job Information:',
      '  ID: ' .. info.id,
      '  Name: ' .. info.name,
      '  Script: ' .. info.script_path,
      '  Status: ' .. info.status,
      '  Started: ' .. info.start_time,
      '  Duration: ' .. info.duration,
      '  Output: ' .. (info.output_file or 'N/A'),
      '  PID: ' .. (info.pid or 'N/A'),
    }
    
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  else
    -- No ID provided, use picker
    telescope.pick_and_show_info()
  end
end

-- Get job IDs for completion
local function get_job_ids()
  local jobs = manager.get_jobs()
  local ids = {}
  for _, job in ipairs(jobs) do
    table.insert(ids, tostring(job.id))
  end
  return ids
end

-- Register all commands
function M.register_commands()
  -- RJobStart [file]
  vim.api.nvim_create_user_command('RJobStart', M.start_job, {
    nargs = '?',
    complete = 'file',
    desc = 'Start R script as background job',
  })
  
  -- RJobsList
  vim.api.nvim_create_user_command('RJobsList', M.toggle_list, {
    nargs = 0,
    desc = 'Toggle R background jobs list',
  })
  
  -- RJobCancel [id]
  vim.api.nvim_create_user_command('RJobCancel', M.cancel_job, {
    nargs = '?',
    complete = function()
      return get_job_ids()
    end,
    desc = 'Cancel a running job',
  })
  
  -- RJobOutput [id]
  vim.api.nvim_create_user_command('RJobOutput', M.view_output, {
    nargs = '?',
    complete = function()
      return get_job_ids()
    end,
    desc = 'View job output',
  })
  
  -- RJobClear
  vim.api.nvim_create_user_command('RJobClear', M.clear_jobs, {
    nargs = 0,
    desc = 'Clear finished jobs',
  })
  
  -- RJobInfo [id]
  vim.api.nvim_create_user_command('RJobInfo', M.show_info, {
    nargs = '?',
    complete = function()
      return get_job_ids()
    end,
    desc = 'Show job information',
  })
end

return M
