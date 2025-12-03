-- User commands for r-background-jobs.nvim
local executor = require('r-background-jobs.executor')
local manager = require('r-background-jobs.manager')
local telescope = require('r-background-jobs.telescope')
local ui = require('r-background-jobs.ui')
local utils = require('r-background-jobs.utils')

local M = {}

-- Parse arguments for RJobStart command
-- Supports: RJobStart script.R --after=1,2,3 --pipeline="name"
local function parse_start_args(arg_string)
  local opts = {
    script_path = nil,
    depends_on = nil,
    pipeline_name = nil,
  }
  
  if not arg_string or arg_string == '' then
    return opts
  end
  
  -- Split by spaces, but preserve quoted strings
  local parts = {}
  for part in arg_string:gmatch('%S+') do
    table.insert(parts, part)
  end
  
  -- First non-flag argument is the script path
  local script_idx = nil
  for i, part in ipairs(parts) do
    if not part:match('^%-%-') then
      script_idx = i
      opts.script_path = part
      break
    end
  end
  
  -- Parse flags
  for i, part in ipairs(parts) do
    if i ~= script_idx then
      -- Parse --after=1,2,3
      local after_match = part:match('^%-%-after=(.+)$')
      if after_match then
        opts.depends_on = {}
        for id_str in after_match:gmatch('[^,]+') do
          local id = tonumber(id_str)
          if id then
            table.insert(opts.depends_on, id)
          else
            vim.notify('Invalid job ID in --after: ' .. id_str, vim.log.levels.WARN)
          end
        end
      end
      
      -- Parse --pipeline="name" or --pipeline=name
      local pipeline_match = part:match('^%-%-pipeline=(.+)$')
      if pipeline_match then
        -- Remove quotes if present
        opts.pipeline_name = pipeline_match:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1')
      end
    end
  end
  
  return opts
end

-- Command: Start a new job
function M.start_job(args)
  local parsed = parse_start_args(args.args)
  local script_path = parsed.script_path
  
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
  
  -- Build options for executor
  local opts = {}
  if parsed.depends_on and #parsed.depends_on > 0 then
    opts.depends_on = parsed.depends_on
  end
  if parsed.pipeline_name then
    opts.pipeline_name = parsed.pipeline_name
  end
  
  -- Start the job
  local job, start_err = executor.start_job(script_path, opts)
  if not job then
    vim.notify('Failed to start job: ' .. (start_err or 'unknown error'), vim.log.levels.ERROR)
  else
    if opts.depends_on then
      vim.notify(
        string.format('Job %d created (waiting for: %s)', job.id, table.concat(opts.depends_on, ', ')),
        vim.log.levels.INFO
      )
    end
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
    
    -- Add dependency info if available
    if job.depends_on and #job.depends_on > 0 then
      table.insert(lines, '  Depends on: ' .. table.concat(job.depends_on, ', '))
    end
    if job.dependents and #job.dependents > 0 then
      table.insert(lines, '  Dependents: ' .. table.concat(job.dependents, ', '))
    end
    if job.pipeline_name then
      table.insert(lines, '  Pipeline: ' .. job.pipeline_name)
    end
    if job.skip_reason then
      table.insert(lines, '  Skip reason: ' .. job.skip_reason)
    end
    
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  else
    -- No ID provided, use picker
    telescope.pick_and_show_info()
  end
end

-- Command: Add dependency to a job
function M.add_dependency(args)
  -- Parse args: job_id depends_on_id
  local parts = vim.split(args.args or '', '%s+')
  local job_id = tonumber(parts[1])
  local depends_on_id = tonumber(parts[2])
  
  if not job_id or not depends_on_id then
    vim.notify('Usage: RJobAddDependency <job_id> <depends_on_id>', vim.log.levels.ERROR)
    return
  end
  
  local job = manager.get_job(job_id)
  if not job then
    vim.notify('Job not found: ' .. job_id, vim.log.levels.ERROR)
    return
  end
  
  local depends_on_job = manager.get_job(depends_on_id)
  if not depends_on_job then
    vim.notify('Dependency job not found: ' .. depends_on_id, vim.log.levels.ERROR)
    return
  end
  
  -- Add dependency using the job method
  local success, err = job:add_dependency(depends_on_id)
  if success then
    -- Also update the depends_on_job's dependents list
    depends_on_job.dependents = depends_on_job.dependents or {}
    if not vim.tbl_contains(depends_on_job.dependents, job_id) then
      table.insert(depends_on_job.dependents, job_id)
    end
    
    vim.notify(
      string.format('Added dependency: Job %d now depends on Job %d', job_id, depends_on_id),
      vim.log.levels.INFO
    )
    
    -- Refresh UI if open
    if ui.state.is_open then
      ui.refresh()
    end
  else
    vim.notify('Failed to add dependency: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
  end
end

-- Command: Show job dependencies
function M.show_dependencies(args)
  local job_id = tonumber(args.args)
  
  if not job_id then
    vim.notify('Usage: RJobShowDependencies <job_id>', vim.log.levels.ERROR)
    return
  end
  
  local job = manager.get_job(job_id)
  if not job then
    vim.notify('Job not found: ' .. job_id, vim.log.levels.ERROR)
    return
  end
  
  local lines = {
    string.format('Dependencies for Job %d (%s):', job_id, job.name),
    '',
  }
  
  -- Show what this job depends on
  if job.depends_on and #job.depends_on > 0 then
    table.insert(lines, 'Depends on:')
    for _, dep_id in ipairs(job.depends_on) do
      local dep_job = manager.get_job(dep_id)
      if dep_job then
        table.insert(lines, string.format('  → Job %d: %s [%s]', dep_id, dep_job.name, dep_job.status))
      else
        table.insert(lines, string.format('  → Job %d: (not found)', dep_id))
      end
    end
  else
    table.insert(lines, 'Depends on: None')
  end
  
  table.insert(lines, '')
  
  -- Show what depends on this job
  if job.dependents and #job.dependents > 0 then
    table.insert(lines, 'Dependents (jobs waiting for this):')
    for _, dep_id in ipairs(job.dependents) do
      local dep_job = manager.get_job(dep_id)
      if dep_job then
        table.insert(lines, string.format('  ← Job %d: %s [%s]', dep_id, dep_job.name, dep_job.status))
      else
        table.insert(lines, string.format('  ← Job %d: (not found)', dep_id))
      end
    end
  else
    table.insert(lines, 'Dependents: None')
  end
  
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
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
  -- RJobStart [file] [--after=1,2,3] [--pipeline="name"]
  vim.api.nvim_create_user_command('RJobStart', M.start_job, {
    nargs = '?',
    complete = 'file',
    desc = 'Start R script as background job (supports --after=ID,ID and --pipeline="name")',
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
  
  -- RJobAddDependency <job_id> <depends_on_id>
  vim.api.nvim_create_user_command('RJobAddDependency', M.add_dependency, {
    nargs = 1,
    complete = function()
      return get_job_ids()
    end,
    desc = 'Add dependency: job_id depends_on_id',
  })
  
  -- RJobShowDependencies <job_id>
  vim.api.nvim_create_user_command('RJobShowDependencies', M.show_dependencies, {
    nargs = 1,
    complete = function()
      return get_job_ids()
    end,
    desc = 'Show job dependencies',
  })
end

return M
