-- Job object for r-background-jobs.nvim
local utils = require('r-background-jobs.utils')

local M = {}

-- Job statuses
M.STATUS = {
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
}

-- Create a new job object
-- @param script_path string Path to R script
-- @return table Job object
function M.new(script_path)
  local job = {
    id = utils.generate_id(),
    name = utils.get_filename(script_path),
    script_path = utils.get_absolute_path(script_path),
    status = M.STATUS.RUNNING,
    start_time = os.time(),
    end_time = nil,
    pid = nil,
    output_file = nil,
    plenary_job = nil,  -- Will hold the plenary Job object
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
  return utils.calculate_duration(self.start_time, self.end_time)
end

-- Get formatted duration string
-- @return string Formatted duration
function M:get_duration_str()
  return utils.format_duration(self:get_duration())
end

-- Get formatted start time
-- @return string Formatted start time
function M:get_start_time_str()
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
    return icon .. ' ' .. status_text
  elseif self.status == M.STATUS.COMPLETED then
    return icon .. ' Done'
  elseif self.status == M.STATUS.FAILED then
    return icon .. ' Failed'
  elseif self.status == M.STATUS.CANCELLED then
    return icon .. ' Cancelled'
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
