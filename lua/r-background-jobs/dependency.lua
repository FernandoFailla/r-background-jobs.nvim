-- Dependency management for r-background-jobs.nvim
-- Handles job dependencies, DAG validation, and dependency resolution

local M = {}

-- Maximum number of dependencies per job
M.MAX_DEPENDENCIES = 10
M.WARN_DEPENDENCIES = 5

-- Validate that adding dependency doesn't create a cycle (DAG validation)
-- Uses Depth-First Search to detect cycles
-- @param job_id number Job that will have the dependency
-- @param depends_on_id number Job that will be depended on
-- @return boolean Valid (true if no cycle would be created)
-- @return string|nil Error message if invalid
function M.validate_dag(job_id, depends_on_id)
  local manager = require('r-background-jobs.manager')
  
  -- Check if depends_on_id exists
  local dep_job = manager.get_job(depends_on_id)
  if not dep_job then
    return false, "Dependency job not found: " .. depends_on_id
  end
  
  -- Check for self-dependency
  if job_id == depends_on_id then
    return false, "Job cannot depend on itself"
  end
  
  -- Perform cycle detection using DFS
  local visited = {}
  local rec_stack = {}
  
  local function has_cycle(current_id)
    -- If in recursion stack, we found a cycle
    if rec_stack[current_id] then
      return true
    end
    
    -- If already visited in a previous path, no need to check again
    if visited[current_id] then
      return false
    end
    
    -- Mark as visited and add to recursion stack
    visited[current_id] = true
    rec_stack[current_id] = true
    
    -- Check all dependencies of current job
    local current_job = manager.get_job(current_id)
    if current_job and current_job.depends_on then
      for _, dep_id in ipairs(current_job.depends_on) do
        if has_cycle(dep_id) then
          return true
        end
      end
    end
    
    -- Remove from recursion stack
    rec_stack[current_id] = false
    return false
  end
  
  -- Temporarily add the new dependency and check for cycles
  -- We need to check if adding depends_on_id to job_id creates a cycle
  -- This means checking if there's a path from depends_on_id back to job_id
  
  local job = manager.get_job(job_id)
  local original_deps = job.depends_on
  
  -- Simulate adding the dependency
  job.depends_on = job.depends_on or {}
  local temp_deps = vim.deepcopy(job.depends_on)
  table.insert(temp_deps, depends_on_id)
  job.depends_on = temp_deps
  
  -- Check if this creates a cycle by checking if depends_on_id leads back to job_id
  local has_cycle_result = has_cycle(job_id)
  
  -- Restore original dependencies
  job.depends_on = original_deps
  
  if has_cycle_result then
    return false, "Adding this dependency would create a cycle"
  end
  
  return true
end

-- Check if a job can run (all dependencies satisfied)
-- @param job_id number Job ID to check
-- @return boolean Can run
-- @return string Reason
function M.can_run(job_id)
  local manager = require('r-background-jobs.manager')
  local job = manager.get_job(job_id)
  
  if not job then
    return false, "Job not found"
  end
  
  return job:can_run()
end

-- Get all jobs that are ready to execute (pending with satisfied dependencies)
-- @return table Array of job IDs ready to run
function M.get_ready_jobs()
  local manager = require('r-background-jobs.manager')
  local ready = {}
  
  for _, job in ipairs(manager.get_jobs()) do
    if job.status == 'pending' then
      local can_run, _ = job:can_run()
      if can_run then
        table.insert(ready, job.id)
      end
    end
  end
  
  return ready
end

-- Add dependency with validation
-- @param job_id number Job that will depend on another
-- @param depends_on_id number Job to depend on
-- @return boolean Success
-- @return string|nil Error message if failed
function M.add(job_id, depends_on_id)
  local manager = require('r-background-jobs.manager')
  
  -- Get jobs
  local job = manager.get_job(job_id)
  if not job then
    return false, "Job not found: " .. job_id
  end
  
  local dep_job = manager.get_job(depends_on_id)
  if not dep_job then
    return false, "Dependency job not found: " .. depends_on_id
  end
  
  -- Check if already has this dependency
  if job.depends_on then
    for _, existing_id in ipairs(job.depends_on) do
      if existing_id == depends_on_id then
        return false, "Job already depends on " .. depends_on_id
      end
    end
  end
  
  -- Validate DAG (no cycles)
  local valid, err = M.validate_dag(job_id, depends_on_id)
  if not valid then
    return false, err
  end
  
  -- Check dependency limit
  job.depends_on = job.depends_on or {}
  if #job.depends_on >= M.MAX_DEPENDENCIES then
    return false, string.format("Maximum dependencies limit (%d) reached", M.MAX_DEPENDENCIES)
  end
  
  -- Warn if approaching limit
  if #job.depends_on >= M.WARN_DEPENDENCIES then
    vim.notify(
      string.format('Warning: Job %d has %d dependencies', job_id, #job.depends_on + 1),
      vim.log.levels.WARN
    )
  end
  
  -- Add dependency
  table.insert(job.depends_on, depends_on_id)
  
  -- Update dependent's dependents list
  dep_job.dependents = dep_job.dependents or {}
  table.insert(dep_job.dependents, job_id)
  
  return true
end

-- Remove dependency
-- @param job_id number Job to remove dependency from
-- @param depends_on_id number Dependency to remove
-- @return boolean Success
-- @return string|nil Error message if failed
function M.remove(job_id, depends_on_id)
  local manager = require('r-background-jobs.manager')
  
  local job = manager.get_job(job_id)
  if not job or not job.depends_on then
    return false, "Job has no dependencies"
  end
  
  -- Find and remove dependency
  local found = false
  for i, dep_id in ipairs(job.depends_on) do
    if dep_id == depends_on_id then
      table.remove(job.depends_on, i)
      found = true
      break
    end
  end
  
  if not found then
    return false, "Dependency not found"
  end
  
  -- Update dependent's dependents list
  local dep_job = manager.get_job(depends_on_id)
  if dep_job and dep_job.dependents then
    for i, dependent_id in ipairs(dep_job.dependents) do
      if dependent_id == job_id then
        table.remove(dep_job.dependents, i)
        break
      end
    end
  end
  
  return true
end

return M
