-- UI module for r-background-jobs.nvim
-- Handles the split window job list interface
local config = require('r-background-jobs.config')
local manager = require('r-background-jobs.manager')
local utils = require('r-background-jobs.utils')

local M = {}

-- UI State
M.state = {
  buf = nil,          -- Buffer number
  win = nil,          -- Window ID
  timer = nil,        -- Auto-refresh timer
  is_open = false,    -- Whether window is open
}

-- Create the jobs list buffer
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'r-jobs-list')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Set buffer name
  vim.api.nvim_buf_set_name(buf, 'R Background Jobs')
  
  return buf
end

-- Setup buffer keymaps
local function setup_keymaps(buf)
  local opts = { noremap = true, silent = true, buffer = buf }
  
  -- View job output
  vim.keymap.set('n', '<CR>', function()
    M.view_job_output()
  end, opts)
  
  -- Cancel job
  vim.keymap.set('n', 'c', function()
    M.cancel_selected_job()
  end, opts)
  
  -- Delete job
  vim.keymap.set('n', 'd', function()
    M.delete_selected_job()
  end, opts)
  
  -- Refresh list
  vim.keymap.set('n', 'r', function()
    M.refresh()
  end, opts)
  
  -- Close window
  vim.keymap.set('n', 'q', function()
    M.close()
  end, opts)
  
  -- Show help
  vim.keymap.set('n', '?', function()
    M.show_help()
  end, opts)
end

-- Get the job ID from current line
local function get_job_id_from_line()
  local line = vim.api.nvim_get_current_line()
  -- Extract ID from line (format: "│ ID  Name  Status...")
  -- The line starts with a box drawing character (│) followed by space and the ID
  local id = line:match('^│%s*(%d+)')
  return tonumber(id)
end

-- Render the jobs list
function M.render()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end
  
  local jobs = manager.get_jobs()
  local lines = {}
  
  -- Header
  table.insert(lines, '┌─ R Background Jobs ──────────────────────────────────────┐')
  table.insert(lines, string.format(
    '│ %-4s  %-25s %-12s %-10s %-8s │',
    'ID', 'Name', 'Status', 'Started', 'Duration'
  ))
  table.insert(lines, '│ ──────────────────────────────────────────────────────── │')
  
  -- Job rows
  if #jobs == 0 then
    table.insert(lines, '│                      No jobs yet                         │')
  else
    for _, job in ipairs(jobs) do
      local line = string.format(
        '│ %-4d  %-25s %-12s %-10s %-8s │',
        job.id,
        -- Truncate name if too long
        #job.name > 25 and job.name:sub(1, 22) .. '...' or job.name,
        job:get_status_display(),
        job:get_start_time_str(),
        job:get_duration_str()
      )
      table.insert(lines, line)
    end
  end
  
  -- Footer with help
  table.insert(lines, '│                                                          │')
  table.insert(lines, '│ <CR>: view | d: delete | c: cancel | r: refresh | q: close │')
  table.insert(lines, '└──────────────────────────────────────────────────────────┘')
  
  -- Update buffer content
  vim.api.nvim_buf_set_option(M.state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.buf, 'modifiable', false)
end

-- Create and open the window
function M.open()
  if M.state.is_open and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    -- Window already open, just focus it
    vim.api.nvim_set_current_win(M.state.win)
    return
  end
  
  local cfg = config.get()
  
  -- Create buffer if needed
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    M.state.buf = create_buffer()
    setup_keymaps(M.state.buf)
  end
  
  -- Create window
  local win_opts = {
    relative = 'editor',
    width = vim.o.columns,
    height = cfg.ui.size,
    row = vim.o.lines - cfg.ui.size - 2,
    col = 0,
    style = 'minimal',
    border = 'none',
  }
  
  -- Use split instead of floating window for MVP
  if cfg.ui.orientation == 'horizontal' then
    vim.cmd(cfg.ui.position .. ' ' .. cfg.ui.size .. 'split')
  else
    vim.cmd(cfg.ui.position .. ' ' .. cfg.ui.size .. 'vsplit')
  end
  
  M.state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.state.win, M.state.buf)
  
  -- Set window options
  vim.api.nvim_win_set_option(M.state.win, 'number', false)
  vim.api.nvim_win_set_option(M.state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(M.state.win, 'cursorline', true)
  vim.api.nvim_win_set_option(M.state.win, 'wrap', false)
  
  M.state.is_open = true
  
  -- Render initial content
  M.render()
  
  -- Start auto-refresh timer
  M.start_auto_refresh()
end

-- Close the window
function M.close()
  -- Stop timer
  M.stop_auto_refresh()
  
  -- Close window
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end
  
  M.state.win = nil
  M.state.is_open = false
end

-- Toggle window open/close
function M.toggle()
  if M.state.is_open then
    M.close()
  else
    M.open()
  end
end

-- Refresh the display
function M.refresh()
  M.render()
end

-- Start auto-refresh timer
function M.start_auto_refresh()
  M.stop_auto_refresh()  -- Stop existing timer if any
  
  local cfg = config.get()
  
  M.state.timer = vim.loop.new_timer()
  M.state.timer:start(cfg.refresh_interval, cfg.refresh_interval, vim.schedule_wrap(function()
    if M.state.is_open then
      M.render()
    end
  end))
end

-- Stop auto-refresh timer
function M.stop_auto_refresh()
  if M.state.timer then
    M.state.timer:stop()
    M.state.timer:close()
    M.state.timer = nil
  end
end

-- View output of selected job
function M.view_job_output()
  local job_id = get_job_id_from_line()
  if not job_id then
    vim.notify('No job selected', vim.log.levels.WARN)
    return
  end
  
  local job = manager.get_job(job_id)
  if not job then
    vim.notify('Job not found: ' .. job_id, vim.log.levels.ERROR)
    return
  end
  
  if not job.output_file or not utils.file_exists(job.output_file) then
    vim.notify('Output file not found for job ' .. job_id, vim.log.levels.WARN)
    return
  end
  
  -- Open output in new split
  vim.cmd('rightbelow split ' .. vim.fn.fnameescape(job.output_file))
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(0, 'filetype', 'r')
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  
  -- Scroll to end if job is running
  if job:is_running() then
    vim.cmd('normal! G')
  end
end

-- Cancel selected job
function M.cancel_selected_job()
  local job_id = get_job_id_from_line()
  if not job_id then
    vim.notify('No job selected', vim.log.levels.WARN)
    return
  end
  
  local success, err = manager.cancel_job(job_id)
  if success then
    vim.notify('Job ' .. job_id .. ' cancelled', vim.log.levels.INFO)
    M.refresh()
  else
    vim.notify('Failed to cancel job: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
  end
end

-- Delete selected job
function M.delete_selected_job()
  local job_id = get_job_id_from_line()
  if not job_id then
    vim.notify('No job selected', vim.log.levels.WARN)
    return
  end
  
  local success, err = manager.delete_job(job_id)
  if success then
    vim.notify('Job ' .. job_id .. ' deleted', vim.log.levels.INFO)
    M.refresh()
  else
    vim.notify('Failed to delete job: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
  end
end

-- Show help
function M.show_help()
  local help = {
    'R Background Jobs - Help',
    '',
    'Keybindings:',
    '  <CR>  - View job output',
    '  c     - Cancel selected job',
    '  d     - Delete job from list',
    '  r     - Refresh list',
    '  q     - Close window',
    '  ?     - Show this help',
    '',
    'Press any key to close...',
  }
  
  vim.notify(table.concat(help, '\n'), vim.log.levels.INFO)
end

-- Register callbacks with manager
manager.register_callback('on_job_start', function()
  if M.state.is_open then
    M.refresh()
  end
end)

manager.register_callback('on_job_complete', function()
  if M.state.is_open then
    M.refresh()
  end
end)

manager.register_callback('on_job_update', function()
  -- Updates are already handled by auto-refresh timer
  -- This is here for potential future use
end)

return M
