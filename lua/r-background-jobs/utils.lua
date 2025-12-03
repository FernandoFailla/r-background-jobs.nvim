-- Utility functions for r-background-jobs.nvim
local M = {}

-- Generate unique job ID
local next_id = 1
function M.generate_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

-- Format time duration in human-readable format
-- @param seconds number Duration in seconds
-- @return string Formatted duration (e.g., "2.3s", "1m 23s", "2h 15m")
function M.format_duration(seconds)
  if not seconds or seconds < 0 then
    return "0s"
  end
  
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60
  
  if hours > 0 then
    return string.format("%dh %dm", hours, minutes)
  elseif minutes > 0 then
    return string.format("%dm %ds", minutes, secs)
  else
    return string.format("%.1fs", secs)
  end
end

-- Format timestamp to time string
-- @param timestamp number Unix timestamp
-- @return string Formatted time (HH:MM:SS)
function M.format_time(timestamp)
  if not timestamp then
    return ""
  end
  return os.date("%H:%M:%S", timestamp)
end

-- Calculate duration between two timestamps
-- @param start_time number Start timestamp
-- @param end_time number|nil End timestamp (uses current time if nil)
-- @return number Duration in seconds
function M.calculate_duration(start_time, end_time)
  if not start_time then
    return 0
  end
  local end_t = end_time or os.time()
  return end_t - start_time
end

-- Ensure directory exists, create if it doesn't
-- @param dir string Directory path
-- @return boolean Success
function M.ensure_dir(dir)
  local stat = vim.loop.fs_stat(dir)
  if stat and stat.type == 'directory' then
    return true
  end
  
  -- Create directory with parents
  local ok = vim.fn.mkdir(dir, 'p')
  return ok == 1
end

-- Check if file exists
-- @param path string File path
-- @return boolean True if file exists
function M.file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

-- Get filename from path
-- @param path string File path
-- @return string Filename
function M.get_filename(path)
  return vim.fn.fnamemodify(path, ':t')
end

-- Safely append data to file
-- @param filepath string Path to file
-- @param data string Data to append
-- @return boolean Success
function M.append_to_file(filepath, data)
  local file = io.open(filepath, 'a')
  if not file then
    return false
  end
  
  file:write(data)
  file:close()
  return true
end

-- Read entire file contents
-- @param filepath string Path to file
-- @return string|nil File contents or nil on error
function M.read_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return nil
  end
  
  local content = file:read('*all')
  file:close()
  return content
end

-- Truncate or create empty file
-- @param filepath string Path to file
-- @return boolean Success
function M.create_empty_file(filepath)
  local file = io.open(filepath, 'w')
  if not file then
    return false
  end
  
  file:close()
  return true
end

-- Validate R script path
-- @param path string Script path
-- @return boolean, string True if valid, or false with error message
function M.validate_script_path(path)
  if not path or path == '' then
    return false, "No script path provided"
  end
  
  if not M.file_exists(path) then
    return false, "File does not exist: " .. path
  end
  
  -- Check if file has .R or .r extension
  local ext = vim.fn.fnamemodify(path, ':e'):lower()
  if ext ~= 'r' then
    return false, "File is not an R script (must have .R or .r extension)"
  end
  
  return true
end

-- Get absolute path
-- @param path string Relative or absolute path
-- @return string Absolute path
function M.get_absolute_path(path)
  return vim.fn.fnamemodify(path, ':p')
end

return M
