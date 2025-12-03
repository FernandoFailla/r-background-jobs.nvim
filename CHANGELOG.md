# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
