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
  
  -- Setup highlights
  setup_highlights()
  
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

-- Setup highlight groups for the UI
local function setup_highlights()
  -- Define highlight groups if they don't exist
  local highlights = {
    RJobsBorder = { link = 'FloatBorder' },
    RJobsHeader = { link = 'Title', bold = true },
    RJobsTitle = { link = 'Title', bold = true },
    RJobsRunning = { fg = '#61afef', bold = true },  -- Blue
    RJobsCompleted = { fg = '#98c379', bold = true }, -- Green
    RJobsFailed = { fg = '#e06c75', bold = true },    -- Red
    RJobsCancelled = { fg = '#d19a66', bold = true }, -- Orange
    RJobsHelp = { link = 'Comment', italic = true },
  }
  
  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

-- Helper to truncate string with ellipsis
local function truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 3) .. '...'
end

-- Helper to pad string to exact length
local function pad(str, len)
  local str_len = vim.fn.strdisplaywidth(str)
  if str_len >= len then
    return truncate(str, len)
  end
  return str .. string.rep(' ', len - str_len)
end

-- Render the jobs list
function M.render()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end
  
  local jobs = manager.get_jobs()
  local lines = {}
  local highlights_to_apply = {}
  
  -- Get window width for dynamic sizing
  local win_width = 80  -- default
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    win_width = vim.api.nvim_win_get_width(M.state.win)
  end
  
  -- Calculate column widths dynamically
  local id_width = 4
  local status_width = 14
  local started_width = 10
  local duration_width = 10
  local separator_width = 9  -- │ between columns and padding
  
  -- Name column gets remaining space
  local name_width = math.max(15, win_width - id_width - status_width - started_width - duration_width - separator_width)
  
  -- Total width calculation
  local total_width = id_width + name_width + status_width + started_width + duration_width + separator_width
  
  -- Header line
  local header_text = ' R Background Jobs '
  local header_padding = math.max(0, total_width - 2 - #header_text)
  local left_pad = math.floor(header_padding / 2)
  local right_pad = header_padding - left_pad
  table.insert(lines, '╭' .. string.rep('─', left_pad) .. header_text .. string.rep('─', right_pad) .. '╮')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Column headers
  local header = string.format(
    '│ %s │ %s │ %s │ %s │ %s │',
    pad('ID', id_width),
    pad('Name', name_width),
    pad('Status', status_width),
    pad('Started', started_width),
    pad('Duration', duration_width)
  )
  table.insert(lines, header)
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsHeader'})
  
  -- Separator line
  local separator = string.format(
    '├%s┼%s┼%s┼%s┼%s┤',
    string.rep('─', id_width + 2),
    string.rep('─', name_width + 2),
    string.rep('─', status_width + 2),
    string.rep('─', started_width + 2),
    string.rep('─', duration_width + 2)
  )
  table.insert(lines, separator)
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Job rows
  if #jobs == 0 then
    local empty_msg = 'No jobs yet'
    local empty_padding = math.max(0, total_width - 4 - #empty_msg)
    local empty_left = math.floor(empty_padding / 2)
    local empty_right = empty_padding - empty_left
    table.insert(lines, '│ ' .. string.rep(' ', empty_left) .. empty_msg .. string.rep(' ', empty_right) .. ' │')
  else
    for _, job in ipairs(jobs) do
      local line = string.format(
        '│ %s │ %s │ %s │ %s │ %s │',
        pad(tostring(job.id), id_width),
        pad(job.name, name_width),
        pad(job:get_status_display(), status_width),
        pad(job:get_start_time_str(), started_width),
        pad(job:get_duration_str(), duration_width)
      )
      table.insert(lines, line)
      
      -- Add status-specific highlighting
      local hl_group = 'Normal'
      if job.status == 'running' then
        hl_group = 'RJobsRunning'
      elseif job.status == 'completed' then
        hl_group = 'RJobsCompleted'
      elseif job.status == 'failed' then
        hl_group = 'RJobsFailed'
      elseif job.status == 'cancelled' then
        hl_group = 'RJobsCancelled'
      end
      
      -- Highlight the status column
      table.insert(highlights_to_apply, {
        line = #lines,
        hl_group = hl_group,
        col_start = id_width + name_width + 8,  -- Start of status column
        col_end = id_width + name_width + status_width + 8  -- End of status column
      })
    end
  end
  
  -- Footer separator
  table.insert(lines, '├' .. string.rep('─', total_width - 2) .. '┤')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Help text
  local help_text = '<CR>: view │ d: delete │ c: cancel │ r: refresh │ q: close'
  local help_padding = math.max(0, total_width - 4 - #help_text)
  local help_left = math.floor(help_padding / 2)
  local help_right = help_padding - help_left
  table.insert(lines, '│ ' .. string.rep(' ', help_left) .. help_text .. string.rep(' ', help_right) .. ' │')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsHelp'})
  
  -- Bottom border
  table.insert(lines, '╰' .. string.rep('─', total_width - 2) .. '╯')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Update buffer content
  vim.api.nvim_buf_set_option(M.state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(M.state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.buf, 'modifiable', false)
  
  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace('r-jobs-ui')
  vim.api.nvim_buf_clear_namespace(M.state.buf, ns_id, 0, -1)
  
  for _, hl in ipairs(highlights_to_apply) do
    local line_idx = hl.line - 1  -- 0-based indexing
    local col_start = hl.col_start or 0
    local col_end = hl.col_end or -1
    
    vim.api.nvim_buf_add_highlight(
      M.state.buf,
      ns_id,
      hl.hl_group,
      line_idx,
      col_start,
      col_end
    )
  end
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
  
  -- Add winbar for clear separation
  vim.api.nvim_win_set_option(M.state.win, 'winbar', ' R Background Jobs ')
  
  -- Set window highlight to make it more distinct
  vim.api.nvim_win_set_option(M.state.win, 'winhighlight', 'Normal:Normal,WinBar:RJobsTitle')
  
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
