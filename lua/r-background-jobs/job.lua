-- Job object for r-background-jobs.nvim
local utils = require('r-background-jobs.utils')

local M = {}

-- Job statuses
M.STATUS = {
  QUEUED = 'queued',        -- Ready to run (no dependencies)
  PENDING = 'pending',      -- Waiting for dependencies
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  SKIPPED = 'skipped',      -- Skipped due to failed dependency
}

-- Create a new job object
-- @param script_path string Path to R script
-- @return table Job object
function M.new(script_path)
  local job = {
    id = utils.generate_id(),
    name = utils.get_filename(script_path),
    script_path = utils.get_absolute_path(script_path),
    status = M.STATUS.QUEUED,  -- Start as queued, will become running when executed
    start_time = nil,  -- Will be set when job actually starts executing
    end_time = nil,
    pid = nil,
    output_file = nil,
    plenary_job = nil,  -- Will hold the plenary Job object
    
    -- Dependencies
    depends_on = nil,     -- Array of job IDs this job depends on
    dependents = nil,     -- Array of job IDs that depend on this job
    
    -- Pipeline info
    pipeline_id = nil,       -- Unique pipeline ID (if part of a pipeline)
    pipeline_name = nil,     -- Human-readable pipeline name
    pipeline_position = nil, -- Position in pipeline (1, 2, 3...)
    pipeline_total = nil,    -- Total jobs in pipeline
    
    -- Skip reason (if status is SKIPPED)
    skip_reason = nil,
  }
  
  -- Set metatable for methods
  setmetatable(job, { __index = M })
  
  return job
end

-- Check if job is currently running
-- @return boolean True if running
function M:is_running()
  return self.status == M.STATUS.RUNNING
end

-- Check if job is finished (completed, failed, or cancelled)
-- @return boolean True if finished
function M:is_finished()
  return self.status == M.STATUS.COMPLETED
      or self.status == M.STATUS.FAILED
      or self.status == M.STATUS.CANCELLED
end

-- Get job duration in seconds
-- @return number Duration in seconds
function M:get_duration()
  if not self.start_time then
    return 0
  end
  return utils.calculate_duration(self.start_time, self.end_time)
end

-- Get formatted duration string
-- @return string Formatted duration
function M:get_duration_str()
  if not self.start_time then
    return "-"
  end
  return utils.format_duration(self:get_duration())
end

-- Get formatted start time
-- @return string Formatted start time
function M:get_start_time_str()
  if not self.start_time then
    return "-"
  end
  return utils.format_time(self.start_time)
end

-- Get status icon
-- @return string Icon representing job status
function M:get_status_icon()
  if self.status == M.STATUS.RUNNING then
    return '●'
  elseif self.status == M.STATUS.COMPLETED then
    return '✓'
  elseif self.status == M.STATUS.FAILED then
    return '✗'
  elseif self.status == M.STATUS.CANCELLED then
    return '✕'
  elseif self.status == M.STATUS.PENDING then
    return '⏳'
  elseif self.status == M.STATUS.SKIPPED then
    return '⊘'
  else
    return '?'
  end
end

-- Get colored status string with icon
-- @return string Status with icon and color
function M:get_status_display()
  local icon = self:get_status_icon()
  local status_text = self.status:sub(1, 1):upper() .. self.status:sub(2)
  
  if self.status == M.STATUS.RUNNING then
    return icon .. ' Running'
  elseif self.status == M.STATUS.COMPLETED then
    return icon .. ' Done'
  elseif self.status == M.STATUS.FAILED then
    return icon .. ' Failed'
  elseif self.status == M.STATUS.CANCELLED then
    return icon .. ' Cancelled'
  elseif self.status == M.STATUS.PENDING then
    return icon .. ' Pending'
  elseif self.status == M.STATUS.SKIPPED then
    return icon .. ' Skipped'
  else
    return status_text
  end
end

-- Mark job as completed
function M:mark_completed()
  self.status = M.STATUS.COMPLETED
  self.end_time = os.time()
end

-- Mark job as failed
function M:mark_failed()
  self.status = M.STATUS.FAILED
  self.end_time = os.time()
end

-- Mark job as cancelled
function M:mark_cancelled()
  self.status = M.STATUS.CANCELLED
  self.end_time = os.time()
end

-- Mark job as skipped
-- @param reason string Reason for skipping
function M:mark_skipped(reason)
  self.status = M.STATUS.SKIPPED
  self.end_time = os.time()
  self.skip_reason = reason or "Dependency failed"
end

-- Check if job can run (all dependencies satisfied)
-- @return boolean Can run
-- @return string Reason if cannot run
function M:can_run()
  -- If no dependencies, can always run
  if not self.depends_on or #self.depends_on == 0 then
    return true, "No dependencies"
  end
  
  local manager = require('r-background-jobs.manager')
  
  -- Check each dependency
  for _, dep_id in ipairs(self.depends_on) do
    local dep_job = manager.get_job(dep_id)
    
    if not dep_job then
      return false, "Dependency job " .. dep_id .. " not found"
    end
    
    -- If any dependency failed or was cancelled, cannot run
    if dep_job.status == M.STATUS.FAILED or dep_job.status == M.STATUS.CANCELLED then
      return false, "Dependency job " .. dep_id .. " failed/cancelled"
    end
    
    -- If any dependency not completed yet, cannot run
    if dep_job.status ~= M.STATUS.COMPLETED then
      return false, "Dependency job " .. dep_id .. " not yet completed"
    end
  end
  
  return true, "All dependencies satisfied"
end

-- Add dependency to this job
-- @param dep_id number Job ID to depend on
-- @return boolean Success
-- @return string Error message if failed
function M:add_dependency(dep_id)
  -- Initialize depends_on if needed
  if not self.depends_on then
    self.depends_on = {}
  end
  
  -- Check if already depends on this job
  for _, existing_dep_id in ipairs(self.depends_on) do
    if existing_dep_id == dep_id then
      return false, "Already depends on job " .. dep_id
    end
  end
  
  -- Validate DAG (no cycles)
  local dependency = require('r-background-jobs.dependency')
  local valid, err = dependency.validate_dag(self.id, dep_id)
  if not valid then
    return false, err
  end
  
  -- Add dependency
  table.insert(self.depends_on, dep_id)
  
  -- Update the dependency's dependents list
  local manager = require('r-background-jobs.manager')
  local dep_job = manager.get_job(dep_id)
  if dep_job then
    dep_job.dependents = dep_job.dependents or {}
    table.insert(dep_job.dependents, self.id)
  end
  
  return true
end

-- Remove dependency from this job
-- @param dep_id number Job ID to remove dependency on
-- @return boolean Success
function M:remove_dependency(dep_id)
  if not self.depends_on then
    return false
  end
  
  for i, existing_dep_id in ipairs(self.depends_on) do
    if existing_dep_id == dep_id then
      table.remove(self.depends_on, i)
      
      -- Update the dependency's dependents list
      local manager = require('r-background-jobs.manager')
      local dep_job = manager.get_job(dep_id)
      if dep_job and dep_job.dependents then
        for j, dependent_id in ipairs(dep_job.dependents) do
          if dependent_id == self.id then
            table.remove(dep_job.dependents, j)
            break
          end
        end
      end
      
      return true
    end
  end
  
  return false
end

-- Get job info as a table for display
-- @return table Job information
function M:get_info()
  return {
    id = self.id,
    name = self.name,
    script_path = self.script_path,
    status = self:get_status_display(),
    start_time = self:get_start_time_str(),
    duration = self:get_duration_str(),
    output_file = self.output_file,
    pid = self.pid,
  }
end

-- Convert job to string representation
-- @return string String representation
function M:to_string()
  return string.format(
    "[%d] %s - %s (started: %s, duration: %s)",
    self.id,
    self.name,
    self.status,
    self:get_start_time_str(),
    self:get_duration_str()
  )
end

return M
