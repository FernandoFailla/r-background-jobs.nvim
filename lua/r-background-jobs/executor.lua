-- Job executor for r-background-jobs.nvim
-- Handles actual execution of R scripts using plenary.job
local config = require('r-background-jobs.config')
local manager = require('r-background-jobs.manager')
local utils = require('r-background-jobs.utils')

local M = {}

-- Execute an R script as a background job
-- @param job table Job object from manager
-- @return boolean Success
-- @return string|nil Error message if failed
function M.execute_job(job)
  local cfg = config.get()
  
  -- Mark job as running and set start time
  job.status = 'running'
  job.start_time = os.time()
  
  -- Ensure output directory exists
  if not utils.ensure_dir(cfg.output_dir) then
    return false, "Failed to create output directory: " .. cfg.output_dir
  end
  
  -- Set output file path
  job.output_file = string.format('%s/job_%d.txt', cfg.output_dir, job.id)
  
  -- Create empty output file
  if not utils.create_empty_file(job.output_file) then
    return false, "Failed to create output file: " .. job.output_file
  end
  
  -- Check if plenary is available
  local ok, PlenaryJob = pcall(require, 'plenary.job')
  if not ok then
    return false, "plenary.nvim is required but not found. Please install it."
  end
  
  -- Create plenary job
  local plenary_job = PlenaryJob:new({
    command = cfg.rscript_path,
    args = { job.script_path },
    
    -- Handle stdout
    on_stdout = function(_, data)
      if data then
        -- Schedule file write for main thread
        vim.schedule(function()
          utils.append_to_file(job.output_file, data .. '\n')
          -- Trigger update callback for UI refresh
          manager.trigger_job_update(job.id)
        end)
      end
    end,
    
    -- Handle stderr
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          -- Prefix stderr with [ERROR] for clarity
          utils.append_to_file(job.output_file, '[ERROR] ' .. data .. '\n')
          manager.trigger_job_update(job.id)
        end)
      end
    end,
    
    -- Handle process exit
    on_exit = function(j, exit_code)
      vim.schedule(function()
        -- Get the current job to check its status
        local current_job = manager.get_job(job.id)
        
        -- If job was already cancelled, skip completion processing
        if current_job and current_job.status == 'cancelled' then
          return
        end
        
        -- Ensure exit_code is a number (handle nil from shutdown/cancel)
        exit_code = exit_code or -1
        
        -- Write completion message to output
        local completion_msg = string.format(
          '\n--- Job completed with exit code: %d ---\n',
          exit_code
        )
        utils.append_to_file(job.output_file, completion_msg)
        
        -- Mark job as completed or failed based on exit code
        if exit_code == 0 then
          manager.mark_job_completed(job.id)
          vim.notify(
            string.format('Job %d (%s) completed successfully', job.id, job.name),
            vim.log.levels.INFO
          )
        else
          manager.mark_job_failed(job.id)
          vim.notify(
            string.format('Job %d (%s) failed with exit code %d', job.id, job.name, exit_code),
            vim.log.levels.WARN
          )
        end
      end)
    end,
  })
  
  -- Store plenary job reference
  job.plenary_job = plenary_job
  
  -- Start the job
  plenary_job:start()
  
  -- Store PID if available
  if plenary_job.pid then
    job.pid = plenary_job.pid
  end
  
  return true
end

-- Start a new job from script path
-- @param script_path string Path to R script
-- @param opts table Optional configuration {depends_on = {1,2}, pipeline_name = "X", pipeline_id = "Y"}
-- @return table|nil Job object or nil on error
-- @return string|nil Error message if failed
function M.start_job(script_path, opts)
  opts = opts or {}
  
  -- Create job in manager
  local job, err = manager.create_job(script_path)
  if not job then
    return nil, err
  end
  
  -- Set dependencies if provided
  if opts.depends_on and #opts.depends_on > 0 then
    job.depends_on = opts.depends_on
    job.status = 'pending'  -- Start as pending if has dependencies
    
    -- Update the dependency jobs to know that this job depends on them
    for _, dep_id in ipairs(opts.depends_on) do
      local dep_job = manager.get_job(dep_id)
      if dep_job then
        dep_job.dependents = dep_job.dependents or {}
        table.insert(dep_job.dependents, job.id)
      else
        -- Dependency not found, clean up and fail
        manager.delete_job(job.id)
        return nil, "Dependency job not found: " .. dep_id
      end
    end
  end
  
  -- Set pipeline info if provided
  if opts.pipeline_name then
    job.pipeline_name = opts.pipeline_name
    job.pipeline_id = opts.pipeline_id
    job.pipeline_position = opts.pipeline_position
    job.pipeline_total = opts.pipeline_total
  end
  
  -- Check if can execute immediately
  local can_run, reason = job:can_run()
  
  if can_run then
    -- Execute the job immediately
    local success, exec_err = M.execute_job(job)
    if not success then
      -- Remove job from manager if execution failed
      manager.delete_job(job.id)
      return nil, exec_err
    end
    
    vim.notify(
      string.format('Started job %d: %s', job.id, job.name),
      vim.log.levels.INFO
    )
  else
    -- Job is pending, waiting for dependencies
    vim.notify(
      string.format('Job %d (%s) pending: %s', job.id, job.name, reason),
      vim.log.levels.INFO
    )
  end
  
  return job
end

-- Cancel a running job
-- @param job_id number Job ID
-- @return boolean Success
-- @return string|nil Error message if failed
function M.cancel_job(job_id)
  return manager.cancel_job(job_id)
end

return M
