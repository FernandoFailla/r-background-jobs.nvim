-- Job manager for r-background-jobs.nvim
local Job = require('r-background-jobs.job')
local utils = require('r-background-jobs.utils')

local M = {}

-- Job storage
M.jobs = {}

-- Callbacks for job events
M.callbacks = {
  on_job_start = {},
  on_job_complete = {},
  on_job_update = {},
}

-- Register a callback for job events
-- @param event string Event name ('on_job_start', 'on_job_complete', 'on_job_update')
-- @param callback function Callback function
function M.register_callback(event, callback)
  if M.callbacks[event] then
    table.insert(M.callbacks[event], callback)
  end
end

-- Trigger callbacks for an event
-- @param event string Event name
-- @param ... any Arguments to pass to callbacks
local function trigger_callbacks(event, ...)
  if M.callbacks[event] then
    for _, callback in ipairs(M.callbacks[event]) do
      local ok, err = pcall(callback, ...)
      if not ok then
        vim.notify(
          string.format('Error in %s callback: %s', event, err),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

-- Create and register a new job
-- @param script_path string Path to R script
-- @return table|nil Job object or nil on error
-- @return string|nil Error message if failed
function M.create_job(script_path)
  -- Validate script path
  local valid, err = utils.validate_script_path(script_path)
  if not valid then
    return nil, err
  end
  
  -- Create job object
  local job = Job.new(script_path)
  
  -- Add to jobs list
  table.insert(M.jobs, job)
  
  -- Trigger callback
  trigger_callbacks('on_job_start', job)
  
  return job
end

-- Get all jobs
-- @return table Array of jobs
function M.get_jobs()
  return M.jobs
end

-- Get job by ID
-- @param id number Job ID
-- @return table|nil Job object or nil if not found
function M.get_job(id)
  for _, job in ipairs(M.jobs) do
    if job.id == id then
      return job
    end
  end
  return nil
end

-- Get running jobs
-- @return table Array of running jobs
function M.get_running_jobs()
  local running = {}
  for _, job in ipairs(M.jobs) do
    if job:is_running() then
      table.insert(running, job)
    end
  end
  return running
end

-- Get finished jobs
-- @return table Array of finished jobs
function M.get_finished_jobs()
  local finished = {}
  for _, job in ipairs(M.jobs) do
    if job:is_finished() then
      table.insert(finished, job)
    end
  end
  return finished
end

-- Cancel a job by ID
-- @param id number Job ID
-- @return boolean Success
-- @return string|nil Error message if failed
function M.cancel_job(id)
  local job = M.get_job(id)
  if not job then
    return false, "Job not found: " .. id
  end
  
  if not job:is_running() then
    return false, "Job is not running"
  end
  
  -- Cancel the plenary job if it exists
  if job.plenary_job then
    job.plenary_job:shutdown()
  end
  
  -- Mark as cancelled
  job:mark_cancelled()
  
  -- Trigger callback
  trigger_callbacks('on_job_complete', job)
  
  return true
end

-- Delete a job from the list
-- @param id number Job ID
-- @return boolean Success
-- @return string|nil Error message if failed
function M.delete_job(id)
  for i, job in ipairs(M.jobs) do
    if job.id == id then
      -- Don't allow deleting running jobs
      if job:is_running() then
        return false, "Cannot delete running job. Cancel it first."
      end
      
      -- Remove from list
      table.remove(M.jobs, i)
      return true
    end
  end
  
  return false, "Job not found: " .. id
end

-- Clear all finished jobs
-- @return number Number of jobs cleared
function M.clear_finished()
  local count = 0
  local i = 1
  
  while i <= #M.jobs do
    if M.jobs[i]:is_finished() then
      table.remove(M.jobs, i)
      count = count + 1
    else
      i = i + 1
    end
  end
  
  return count
end

-- Mark job as completed (called by executor)
-- @param id number Job ID
function M.mark_job_completed(id)
  local job = M.get_job(id)
  if job then
    job:mark_completed()
    trigger_callbacks('on_job_complete', job)
    
    -- Check and start dependent jobs
    M.check_and_start_dependents(id)
  end
end

-- Mark job as failed (called by executor)
-- @param id number Job ID
function M.mark_job_failed(id)
  local job = M.get_job(id)
  if job then
    job:mark_failed()
    trigger_callbacks('on_job_complete', job)
    
    -- Propagate failure to dependents (mark as skipped)
    M.check_and_start_dependents(id)
  end
end

-- Trigger update callback (called by executor for real-time updates)
-- @param id number Job ID
function M.trigger_job_update(id)
  local job = M.get_job(id)
  if job then
    trigger_callbacks('on_job_update', job)
  end
end

-- Get job count
-- @return number Total number of jobs
function M.get_job_count()
  return #M.jobs
end

-- Get running job count
-- @return number Number of running jobs
function M.get_running_count()
  local count = 0
  for _, job in ipairs(M.jobs) do
    if job:is_running() then
      count = count + 1
    end
  end
  return count
end

-- Get pending jobs
-- @return table Array of pending jobs
function M.get_pending_jobs()
  local pending = {}
  for _, job in ipairs(M.jobs) do
    if job.status == 'pending' then
      table.insert(pending, job)
    end
  end
  return pending
end

-- Check and start dependent jobs after a job completes/fails
-- @param job_id number Job ID that just completed or failed
function M.check_and_start_dependents(job_id)
  local executor = require('r-background-jobs.executor')
  
  local job = M.get_job(job_id)
  if not job or not job.dependents then
    return
  end
  
  -- For each dependent job
  for _, dependent_id in ipairs(job.dependents) do
    local dependent = M.get_job(dependent_id)
    
    if dependent and dependent.status == 'pending' then
      local can_run, reason = dependent:can_run()
      
      if can_run then
        -- All dependencies satisfied, start the job
        vim.notify(
          string.format('Starting dependent job %d: %s', dependent_id, dependent.name),
          vim.log.levels.INFO
        )
        executor.execute_job(dependent)
      else
        -- Check if any dependency failed/cancelled
        local should_skip = false
        if dependent.depends_on then
          for _, dep_id in ipairs(dependent.depends_on) do
            local dep = M.get_job(dep_id)
            if dep and (dep.status == 'failed' or dep.status == 'cancelled') then
              should_skip = true
              break
            end
          end
        end
        
        if should_skip then
          -- Mark as skipped and propagate to its dependents
          dependent:mark_skipped(reason)
          vim.notify(
            string.format('Job %d (%s) skipped: %s', dependent_id, dependent.name, reason),
            vim.log.levels.WARN
          )
          
          -- Recursively check this job's dependents
          M.check_and_start_dependents(dependent_id)
        end
      end
    end
  end
end

-- Clear all jobs (for testing/debugging)
function M.clear_all()
  M.jobs = {}
end

return M
