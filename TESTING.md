# Testing Guide for r-background-jobs.nvim

This document provides test cases and validation procedures for the plugin.

## Prerequisites

1. Neovim >= 0.8.0 installed
2. R and Rscript installed and in PATH
3. plenary.nvim installed
4. This plugin installed

## Test Scripts

The `test-scripts/` directory contains several R scripts for testing:

- `simple.R` - Quick completion test (< 1 second)
- `long-running.R` - Long job test (~20 seconds with progress output)
- `with-error.R` - Error handling test (exits with error)
- `large-output.R` - Large output handling test

## Manual Test Cases

### Test 1: Plugin Installation and Setup

1. Install the plugin with plenary.nvim dependency
2. Add to init.lua:
   ```lua
   require('r-background-jobs').setup()
   ```
3. Restart Neovim
4. Verify no errors on startup

**Expected:** Plugin loads without errors

---

### Test 2: Basic Job Execution

1. Open `test-scripts/simple.R` in Neovim
2. Run `:RJobStart` (or press `<leader>rs` if using default keybindings)
3. Observe notification: "Started job 1: simple.R"
4. Wait a moment
5. Observe notification: "Job 1 (simple.R) completed successfully"

**Expected:** 
- Job starts successfully
- Job completes with exit code 0
- Notifications appear for start and completion

---

### Test 3: Jobs List UI

1. Start a job (any test script)
2. Run `:RJobsList` (or press `<leader>rj`)
3. Verify the jobs list window opens at bottom
4. Check that the job appears with:
   - Job ID
   - Script name
   - Status (running/completed)
   - Start time
   - Duration

**Expected:**
- Window opens in split at bottom
- Job information is displayed correctly
- Status updates in real-time

---

### Test 4: View Job Output

**Method 1 - From jobs list:**
1. Open jobs list (`:RJobsList`)
2. Navigate to a completed job
3. Press `<CR>`
4. Verify output window opens

**Method 2 - From command:**
1. Run `:RJobOutput 1` (or without ID to use picker)
2. Verify output window opens

**Expected:**
- Output file opens in new split
- Contains stdout and stderr
- Has R syntax highlighting
- Is read-only

---

### Test 5: Long-Running Job

1. Start `long-running.R`: `:RJobStart test-scripts/long-running.R`
2. Open jobs list: `:RJobsList`
3. Observe:
   - Status shows "● Running"
   - Duration updates every second
4. View output while running: press `<CR>` on the job
5. Observe output appearing in real-time
6. Wait for completion (~20 seconds)
7. Verify status changes to "✓ Done"

**Expected:**
- Job runs for ~20 seconds
- Real-time output updates
- Duration counter increments
- Status updates on completion

---

### Test 6: Job Cancellation

1. Start a long-running job: `:RJobStart test-scripts/long-running.R`
2. Open jobs list: `:RJobsList`
3. Press `c` on the running job
4. Verify status changes to "✕ Cancelled"
5. Check output file shows partial results

**Expected:**
- Job is killed successfully
- Status updates to cancelled
- Partial output is preserved

---

### Test 7: Error Handling

1. Start error script: `:RJobStart test-scripts/with-error.R`
2. Wait for completion
3. Observe notification: "Job X (with-error.R) failed with exit code 1"
4. Check jobs list shows "✗ Failed"
5. View output, verify error message is captured with [ERROR] prefix

**Expected:**
- Job fails with non-zero exit code
- Error notification appears
- stderr is captured in output
- Status shows failed

---

### Test 8: Large Output

1. Start: `:RJobStart test-scripts/large-output.R`
2. Wait for completion
3. View output
4. Verify all output is captured correctly

**Expected:**
- All output lines are present
- No truncation or corruption
- File is readable

---

### Test 9: Multiple Simultaneous Jobs

1. Start multiple jobs quickly:
   ```vim
   :RJobStart test-scripts/simple.R
   :RJobStart test-scripts/long-running.R
   :RJobStart test-scripts/large-output.R
   ```
2. Open jobs list
3. Verify all jobs are listed
4. Verify each has unique ID
5. Observe different completion times

**Expected:**
- All jobs run simultaneously
- Each has unique ID (1, 2, 3)
- Jobs complete independently
- No conflicts or race conditions

---

### Test 10: Delete Jobs

1. Complete some jobs
2. Open jobs list
3. Navigate to a completed job
4. Press `d`
5. Verify job is removed from list

**Expected:**
- Completed jobs can be deleted
- Running jobs cannot be deleted (error message)

---

### Test 11: Clear Finished Jobs

1. Complete several jobs
2. Run `:RJobClear`
3. Confirm with 'y'
4. Verify all finished jobs are removed
5. Running jobs remain

**Expected:**
- Confirmation prompt appears
- All finished jobs cleared
- Running jobs untouched

---

### Test 12: Telescope Integration (if installed)

1. Start multiple jobs
2. Run `:RJobOutput` without ID
3. Telescope picker should appear
4. Preview pane shows job output
5. Select a job and press `<CR>`

**Expected:**
- Telescope picker opens with job list
- Preview shows job info and output
- Selection works correctly

**If Telescope not installed:**
- vim.ui.select fallback is used instead

---

### Test 13: Default Keybindings

1. Open any R file
2. Press `<leader>rs`
3. Verify job starts from current file

4. Press `<leader>rj`
5. Verify jobs list toggles

**Expected:**
- `<leader>rs` starts job from current file
- `<leader>rj` toggles jobs list

---

### Test 14: Custom Configuration

1. Setup with custom config:
   ```lua
   require('r-background-jobs').setup({
     ui = { size = 20 },
     keybindings = {
       toggle_jobs = '<leader>tj',
       start_job = false,  -- Disable
     },
   })
   ```
2. Verify jobs list window is 20 lines tall
3. Verify `<leader>tj` toggles list
4. Verify `<leader>rs` doesn't work (disabled)

**Expected:**
- Custom configuration is applied
- UI respects size setting
- Keybindings work as configured

---

### Test 15: Edge Cases

**Test with non-R file:**
1. Try `:RJobStart README.md`
2. Expect error: "File is not an R script"

**Test with non-existent file:**
1. Try `:RJobStart doesnotexist.R`
2. Expect error: "File does not exist"

**Test with no Rscript:**
1. Configure with invalid path: `rscript_path = '/invalid/path'`
2. Try to start a job
3. Expect error about Rscript not found

**Expected:**
- Appropriate error messages for all edge cases
- Plugin doesn't crash

---

## API Testing

Test the Lua API:

```lua
local rjobs = require('r-background-jobs')

-- Start a job programmatically
local job = rjobs.start_job('test-scripts/simple.R')
print('Job ID:', job.id)

-- Get all jobs
local jobs = rjobs.get_jobs()
print('Total jobs:', #jobs)

-- Get specific job
local job1 = rjobs.get_job(1)
if job1 then
  print('Job 1 status:', job1.status)
end

-- Cancel a job
rjobs.cancel_job(1)

-- Clear finished
local cleared = rjobs.clear_finished()
print('Cleared', cleared, 'jobs')
```

---

## Performance Testing

1. Start 10+ jobs simultaneously
2. Monitor Neovim responsiveness
3. Check memory usage
4. Verify all jobs complete successfully

**Expected:**
- Neovim remains responsive
- All jobs execute correctly
- No memory leaks

---

## Test Checklist

- [ ] Test 1: Plugin Installation and Setup
- [ ] Test 2: Basic Job Execution
- [ ] Test 3: Jobs List UI
- [ ] Test 4: View Job Output
- [ ] Test 5: Long-Running Job
- [ ] Test 6: Job Cancellation
- [ ] Test 7: Error Handling
- [ ] Test 8: Large Output
- [ ] Test 9: Multiple Simultaneous Jobs
- [ ] Test 10: Delete Jobs
- [ ] Test 11: Clear Finished Jobs
- [ ] Test 12: Telescope Integration
- [ ] Test 13: Default Keybindings
- [ ] Test 14: Custom Configuration
- [ ] Test 15: Edge Cases
- [ ] API Testing
- [ ] Performance Testing

---

## Reporting Issues

If you encounter any issues during testing:

1. Note the test case that failed
2. Capture any error messages
3. Check Neovim log: `:messages`
4. Check output files in `~/.local/share/nvim/r-jobs/`
5. Report with steps to reproduce
