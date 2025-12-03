-- Test suite for core job management features
-- Run with: nvim --headless -c "luafile tests/test_core_features.lua" -c "qa!"

-- Mock vim global for headless mode
if not vim then
  _G.vim = {
    notify = function(msg, level) 
      -- Suppress notifications in tests
    end,
    log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
    api = {
      nvim_get_runtime_file = function() return {} end,
      nvim_create_buf = function() return 1 end,
      nvim_buf_set_option = function() end,
      nvim_buf_set_lines = function() end,
      nvim_buf_set_name = function() end,
      nvim_create_namespace = function() return 1 end,
      nvim_buf_clear_namespace = function() end,
      nvim_buf_add_highlight = function() end,
    },
    fn = {
      expand = function(path) return path end,
      fnamemodify = function(path, mod) 
        if mod == ':t' then
          return path:match("([^/]+)$") or path
        end
        return path
      end,
      filereadable = function(path) return 1 end,
      stdpath = function(what) 
        if what == 'data' then
          return '/tmp/nvim-test-data'
        end
        return '/tmp'
      end,
    },
    loop = {
      os_uname = function() return { sysname = "Linux" } end,
      fs_stat = function(path)
        -- Mock file existence - pretend all .R and .r files exist
        if path:match("%.R$") or path:match("%.r$") then
          return { type = 'file', size = 100 }
        end
        -- Non-R files and non-existent files return nil
        return nil
      end,
    },
    deepcopy = function(t)
      if type(t) ~= 'table' then return t end
      local copy = {}
      for k, v in pairs(t) do
        copy[k] = vim.deepcopy(v)
      end
      return copy
    end,
    tbl_contains = function(t, value)
      if type(t) ~= 'table' then return false end
      for _, v in ipairs(t) do
        if v == value then return true end
      end
      return false
    end,
    split = function(str, sep)
      local result = {}
      for match in (str..sep):gmatch("(.-)"..sep) do
        table.insert(result, match)
      end
      return result
    end,
    inspect = function(t)
      if type(t) ~= 'table' then return tostring(t) end
      local items = {}
      for k, v in pairs(t) do
        table.insert(items, tostring(k) .. "=" .. tostring(v))
      end
      return "{ " .. table.concat(items, ", ") .. " }"
    end,
  }
end

local Job = require('r-background-jobs.job')
local manager = require('r-background-jobs.manager')
local executor = require('r-background-jobs.executor')
local utils = require('r-background-jobs.utils')
local config = require('r-background-jobs.config')

-- Test framework
local tests_run = 0
local tests_passed = 0
local tests_failed = 0

local function assert_equal(actual, expected, test_name)
  tests_run = tests_run + 1
  if actual == expected then
    tests_passed = tests_passed + 1
    print(string.format("✓ PASS: %s", test_name))
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format("✗ FAIL: %s", test_name))
    print(string.format("  Expected: %s", tostring(expected)))
    print(string.format("  Got: %s", tostring(actual)))
    return false
  end
end

local function assert_true(condition, test_name)
  return assert_equal(condition, true, test_name)
end

local function assert_false(condition, test_name)
  return assert_equal(condition, false, test_name)
end

local function assert_not_nil(value, test_name)
  tests_run = tests_run + 1
  if value ~= nil then
    tests_passed = tests_passed + 1
    print(string.format("✓ PASS: %s", test_name))
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format("✗ FAIL: %s (value was nil)", test_name))
    return false
  end
end

local function assert_nil(value, test_name)
  tests_run = tests_run + 1
  if value == nil then
    tests_passed = tests_passed + 1
    print(string.format("✓ PASS: %s", test_name))
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format("✗ FAIL: %s (expected nil, got %s)", test_name, tostring(value)))
    return false
  end
end

local function assert_contains(tbl, value, test_name)
  tests_run = tests_run + 1
  if type(tbl) ~= 'table' then
    tests_failed = tests_failed + 1
    print(string.format("✗ FAIL: %s (not a table)", test_name))
    return false
  end
  
  for _, v in ipairs(tbl) do
    if v == value then
      tests_passed = tests_passed + 1
      print(string.format("✓ PASS: %s", test_name))
      return true
    end
  end
  
  tests_failed = tests_failed + 1
  print(string.format("✗ FAIL: %s", test_name))
  print(string.format("  Table does not contain value: %s", tostring(value)))
  return false
end

local function assert_match(str, pattern, test_name)
  tests_run = tests_run + 1
  if type(str) == 'string' and str:match(pattern) then
    tests_passed = tests_passed + 1
    print(string.format("✓ PASS: %s", test_name))
    return true
  else
    tests_failed = tests_failed + 1
    print(string.format("✗ FAIL: %s", test_name))
    print(string.format("  String '%s' does not match pattern '%s'", tostring(str), pattern))
    return false
  end
end

-- Helper to reset manager state
local function reset_manager()
  manager.jobs = {}
end

-- Helper to create a job with explicit ID
local function create_job_with_id(id, script_path, status)
  local job = Job.new(script_path or ("/tmp/test" .. id .. ".R"))
  job.id = id
  job.status = status or 'running'
  job.depends_on = job.depends_on or {}
  job.dependents = job.dependents or {}
  table.insert(manager.jobs, job)
  return job
end

print("\n=== Running Core Features Test Suite ===\n")

-- =============================================================================
-- Test Suite 1: Job Object Creation and Properties
-- =============================================================================
print("\n--- Test Suite 1: Job Object Creation ---")

do
  local job = Job.new("/path/to/script.R")
  
  assert_not_nil(job, "Job.new() should create a job object")
  assert_not_nil(job.id, "Job should have an ID")
  assert_equal(job.name, "script.R", "Job name should be extracted from path")
  assert_equal(job.script_path, "/path/to/script.R", "Script path should be stored")
  assert_equal(job.status, 'running', "Default status should be 'running'")
  assert_not_nil(job.start_time, "Job should have start time")
  assert_nil(job.end_time, "Job should not have end time initially")
  assert_nil(job.pid, "Job should not have PID initially")
end

do
  local job = Job.new("/home/user/analysis/data_processing.R")
  assert_equal(job.name, "data_processing.R", "Job name should handle long paths")
end

-- =============================================================================
-- Test Suite 2: Job Status Methods
-- =============================================================================
print("\n--- Test Suite 2: Job Status Methods ---")

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'running')
  
  assert_true(job:is_running(), "is_running() should return true for running job")
  assert_false(job:is_finished(), "is_finished() should return false for running job")
end

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'completed')
  
  assert_false(job:is_running(), "is_running() should return false for completed job")
  assert_true(job:is_finished(), "is_finished() should return true for completed job")
end

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'failed')
  
  assert_false(job:is_running(), "is_running() should return false for failed job")
  assert_true(job:is_finished(), "is_finished() should return true for failed job")
end

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'cancelled')
  
  assert_false(job:is_running(), "is_running() should return false for cancelled job")
  assert_true(job:is_finished(), "is_finished() should return true for cancelled job")
end

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'pending')
  
  assert_false(job:is_running(), "is_running() should return false for pending job")
  assert_false(job:is_finished(), "is_finished() should return false for pending job")
end

-- =============================================================================
-- Test Suite 3: Job Time Formatting
-- =============================================================================
print("\n--- Test Suite 3: Job Time Formatting ---")

do
  reset_manager()
  local job = create_job_with_id(1)
  job.start_time = os.time()
  
  local time_str = job:get_start_time_str()
  assert_match(time_str, "%d%d:%d%d:%d%d", "Start time should be formatted as HH:MM:SS")
end

do
  reset_manager()
  local job = create_job_with_id(1)
  job.start_time = os.time()
  job.end_time = job.start_time + 65  -- 1 minute 5 seconds
  
  local duration = job:get_duration_str()
  assert_match(duration, "1m", "Duration should show minutes for >60s")
end

do
  reset_manager()
  local job = create_job_with_id(1)
  job.start_time = os.time()
  job.end_time = job.start_time + 5
  
  local duration = job:get_duration_str()
  assert_match(duration, "5", "Duration should show seconds for <60s")
end

do
  reset_manager()
  local job = create_job_with_id(1)
  job.start_time = os.time()
  -- No end_time (still running)
  
  local duration = job:get_duration_str()
  assert_not_nil(duration, "Duration should work for running jobs")
end

-- =============================================================================
-- Test Suite 4: Job Info Method
-- =============================================================================
print("\n--- Test Suite 4: Job Info Method ---")

do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'completed')
  job.pid = 12345
  job.output_file = "/tmp/output.txt"
  job.end_time = job.start_time + 10
  
  local info = job:get_info()
  
  assert_equal(info.id, 1, "Info should include job ID")
  assert_equal(info.name, "test.R", "Info should include job name")
  assert_equal(info.script_path, "/tmp/test.R", "Info should include script path")
  assert_equal(info.status, "✓ Done", "Info should include formatted status")
  assert_not_nil(info.start_time, "Info should include start time")
  assert_not_nil(info.duration, "Info should include duration")
  assert_equal(info.output_file, "/tmp/output.txt", "Info should include output file")
  assert_equal(info.pid, 12345, "Info should include PID")
end

-- =============================================================================
-- Test Suite 5: Manager - Get Jobs
-- =============================================================================
print("\n--- Test Suite 5: Manager - Get Jobs ---")

do
  reset_manager()
  
  local jobs = manager.get_jobs()
  assert_equal(#jobs, 0, "get_jobs() should return empty array initially")
end

do
  reset_manager()
  create_job_with_id(1)
  create_job_with_id(2)
  create_job_with_id(3)
  
  local jobs = manager.get_jobs()
  assert_equal(#jobs, 3, "get_jobs() should return all jobs")
end

do
  reset_manager()
  create_job_with_id(1)
  create_job_with_id(2)
  
  local job = manager.get_job(1)
  assert_not_nil(job, "get_job() should find existing job")
  assert_equal(job.id, 1, "get_job() should return correct job")
end

do
  reset_manager()
  create_job_with_id(1)
  
  local job = manager.get_job(999)
  assert_nil(job, "get_job() should return nil for non-existent job")
end

-- =============================================================================
-- Test Suite 6: Manager - Job Counts
-- =============================================================================
print("\n--- Test Suite 6: Manager - Job Counts ---")

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'running')
  create_job_with_id(2, "/tmp/test2.R", 'completed')
  create_job_with_id(3, "/tmp/test3.R", 'running')
  
  local count = manager.get_job_count()
  assert_equal(count, 3, "get_job_count() should return total jobs")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'running')
  create_job_with_id(2, "/tmp/test2.R", 'completed')
  create_job_with_id(3, "/tmp/test3.R", 'running')
  
  local count = manager.get_running_count()
  assert_equal(count, 2, "get_running_count() should return only running jobs")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'completed')
  create_job_with_id(2, "/tmp/test2.R", 'failed')
  
  local count = manager.get_running_count()
  assert_equal(count, 0, "get_running_count() should return 0 when no jobs running")
end

-- =============================================================================
-- Test Suite 7: Manager - Delete Job
-- =============================================================================
print("\n--- Test Suite 7: Manager - Delete Job ---")

do
  reset_manager()
  create_job_with_id(1, "/tmp/test.R", 'running')
  
  local success, err = manager.delete_job(1)
  assert_false(success, "Should not delete running job")
  assert_not_nil(err, "Should return error message")
  assert_match(err, "running", "Error should mention job is running")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test.R", 'completed')
  
  local success = manager.delete_job(1)
  assert_true(success, "Should delete completed job")
  
  local job = manager.get_job(1)
  assert_nil(job, "Job should be removed from list")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test.R", 'failed')
  
  local success = manager.delete_job(1)
  assert_true(success, "Should delete failed job")
end

do
  reset_manager()
  
  local success, err = manager.delete_job(999)
  assert_false(success, "Should fail to delete non-existent job")
  assert_not_nil(err, "Should return error message")
end

-- =============================================================================
-- Test Suite 8: Manager - Clear Finished Jobs
-- =============================================================================
print("\n--- Test Suite 8: Manager - Clear Finished Jobs ---")

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'completed')
  create_job_with_id(2, "/tmp/test2.R", 'failed')
  create_job_with_id(3, "/tmp/test3.R", 'cancelled')
  create_job_with_id(4, "/tmp/test4.R", 'running')
  
  local count = manager.clear_finished()
  assert_equal(count, 3, "Should clear all finished jobs")
  
  local remaining = manager.get_jobs()
  assert_equal(#remaining, 1, "Should keep running job")
  assert_equal(remaining[1].id, 4, "Should keep the running job")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'running')
  create_job_with_id(2, "/tmp/test2.R", 'pending')
  
  local count = manager.clear_finished()
  assert_equal(count, 0, "Should not clear any jobs if none finished")
  assert_equal(#manager.get_jobs(), 2, "All jobs should remain")
end

do
  reset_manager()
  
  local count = manager.clear_finished()
  assert_equal(count, 0, "Should handle empty job list")
end

-- =============================================================================
-- Test Suite 9: Manager - Get Pending Jobs
-- =============================================================================
print("\n--- Test Suite 9: Manager - Get Pending Jobs ---")

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'running')
  create_job_with_id(2, "/tmp/test2.R", 'pending')
  create_job_with_id(3, "/tmp/test3.R", 'pending')
  create_job_with_id(4, "/tmp/test4.R", 'completed')
  
  local pending = manager.get_pending_jobs()
  assert_equal(#pending, 2, "Should return only pending jobs")
  assert_equal(pending[1].id, 2, "First pending job should be ID 2")
  assert_equal(pending[2].id, 3, "Second pending job should be ID 3")
end

do
  reset_manager()
  create_job_with_id(1, "/tmp/test1.R", 'running')
  
  local pending = manager.get_pending_jobs()
  assert_equal(#pending, 0, "Should return empty array if no pending jobs")
end

-- =============================================================================
-- Test Suite 10: Utils - Path Validation
-- =============================================================================
print("\n--- Test Suite 10: Utils - Path Validation ---")

do
  -- Create temporary R file for testing
  local tmp_file = "/tmp/test_script_validation.R"
  local f = io.open(tmp_file, "w")
  if f then
    f:write("# Test R script\n")
    f:close()
  end
  
  local valid, err = utils.validate_script_path(tmp_file)
  assert_true(valid, "Should validate .R extension with existing file")
  assert_nil(err, "Should not return error for valid path")
  
  -- Cleanup
  os.remove(tmp_file)
end

do
  -- Create temporary .r file for testing
  local tmp_file = "/tmp/test_script_lowercase.r"
  local f = io.open(tmp_file, "w")
  if f then
    f:write("# Test R script\n")
    f:close()
  end
  
  local valid, err = utils.validate_script_path(tmp_file)
  assert_true(valid, "Should validate lowercase .r extension with existing file")
  
  -- Cleanup
  os.remove(tmp_file)
end

do
  local valid, err = utils.validate_script_path("/path/to/nonexistent/script.txt")
  assert_false(valid, "Should reject non-R file")
  assert_not_nil(err, "Should return error message")
end

do
  local valid, err = utils.validate_script_path("")
  assert_false(valid, "Should reject empty path")
  assert_not_nil(err, "Should return error message")
end

do
  local valid, err = utils.validate_script_path(nil)
  assert_false(valid, "Should reject nil path")
  assert_not_nil(err, "Should return error message")
end

-- =============================================================================
-- Test Suite 11: Utils - Filename Extraction
-- =============================================================================
print("\n--- Test Suite 11: Utils - Filename Extraction ---")

do
  local filename = utils.get_filename("/path/to/script.R")
  assert_equal(filename, "script.R", "Should extract filename from full path")
end

do
  local filename = utils.get_filename("script.R")
  assert_equal(filename, "script.R", "Should handle filename without path")
end

do
  local filename = utils.get_filename("/very/long/nested/path/to/my_analysis.R")
  assert_equal(filename, "my_analysis.R", "Should handle long nested paths")
end

-- =============================================================================
-- Test Suite 12: Utils - ID Generation
-- =============================================================================
print("\n--- Test Suite 12: Utils - ID Generation ---")

do
  -- Reset ID counter by reloading utils
  package.loaded['r-background-jobs.utils'] = nil
  local utils_fresh = require('r-background-jobs.utils')
  
  local id1 = utils_fresh.generate_id()
  local id2 = utils_fresh.generate_id()
  local id3 = utils_fresh.generate_id()
  
  assert_equal(id1, 1, "First ID should be 1")
  assert_equal(id2, 2, "Second ID should be 2")
  assert_equal(id3, 3, "Third ID should be 3")
  assert_true(id2 > id1, "IDs should be incrementing")
  assert_true(id3 > id2, "IDs should be incrementing")
end

-- =============================================================================
-- Test Suite 13: Utils - Duration Formatting
-- =============================================================================
print("\n--- Test Suite 13: Utils - Duration Formatting ---")

do
  local duration = utils.format_duration(5)
  assert_equal(duration, "5.0s", "Should format seconds")
end

do
  local duration = utils.format_duration(65)
  assert_match(duration, "1m", "Should format minutes")
end

do
  local duration = utils.format_duration(3661)
  assert_match(duration, "1h", "Should format hours")
end

do
  local duration = utils.format_duration(0)
  assert_equal(duration, "0.0s", "Should handle zero")
end

do
  local duration = utils.format_duration(nil)
  assert_equal(duration, "0s", "Should handle nil (return 0s)")
end

do
  local duration = utils.format_duration(-5)
  assert_equal(duration, "0s", "Should handle negative values (return 0s)")
end

-- =============================================================================
-- Test Suite 14: Config - Default Values
-- =============================================================================
print("\n--- Test Suite 14: Config - Default Values ---")

do
  -- Reset and setup config
  package.loaded['r-background-jobs.config'] = nil
  local config_fresh = require('r-background-jobs.config')
  config_fresh.setup({})  -- Initialize with defaults
  
  local cfg = config_fresh.get()
  
  assert_not_nil(cfg, "Config should return a table")
  assert_not_nil(cfg.ui, "Config should have ui section")
  assert_not_nil(cfg.keybindings, "Config should have keybindings section")
  assert_equal(cfg.rscript_path, 'Rscript', "Default Rscript path should be 'Rscript'")
  assert_equal(cfg.refresh_interval, 1000, "Default refresh interval should be 1000ms")
end

do
  package.loaded['r-background-jobs.config'] = nil
  local config_fresh = require('r-background-jobs.config')
  config_fresh.setup({})  -- Initialize with defaults
  
  local cfg = config_fresh.get()
  
  assert_equal(cfg.ui.orientation, 'horizontal', "Default UI orientation should be horizontal")
  assert_equal(cfg.ui.position, 'botright', "Default UI position should be botright")
  assert_equal(cfg.ui.size, 15, "Default UI size should be 15")
end

-- =============================================================================
-- Test Suite 15: Config - Custom Configuration
-- =============================================================================
print("\n--- Test Suite 15: Config - Custom Configuration ---")

do
  package.loaded['r-background-jobs.config'] = nil
  local config_fresh = require('r-background-jobs.config')
  
  config_fresh.setup({
    ui = { size = 20 },
    refresh_interval = 2000,
  })
  
  local cfg = config_fresh.get()
  
  assert_equal(cfg.ui.size, 20, "Custom UI size should override default")
  assert_equal(cfg.refresh_interval, 2000, "Custom refresh interval should override default")
  assert_equal(cfg.ui.orientation, 'horizontal', "Non-overridden values should keep defaults")
end

-- Print summary
print("\n=== Test Summary ===")
print(string.format("Tests run: %d", tests_run))
print(string.format("Passed: %d", tests_passed))
print(string.format("Failed: %d", tests_failed))

if tests_run > 0 then
  print(string.format("Success rate: %.1f%%", (tests_passed / tests_run) * 100))
end

if tests_failed > 0 then
  print("\n❌ Some tests failed!")
  os.exit(1)
else
  print("\n✅ All tests passed!")
  os.exit(0)
end
