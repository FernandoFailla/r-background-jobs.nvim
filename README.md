# r-background-jobs.nvim

> **Note:** This project was fully built using AI assistance (vibe code/AI coding tools). While functional, users should be aware of this development approach.

A Neovim plugin that brings RStudio-like background job execution to R development in Neovim.

## Features

- Run R scripts asynchronously in background jobs
- Toggle split window UI showing job status and progress
- Real-time output capture (stdout and stderr)
- Job control: start, cancel, view output, and manage jobs
- Telescope integration for job selection
- Works with any R setup (requires Rscript in PATH)

## Requirements

- Neovim >= 0.8.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (required)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional but recommended)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'yourusername/r-background-jobs.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',  -- Optional
  },
  config = function()
    require('r-background-jobs').setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'yourusername/r-background-jobs.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',  -- Optional
  },
  config = function()
    require('r-background-jobs').setup()
  end
}
```

## Quick Start

```lua
-- Basic setup with defaults
require('r-background-jobs').setup()

-- Custom configuration
require('r-background-jobs').setup({
  rscript_path = '/usr/local/bin/Rscript',
  ui = {
    size = 20,
    orientation = 'horizontal',
  },
  keybindings = {
    toggle_jobs = '<leader>tj',
    start_job = '<leader>rr',
  }
})
```

## Usage

### Commands

- `:RJobStart [file]` - Start a background job (uses current file if no argument)
- `:RJobsList` - Toggle the jobs list window
- `:RJobCancel [id]` - Cancel a running job
- `:RJobOutput [id]` - View job output
- `:RJobClear` - Clear completed/failed jobs from list
- `:RJobInfo [id]` - Show detailed job information

### Default Keybindings

- `<leader>rj` - Toggle jobs list
- `<leader>rs` - Start job from current file

### Jobs List Window Keybindings

- `<CR>` - View job output
- `c` - Cancel selected job
- `d` - Delete job from list
- `r` - Refresh list
- `q` - Close window
- `?` - Show help

## Configuration

```lua
{
  -- Path to Rscript executable
  rscript_path = 'Rscript',
  
  -- Output directory for job logs
  output_dir = vim.fn.stdpath('data') .. '/r-jobs',
  
  -- UI settings
  ui = {
    position = 'botright',      -- Split position
    size = 15,                   -- Lines (horizontal) or columns (vertical)
    orientation = 'horizontal',  -- 'horizontal' or 'vertical'
  },
  
  -- Auto-refresh interval for jobs list (milliseconds)
  refresh_interval = 1000,
  
  -- Default keybindings (set to false to disable)
  keybindings = {
    toggle_jobs = '<leader>rj',
    start_job = '<leader>rs',
  },
}
```

## Development Status

This plugin is under active development. See the implementation checklist for current progress.

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
