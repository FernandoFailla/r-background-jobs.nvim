# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
