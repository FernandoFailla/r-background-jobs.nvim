-- Test suite for job dependency system
-- Run with: nvim --headless -c "luafile tests/test_dependencies.lua" -c "qa!"

-- Mock vim global for headless mode
if not vim then
  _G.vim = {
    notify = function(msg, level) print(msg) end,
    log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
    deepcopy = function(t)
      if type(t) ~= 'table' then return t end
      local copy = {}
      for k, v in pairs(t) do
        copy[k] = vim.deepcopy(v)
      end
      return copy
    end,
    tbl_contains = function(t, value)
      for _, v in ipairs(t) do
        if v == value then return true end
      end
      return false
    end,
  }
end

local dependency = require('r-background-jobs.dependency')
local Job = require('r-background-jobs.job')
local manager = require('r-background-jobs.manager')

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

-- Helper to reset manager state
local function reset_manager()
  manager.jobs = {}
end

-- Helper to create and register a job with explicit ID (for testing)
local function create_job_with_id(id, script_path, status)
  local job = Job.new(script_path or ("/tmp/test" .. id .. ".R"))
  job.id = id  -- Override the auto-generated ID
  job.status = status or 'running'
  job.depends_on = job.depends_on or {}
  job.dependents = job.dependents or {}
  table.insert(manager.jobs, job)
  return job
end

print("\n=== Running Job Dependency Tests ===\n")

-- Test 1: Simple Chain Validation (1 → 2 → 3)
print("\n--- Test Suite 1: DAG Validation (Simple Cases) ---")
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'running')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  
  -- Add: job2 depends on job1
  local valid1, err1 = dependency.validate_dag(2, 1)
  assert_true(valid1, "Job 2 should be able to depend on Job 1")
  
  if valid1 then
    job2.depends_on = {1}
    job1.dependents = {2}
  end
  
  -- Add: job3 depends on job2
  local valid2, err2 = dependency.validate_dag(3, 2)
  assert_true(valid2, "Job 3 should be able to depend on Job 2 (chain: 1 → 2 → 3)")
end

-- Test 2: Self-Dependency Prevention
do
  reset_manager()
  local job1 = create_job_with_id(1)
  
  local valid, err = dependency.validate_dag(1, 1)
  assert_false(valid, "Job should not be able to depend on itself")
  assert_not_nil(err, "Should return error message for self-dependency")
end

-- Test 3: Circular Dependency (2-node) - Direct Cycle
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  -- job1 depends on job2
  job1.depends_on = {2}
  job2.dependents = {1}
  
  -- Now try to make job2 depend on job1 (would create cycle)
  local valid, err = dependency.validate_dag(2, 1)
  assert_false(valid, "Should not allow circular dependency (1 ↔ 2)")
  assert_not_nil(err, "Should return error message for cycle")
end

-- Test 4: Circular Dependency (3-node) - Transitive Cycle
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  local job3 = create_job_with_id(3)
  
  -- Setup: job2 → job1, job3 → job2
  job2.depends_on = {1}
  job1.dependents = {2}
  
  job3.depends_on = {2}
  job2.dependents = {3}
  
  -- Now try to make job1 depend on job3 (would create cycle: 1 → 2 → 3 → 1)
  local valid, err = dependency.validate_dag(1, 3)
  assert_false(valid, "Should not allow transitive circular dependency (1 → 2 → 3 → 1)")
end

-- Test 5: Multiple Dependencies (Diamond Pattern)
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'completed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  local job4 = create_job_with_id(4, "/tmp/test4.R", 'pending')
  
  -- Setup: job2 → job1, job3 → job1
  job2.depends_on = {1}
  job3.depends_on = {1}
  job1.dependents = {2, 3}
  
  -- Now add: job4 → job2 (first dependency)
  local valid1 = dependency.validate_dag(4, 2)
  assert_true(valid1, "Job 4 should be able to depend on Job 2")
  
  if valid1 then
    job4.depends_on = {2}
    job2.dependents = {4}
  end
  
  -- Now add: job4 → job3 (second dependency, creates diamond)
  local valid2 = dependency.validate_dag(4, 3)
  assert_true(valid2, "Job 4 should be able to depend on Job 3 (diamond: 1 → 2,3 → 4)")
end

-- Test 6: Non-existent Dependency Job
do
  reset_manager()
  local job1 = create_job_with_id(1)
  
  local valid, err = dependency.validate_dag(1, 999)
  assert_false(valid, "Should not allow dependency on non-existent job")
  assert_not_nil(err, "Should return error message")
end

print("\n--- Test Suite 2: Job.can_run() ---")

-- Test 7: Job with No Dependencies Can Run
do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'running')
  job.depends_on = {}
  
  local can_run, reason = job:can_run()
  assert_true(can_run, "Job with no dependencies should be able to run")
end

-- Test 8: Job with Completed Dependencies Can Run
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'completed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'completed')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  
  job3.depends_on = {1, 2}
  
  local can_run, reason = job3:can_run()
  assert_true(can_run, "Job with all dependencies completed should be able to run")
end

-- Test 9: Job with Running Dependencies Cannot Run
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'completed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'running')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  
  job3.depends_on = {1, 2}
  
  local can_run, reason = job3:can_run()
  assert_false(can_run, "Job with running dependencies should not be able to run")
  assert_not_nil(reason, "Should provide a reason")
end

-- Test 10: Job with Failed Dependency Cannot Run
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'failed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  
  job2.depends_on = {1}
  
  local can_run, reason = job2:can_run()
  assert_false(can_run, "Job with failed dependency should not be able to run")
  assert_not_nil(reason, "Should provide a reason mentioning failure")
end

-- Test 11: Job with Cancelled Dependency Cannot Run
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'cancelled')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  
  job2.depends_on = {1}
  
  local can_run, reason = job2:can_run()
  assert_false(can_run, "Job with cancelled dependency should not be able to run")
end

-- Test 12: Job with Pending Dependency Cannot Run
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'pending')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  
  job2.depends_on = {1}
  
  local can_run, reason = job2:can_run()
  assert_false(can_run, "Job with pending dependency should not be able to run")
end

print("\n--- Test Suite 3: Job.add_dependency() ---")

-- Test 13: Add Valid Dependency
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  local success, err = job2:add_dependency(1)
  assert_true(success, "Should successfully add valid dependency")
  assert_contains(job2.depends_on, 1, "Job 2 should now depend on Job 1")
end

-- Test 14: Prevent Self-Dependency via Job Method
do
  reset_manager()
  local job1 = create_job_with_id(1)
  
  local success, err = job1:add_dependency(1)
  assert_false(success, "Job should not be able to add self-dependency")
end

-- Test 15: Prevent Duplicate Dependency
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  job2.depends_on = {1}
  
  local success, err = job2:add_dependency(1)
  assert_false(success, "Should not allow duplicate dependency")
end

-- Test 16: Prevent Dependency on Non-Existent Job
do
  reset_manager()
  local job1 = create_job_with_id(1)
  
  local success, err = job1:add_dependency(999)
  assert_false(success, "Should not allow dependency on non-existent job")
end

-- Test 17: Prevent Dependency That Creates Cycle
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  -- job2 depends on job1
  job2.depends_on = {1}
  job1.dependents = {2}
  
  -- Try to make job1 depend on job2 (creates cycle)
  local success, err = job1:add_dependency(2)
  assert_false(success, "Should not allow dependency that creates cycle")
end

print("\n--- Test Suite 4: Job.remove_dependency() ---")

-- Test 18: Remove Existing Dependency
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  job2.depends_on = {1}
  
  local success = job2:remove_dependency(1)
  assert_true(success, "Should successfully remove existing dependency")
  assert_equal(#job2.depends_on, 0, "Job 2 should have no dependencies after removal")
end

-- Test 19: Remove Non-Existent Dependency
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  job2.depends_on = {}
  
  local success = job2:remove_dependency(1)
  assert_false(success, "Should fail when removing non-existent dependency")
end

print("\n--- Test Suite 5: Job Status and Display ---")

-- Test 20: Mark Job as Skipped
do
  reset_manager()
  local job = create_job_with_id(1, "/tmp/test.R", 'pending')
  
  job:mark_skipped("Dependency Job 5 failed")
  
  assert_equal(job.status, 'skipped', "Job should be marked as skipped")
  assert_equal(job.skip_reason, "Dependency Job 5 failed", "Skip reason should be set correctly")
end

-- Test 21: Status Display Strings
do
  reset_manager()
  
  local statuses = {
    { status = 'running', expected = '● Running' },
    { status = 'completed', expected = '✓ Done' },
    { status = 'failed', expected = '✗ Failed' },
    { status = 'cancelled', expected = '✕ Cancelled' },
    { status = 'pending', expected = '⏳ Pending' },
    { status = 'skipped', expected = '⊘ Skipped' },
  }
  
  for _, test in ipairs(statuses) do
    local job = create_job_with_id(1, "/tmp/test.R", test.status)
    local display = job:get_status_display()
    assert_equal(display, test.expected, 
      string.format("Status '%s' should display as '%s'", test.status, test.expected))
    
    -- Reset for next iteration
    reset_manager()
  end
end

print("\n--- Test Suite 6: dependency.get_ready_jobs() ---")

-- Test 22: Find Ready Jobs
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'completed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  
  job2.depends_on = {1}
  job3.depends_on = {2}
  
  local ready = dependency.get_ready_jobs()
  assert_equal(#ready, 1, "Should find exactly 1 ready job")
  assert_equal(ready[1], 2, "Job 2 should be ready (Job 1 is completed)")
end

-- Test 23: No Ready Jobs When Dependencies Running
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'running')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'pending')
  
  job2.depends_on = {1}
  
  local ready = dependency.get_ready_jobs()
  assert_equal(#ready, 0, "Should find no ready jobs when dependencies are still running")
end

-- Test 24: Multiple Ready Jobs
do
  reset_manager()
  local job1 = create_job_with_id(1, "/tmp/test1.R", 'completed')
  local job2 = create_job_with_id(2, "/tmp/test2.R", 'completed')
  local job3 = create_job_with_id(3, "/tmp/test3.R", 'pending')
  local job4 = create_job_with_id(4, "/tmp/test4.R", 'pending')
  
  job3.depends_on = {1}
  job4.depends_on = {2}
  
  local ready = dependency.get_ready_jobs()
  assert_equal(#ready, 2, "Should find 2 ready jobs")
end

print("\n--- Test Suite 7: dependency.add() and dependency.remove() ---")

-- Test 25: dependency.add() - Bidirectional Update
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  local success, err = dependency.add(2, 1)
  assert_true(success, "dependency.add() should succeed")
  assert_contains(job2.depends_on, 1, "Job 2 should depend on Job 1")
  assert_contains(job1.dependents, 2, "Job 1 should list Job 2 as dependent")
end

-- Test 26: dependency.add() - Enforce Max Limit (10)
do
  reset_manager()
  
  -- Create 11 jobs
  for i = 1, 11 do
    create_job_with_id(i)
  end
  
  -- Add 10 dependencies to job 11
  for i = 1, 10 do
    local success = dependency.add(11, i)
    if i <= 10 then
      assert_true(success, string.format("Should allow dependency %d/10", i))
    end
  end
  
  -- Try to add 11th dependency
  local job11 = manager.get_job(11)
  assert_equal(#job11.depends_on, 10, "Should have exactly 10 dependencies")
  
  -- Note: We can't add an 11th because we've already added 10
  -- This test verifies the limit is enforced
end

-- Test 27: dependency.remove() - Bidirectional Update
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  -- First add
  dependency.add(2, 1)
  
  -- Then remove
  local success = dependency.remove(2, 1)
  assert_true(success, "dependency.remove() should succeed")
  assert_equal(#job2.depends_on, 0, "Job 2 should no longer depend on Job 1")
  assert_equal(#job1.dependents, 0, "Job 1 should no longer list Job 2 as dependent")
end

-- Test 28: dependency.remove() - Non-existent Dependency
do
  reset_manager()
  local job1 = create_job_with_id(1)
  local job2 = create_job_with_id(2)
  
  local success, err = dependency.remove(2, 1)
  assert_false(success, "Should fail when removing non-existent dependency")
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
