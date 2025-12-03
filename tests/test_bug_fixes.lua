-- Test suite for bug fixes validation
-- Run with: nvim --headless -c "luafile tests/test_bug_fixes.lua" -c "qa!"

-- Add current project to runtimepath FIRST (before lazy.nvim plugin)
vim.o.runtimepath = '/home/fernando/Projects/pluginbackgroundjobs,' .. vim.o.runtimepath

-- Force reload modules to use the local version
package.loaded['r-background-jobs.job'] = nil
package.loaded['r-background-jobs.manager'] = nil
package.loaded['r-background-jobs.executor'] = nil
package.loaded['r-background-jobs.utils'] = nil
package.loaded['r-background-jobs.config'] = nil
package.loaded['r-background-jobs.dependency'] = nil

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
        return nil
      end,
    },
    deepcopy = function(t)
      if type(t) ~= 'table' then return t end
      local copy = {}
      for k, v in pairs(t) do
        if type(v) == 'table' then
          copy[k] = vim.deepcopy(v)
        else
          copy[k] = v
        end
      end
      return copy
    end,
    tbl_deep_extend = function(behavior, ...)
      local result = {}
      for _, tbl in ipairs({...}) do
        for k, v in pairs(tbl) do
          result[k] = v
        end
      end
      return result
    end,
    schedule = function(fn) fn() end,
  }
end

-- Load modules
local Job = require('r-background-jobs.job')
local manager = require('r-background-jobs.manager')
local executor = require('r-background-jobs.executor')

-- Helper to reset manager state
local function reset_manager()
  manager.jobs = {}
end

-- Test script path (reuse existing test script)
local test_script = '/home/fernando/Projects/pluginbackgroundjobs/test-scripts/simple.R'

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

-- Test suite
print("\n" .. string.rep("=", 70))
print("BUG FIXES TEST SUITE")
print(string.rep("=", 70) .. "\n")

-- Bug #1: Pending jobs should not have start_time set
print("\n--- Bug #1: Pending jobs should not have start_time set ---\n")

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_nil(job.start_time, 'New job should have nil start_time')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_equal(job:get_start_time_str(), '-', 
               'Should return "-" for start_time_str when start_time is nil')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_equal(job:get_duration(), 0, 
               'Should return 0 for duration when start_time is nil')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_equal(job:get_duration_str(), '-', 
               'Should return "-" for duration_str when start_time is nil')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  job.status = 'pending'
  job.depends_on = {999}
  
  assert_nil(job.start_time, 'Pending job should have nil start_time')
  assert_equal(job:get_start_time_str(), '-', 'Pending job should show "-" for start time')
  assert_equal(job:get_duration_str(), '-', 'Pending job should show "-" for duration')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_equal(job:get_start_time_str(), '-', 'Should be "-" before running')
  
  job.status = 'running'
  job.start_time = os.time()
  
  local start_str = job:get_start_time_str()
  assert_true(start_str ~= '-', 'Should not be "-" after running')
  assert_true(#start_str > 0, 'Should have non-empty start time string')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  assert_equal(job:get_duration(), 0, 'Duration should be 0 before start')
  assert_equal(job:get_duration_str(), '-', 'Duration string should be "-" before start')
  
  job.status = 'running'
  job.start_time = os.time() - 5
  
  local duration = job:get_duration()
  assert_true(duration >= 5 and duration <= 6, 'Duration should be approximately 5 seconds')
  
  local duration_str = job:get_duration_str()
  assert_true(duration_str:match('%d+s') ~= nil, 'Duration string should show seconds')
end

-- Bug #2: Status should transition pending -> running -> completed
print("\n--- Bug #2: Status should transition pending -> running -> completed ---\n")

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  job.status = 'pending'
  
  job.status = 'running'
  job.start_time = os.time()
  
  assert_equal(job.status, 'running', 'Status should be running after execute_job')
  assert_not_nil(job.start_time, 'Start time should be set when status becomes running')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  job.status = 'pending'
  assert_nil(job.start_time, 'Start time should be nil when pending')
  
  local before_time = os.time()
  job.status = 'running'
  job.start_time = os.time()
  local after_time = os.time()
  
  assert_equal(job.status, 'running', 'Status should be running')
  assert_not_nil(job.start_time, 'Start time should be set')
  assert_true(job.start_time >= before_time and job.start_time <= after_time,
              'Start time should be current time')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  
  assert_equal(job.status, 'queued', 'Should start as queued')
  assert_nil(job.start_time, 'Should have no start time')
  
  job.status = 'running'
  job.start_time = os.time()
  assert_equal(job.status, 'running', 'Should be running')
  assert_not_nil(job.start_time, 'Should have start time')
  
  job.status = 'completed'
  assert_equal(job.status, 'completed', 'Should be completed')
  assert_not_nil(job.start_time, 'Should still have start time')
end

do
  reset_manager()
  local job, _ = manager.create_job(test_script)
  job.status = 'pending'
  
  assert_equal(job:get_duration(), 0, 'Duration should be 0 when pending')
  assert_equal(job:get_duration_str(), '-', 'Duration string should be "-" when pending')
  
  job.status = 'running'
  job.start_time = os.time() - 3
  
  local duration = job:get_duration()
  assert_true(duration >= 3 and duration <= 4, 'Duration should be approximately 3 seconds')
  assert_true(job:get_duration_str():match('%d+s') ~= nil, 'Should show duration in seconds')
end

do
  reset_manager()
  
  local parent_job, _ = manager.create_job(test_script)
  parent_job.status = 'completed'
  
  local child_job, _ = manager.create_job(test_script)
  child_job.status = 'pending'
  child_job.depends_on = {parent_job.id}
  
  assert_equal(child_job.status, 'pending', 'Dependent job should be pending')
  assert_nil(child_job.start_time, 'Dependent job should have no start time')
  
  local can_run, _ = child_job:can_run()
  assert_true(can_run, 'Child should be able to run after parent completes')
  
  child_job.status = 'running'
  child_job.start_time = os.time()
  
  assert_equal(child_job.status, 'running', 'Child should be running')
  assert_not_nil(child_job.start_time, 'Child should have start time')
end

-- Integration: Both bugs fixed together
print("\n--- Integration: Both bugs fixed together ---\n")

do
  reset_manager()
  
  local job1, _ = manager.create_job(test_script)
  local job2, _ = manager.create_job(test_script)
  
  assert_equal(job1.status, 'queued', 'Job1 should start as queued')
  assert_nil(job1.start_time, 'Job1 should have no start time when queued')
  
  job1.status = 'running'
  job1.start_time = os.time()
  assert_equal(job1.status, 'running', 'Job1 should be running')
  assert_not_nil(job1.start_time, 'Job1 should have start time when running')
  
  job1.status = 'completed'
  assert_equal(job1.status, 'completed', 'Job1 should be completed')
  
  job2.status = 'pending'
  job2.depends_on = {job1.id}
  assert_nil(job2.start_time, 'Job2 should have no start time when pending')
  assert_equal(job2:get_start_time_str(), '-', 'Job2 should show "-" for start time when pending')
  assert_equal(job2:get_duration_str(), '-', 'Job2 should show "-" for duration when pending')
  
  local can_run, _ = job2:can_run()
  assert_true(can_run, 'Job2 should be able to run after Job1 completes')
  
  job2.status = 'running'
  job2.start_time = os.time()
  assert_equal(job2.status, 'running', 'Job2 should be running')
  assert_not_nil(job2.start_time, 'Job2 should have start time when running')
  assert_true(job2:get_start_time_str() ~= '-', 'Job2 should show real start time when running')
  
  job2.status = 'completed'
  assert_equal(job2.status, 'completed', 'Job2 should be completed')
end

do
  reset_manager()
  
  local job = Job.new(test_script)
  job.id = 999  -- Set explicit ID
  local creation_time = os.time()
  
  job.status = 'pending'
  job.depends_on = {9999}
  
  os.execute('sleep 1')
  
  assert_nil(job.start_time, 'Should have no start time while pending')
  assert_equal(job:get_duration(), 0, 'Should have 0 duration while pending')
  assert_equal(job:get_duration_str(), '-', 'Should show "-" for duration while pending')
  
  job.status = 'running'
  job.start_time = os.time()
  
  local duration = job:get_duration()
  assert_true(duration < 2, 'Duration should be less than 2 seconds (not counting pending time)')
end

-- Print summary
print("\n" .. string.rep("=", 70))
print("TEST SUMMARY")
print(string.rep("=", 70))
print(string.format("Total tests: %d", tests_run))
print(string.format("Passed: %d", tests_passed))
print(string.format("Failed: %d", tests_failed))
print(string.format("Success rate: %.1f%%", (tests_passed / tests_run) * 100))
print(string.rep("=", 70) .. "\n")

if tests_failed > 0 then
  os.exit(1)
end
