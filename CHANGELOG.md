# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2025-12-03

### Fixed
- **Bug #1**: Pending jobs now correctly show "-" for Start Time and Duration instead of counting from creation time
  - Jobs are created with `start_time = nil` (instead of `os.time()`)
  - `get_start_time_str()`, `get_duration()`, and `get_duration_str()` now return "-" or 0 when `start_time` is nil
  - Prevents duration from being counted while job is waiting for dependencies
- **Bug #2**: Jobs now correctly transition through status lifecycle: `queued` → `running` → `completed`/`failed`
  - Added new `queued` status for jobs ready to run (no dependencies)
  - Default job status changed from `running` to `queued`
  - `executor.execute_job()` now sets `status = 'running'` and `start_time = os.time()` when execution begins
  - Ensures jobs show proper status in UI at all stages

### Added
- New job status: `queued` (default for newly created jobs)
- Comprehensive bug fixes test suite (`tests/test_bug_fixes.lua`) with 52 tests
- Tests validate correct start_time handling and status transitions

### Changed
- Job lifecycle now: `queued` (creation) → `pending` (has dependencies) → `running` (executing) → `completed`/`failed`/`cancelled`
- Jobs with dependencies start as `pending`, jobs without dependencies start as `queued`

## [0.3.0] - 2025-12-03

### Added
- **Job Dependency System (DAG)**: Jobs can now depend on other jobs, creating directed acyclic graphs
- New job statuses: `pending` (⏳) for jobs waiting on dependencies, `skipped` (⊘) for jobs skipped due to failed dependencies
- **Command flags**:
  - `--after=ID,ID` flag for `RJobStart` to specify job dependencies
  - `--pipeline="name"` flag to group related jobs into named pipelines
- **New commands**:
  - `:RJobAddDependency <job_id> <depends_on_id>` - Add dependency after job creation
  - `:RJobShowDependencies <job_id>` - Show dependency graph for a job
- **Enhanced UI**:
  - New "Pipeline" column showing pipeline names and position (e.g., "[Analysis] 1/3")
  - New "Depends" column showing dependencies (e.g., "→ #1,#2")
  - Hierarchical indentation in Name column for dependent jobs (tree-like visualization)
  - Color-coded pending (yellow) and skipped (gray) statuses
- **Dependency module** (`dependency.lua`):
  - DAG validation with cycle detection using depth-first search
  - Prevents circular dependencies
  - Enforces max 10 dependencies per job (warning at 5)
  - Methods for validation, checking readiness, and managing dependencies

### Changed
- `executor.start_job()` now accepts optional `opts` parameter for dependencies and pipeline metadata
- `manager` now propagates job completion/failure to dependent jobs
- Failed jobs automatically mark all dependent jobs as "skipped" with skip reason
- `:RJobInfo` now displays dependency information (depends_on, dependents, pipeline, skip_reason)
- UI table width increased (min: 100, max: 150) to accommodate new columns
- Overhead calculation updated to 22 characters for 7 columns

### Technical Details
- Job objects now track: `depends_on`, `dependents`, `pipeline_name`, `pipeline_position`, `pipeline_total`, `skip_reason`
- Jobs check `can_run()` before execution (validates all dependencies are completed)
- Automatic dependency propagation on job state changes (completed/failed)
- Skip propagation: when a job fails, all transitive dependents are marked as skipped

### Documentation
- Added comprehensive test documentation in `test-scripts/test-dependencies.md`
- Documented all dependency test scenarios and expected behaviors

## [0.2.1] - 2025-12-03

### Fixed
- Fixed table border being cut off due to incorrect width calculations
- Corrected overhead calculation from 9 to 16 characters (6 pipes + 10 padding spaces)
- Table width now properly constrained to window width

### Added
- Min/max table width limits (70-100 columns by default) for better UX across different terminal sizes
- Configuration options `ui.min_width` and `ui.max_width` to customize table size limits

### Changed
- Table width calculation now uses constrained `table_width` instead of raw `win_width`
- Name column width calculation improved to prevent overflow
- Better handling of narrow and wide terminals

## [0.2.0] - 2025-12-03

### Added
- Dynamic table width calculation that adapts to window size
- Color-coded status indicators (blue=running, green=completed, red=failed, orange=cancelled)
- Highlight groups for better visual distinction (borders, headers, status)
- WinBar title for clear split window separation
- Improved box-drawing characters for cleaner table borders (╭╮╰╯├┤┼)
- Configuration options for `show_winbar` and `use_colors`

### Changed
- Complete UI redesign with properly aligned columns
- Column widths now adjust dynamically based on window width
- Status column now displays icons with colors for better visibility
- Help text formatting improved with better visual separation

### Improved
- Table rendering is now responsive and adapts to terminal width
- Better visual hierarchy with highlight groups
- Clearer separation between different UI elements

## [0.1.2] - 2025-12-03

### Fixed
- Fixed error when cancelling jobs: "bad argument #2 to 'format' (number expected, got nil)"
- Updated on_exit callback in executor to handle nil exit_code from job shutdown
- Added check to skip completion processing for already-cancelled jobs

## [0.1.1] - 2025-12-03

### Fixed
- Fixed job list keybindings not working (Enter, c, d, r) - only 'q' was functional
- Updated `get_job_id_from_line()` regex pattern to properly parse job IDs from table rows that start with box drawing characters (│)

## [0.1.0] - Initial Release

### Added
- Run R scripts asynchronously in background jobs
- Toggle split window UI showing job status and progress
- Real-time output capture (stdout and stderr)
- Job control: start, cancel, view output, and manage jobs
- Telescope integration for job selection
- User commands: RJobStart, RJobsList, RJobCancel, RJobOutput, RJobClear, RJobInfo
