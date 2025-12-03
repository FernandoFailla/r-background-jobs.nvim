# Testing Job Dependencies

This document describes how to manually test the job dependency system.

## Test Scenarios

### 1. Basic Dependency Chain
Create a simple chain: Job 1 → Job 2 → Job 3

```vim
:RJobStart test-scripts/simple.R
" Wait for job 1 to start, note the ID (should be 1)
:RJobStart test-scripts/simple.R --after=1
" Wait for job 2 to be created (should be 2, status: pending)
:RJobStart test-scripts/simple.R --after=2
" Job 3 should be created (status: pending)
```

**Expected behavior:**
- Job 1 starts immediately
- Job 2 shows as "⏳ Pending" until Job 1 completes
- Job 3 shows as "⏳ Pending" until Job 2 completes
- When Job 1 completes, Job 2 should start automatically
- When Job 2 completes, Job 3 should start automatically

### 2. Multiple Dependencies
Create a job that depends on multiple jobs: Job 1, Job 2 → Job 3

```vim
:RJobStart test-scripts/simple.R
:RJobStart test-scripts/simple.R
" Note: Now you should have jobs 1 and 2 running
:RJobStart test-scripts/simple.R --after=1,2
" Job 3 should be pending, waiting for both 1 and 2
```

**Expected behavior:**
- Jobs 1 and 2 start immediately
- Job 3 shows as "⏳ Pending"
- Job 3 only starts after BOTH Job 1 and Job 2 complete

### 3. Pipeline Naming
Create jobs with pipeline names:

```vim
:RJobStart test-scripts/simple.R --pipeline="Analysis"
:RJobStart test-scripts/simple.R --after=1 --pipeline="Analysis"
:RJobStart test-scripts/simple.R --after=2 --pipeline="Analysis"
```

**Expected behavior:**
- All jobs show "[Analysis]" in the Pipeline column
- Jobs are indented in the Name column to show hierarchy

### 4. Failure Propagation
Test that failed jobs skip their dependents:

```vim
:RJobStart test-scripts/with-error.R
" Wait for the job ID (should be 1)
:RJobStart test-scripts/simple.R --after=1
" Job 2 should be pending
```

**Expected behavior:**
- Job 1 fails (because the script has an error)
- Job 2 is automatically marked as "⊘ Skipped"
- Job 2 never runs

### 5. View Dependencies
Test the dependency viewing commands:

```vim
:RJobStart test-scripts/simple.R
:RJobStart test-scripts/simple.R --after=1
:RJobInfo 2
" Should show "Depends on: 1"
:RJobShowDependencies 1
" Should show that Job 2 depends on Job 1
```

### 6. Add Dependency Manually
Test adding dependencies after job creation:

```vim
:RJobStart test-scripts/long-running.R
:RJobStart test-scripts/simple.R
" Now add a dependency manually
:RJobAddDependency 2 1
" Job 2 should now depend on Job 1
```

## UI Verification

When viewing `:RJobsList`, verify:

1. **ID Column**: Shows job IDs correctly
2. **Pipeline Column**: Shows pipeline names or "-"
3. **Name Column**: Shows indentation for dependent jobs (with "└─")
4. **Status Column**: Shows new statuses:
   - "⏳ Pending" (yellow) for jobs waiting on dependencies
   - "⊘ Skipped" (gray) for jobs skipped due to failed dependencies
5. **Depends Column**: Shows "→ #1,#2" format for dependencies, or "-"
6. **Started/Duration**: Work as before

## Commands Reference

- `:RJobStart <file> [--after=ID,ID,...] [--pipeline="name"]` - Start job with optional dependencies
- `:RJobAddDependency <job_id> <depends_on_id>` - Add dependency manually
- `:RJobShowDependencies <job_id>` - Show all dependencies for a job
- `:RJobInfo <job_id>` - Show detailed job info (includes dependency info)

## Notes

- Maximum 10 dependencies per job (warning at 5)
- Circular dependencies are prevented by DAG validation
- Jobs in the same pipeline show visual hierarchy through indentation
