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
  
  -- Runtime column widths (can be adjusted interactively)
  column_widths = nil,  -- Will be initialized from config
}

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
    RJobsPending = { fg = '#e5c07b', bold = true },   -- Yellow
    RJobsSkipped = { fg = '#abb2bf', bold = true },   -- Gray
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
  
  -- Resize columns
  vim.keymap.set('n', '[', function()
    M.decrease_column_width()
  end, opts)
  
  vim.keymap.set('n', ']', function()
    M.increase_column_width()
  end, opts)
  
  -- Reset column widths to default
  vim.keymap.set('n', '=', function()
    M.reset_column_widths()
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

-- Identify which column the cursor is currently in
-- Returns: column name or nil
local function identify_column_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col('.') - 1  -- 0-based
  
  -- Skip if not in a data row (check for │ at start)
  if not line:match('^│') then
    return nil
  end
  
  -- Calculate column positions based on current widths
  local widths = M.state.column_widths
  if not widths then return nil end
  
  local pos = 2  -- Start after "│ "
  local columns = {'id', 'pipeline', 'name', 'status', 'depends', 'started', 'duration'}
  
  for _, col_name in ipairs(columns) do
    local col_width = widths[col_name]
    local col_end = pos + col_width + 3  -- +3 for " │ "
    
    if col >= pos and col < col_end then
      return col_name
    end
    
    pos = col_end
  end
  
  return nil
end

-- Helper to build pipeline display string
local function build_pipeline_display(job)
  if not job.pipeline_name then
    return '-'
  end
  
  -- Calculate pipeline position if available
  if job.pipeline_position and job.pipeline_total then
    return string.format('[%s] %d/%d', job.pipeline_name, job.pipeline_position, job.pipeline_total)
  else
    return string.format('[%s]', job.pipeline_name)
  end
end

-- Helper to build depends display string
local function build_depends_display(job)
  if not job.depends_on or #job.depends_on == 0 then
    return '-'
  end
  
  -- Show as "→ #1,#2,#3"
  local ids = {}
  for _, id in ipairs(job.depends_on) do
    table.insert(ids, '#' .. tostring(id))
  end
  return '→ ' .. table.concat(ids, ',')
end

-- Helper to build indented name with pipeline hierarchy
local function build_name_with_indent(job, all_jobs)
  local name = job.name
  
  -- Calculate indentation based on dependency depth
  if job.depends_on and #job.depends_on > 0 then
    -- Find the maximum depth by traversing dependencies
    local depth = 0
    local visited = {}
    
    local function calc_depth(job_id, current_depth)
      if visited[job_id] then
        return current_depth
      end
      visited[job_id] = true
      
      local j = nil
      for _, jj in ipairs(all_jobs) do
        if jj.id == job_id then
          j = jj
          break
        end
      end
      
      if not j or not j.depends_on or #j.depends_on == 0 then
        return current_depth
      end
      
      local max_depth = current_depth
      for _, dep_id in ipairs(j.depends_on) do
        local d = calc_depth(dep_id, current_depth + 1)
        if d > max_depth then
          max_depth = d
        end
      end
      return max_depth
    end
    
    depth = calc_depth(job.id, 0)
    
    -- Add indentation (2 spaces per level) and tree character
    if depth > 0 then
      local indent = string.rep('  ', depth)
      name = indent .. '└─ ' .. name
    end
  end
  
  return name
end

-- Render the jobs list
function M.render()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end
  
  local jobs = manager.get_jobs()
  local lines = {}
  local highlights_to_apply = {}
  
  -- Get configuration
  local cfg = config.get()
  
  -- Initialize column widths from config if not set
  if not M.state.column_widths then
    M.state.column_widths = vim.deepcopy(cfg.ui.column_widths or {
      id = 4,
      pipeline = 16,
      name = 30,
      status = 12,
      depends = 12,
      started = 10,
      duration = 10,
    })
  end
  
  -- Use runtime column widths (can be adjusted by user)
  local id_width = M.state.column_widths.id
  local pipeline_width = M.state.column_widths.pipeline
  local name_width = M.state.column_widths.name
  local status_width = M.state.column_widths.status
  local depends_width = M.state.column_widths.depends
  local started_width = M.state.column_widths.started
  local duration_width = M.state.column_widths.duration
  
  -- Calculate overhead: 8 pipes (│) + 14 padding spaces (2 per column × 7 columns)
  local OVERHEAD = 22
  
  -- Calculate total width of all columns
  local fixed_cols_width = id_width + pipeline_width + status_width + depends_width + started_width + duration_width
  
  -- Total width calculation
  local total_width = fixed_cols_width + name_width + OVERHEAD
  
  -- Header line
  local header_text = ' R Background Jobs '
  local header_padding = math.max(0, total_width - 2 - #header_text)
  local left_pad = math.floor(header_padding / 2)
  local right_pad = header_padding - left_pad
  table.insert(lines, '╭' .. string.rep('─', left_pad) .. header_text .. string.rep('─', right_pad) .. '╮')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Column headers
  local header = string.format(
    '│ %s │ %s │ %s │ %s │ %s │ %s │ %s │',
    pad('ID', id_width),
    pad('Pipeline', pipeline_width),
    pad('Name', name_width),
    pad('Status', status_width),
    pad('Depends', depends_width),
    pad('Started', started_width),
    pad('Duration', duration_width)
  )
  table.insert(lines, header)
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsHeader'})
  
  -- Separator line
  local separator = string.format(
    '├%s┼%s┼%s┼%s┼%s┼%s┼%s┤',
    string.rep('─', id_width + 2),
    string.rep('─', pipeline_width + 2),
    string.rep('─', name_width + 2),
    string.rep('─', status_width + 2),
    string.rep('─', depends_width + 2),
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
        '│ %s │ %s │ %s │ %s │ %s │ %s │ %s │',
        pad(tostring(job.id), id_width),
        pad(build_pipeline_display(job), pipeline_width),
        pad(build_name_with_indent(job, jobs), name_width),
        pad(job:get_status_display(), status_width),
        pad(build_depends_display(job), depends_width),
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
      elseif job.status == 'pending' then
        hl_group = 'RJobsPending'
      elseif job.status == 'skipped' then
        hl_group = 'RJobsSkipped'
      end
      
      -- Highlight the status column
      local status_col_start = id_width + pipeline_width + name_width + 12
      table.insert(highlights_to_apply, {
        line = #lines,
        hl_group = hl_group,
        col_start = status_col_start,
        col_end = status_col_start + status_width
      })
    end
  end
  
  -- Footer separator
  table.insert(lines, '├' .. string.rep('─', total_width - 2) .. '┤')
  table.insert(highlights_to_apply, {line = #lines, hl_group = 'RJobsBorder'})
  
  -- Help text
  local help_text = '<CR>: view │ [/]: resize │ =: reset │ r: refresh │ q: close'
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
    'Column Resizing:',
    '  [     - Decrease column width',
    '  ]     - Increase column width',
    '  =     - Reset all columns to default',
    '',
    'Press any key to close...',
  }
  
  vim.notify(table.concat(help, '\n'), vim.log.levels.INFO)
end

-- Increase column width under cursor
function M.increase_column_width()
  local col_name = identify_column_at_cursor()
  
  if not col_name then
    vim.notify('Position cursor on a column to resize', vim.log.levels.WARN)
    return
  end
  
  -- Increase width by 2
  M.state.column_widths[col_name] = M.state.column_widths[col_name] + 2
  
  -- Show feedback
  vim.notify(
    string.format('Column "%s" width: %d', col_name, M.state.column_widths[col_name]),
    vim.log.levels.INFO
  )
  
  -- Re-render
  M.refresh()
end

-- Decrease column width under cursor
function M.decrease_column_width()
  local col_name = identify_column_at_cursor()
  
  if not col_name then
    vim.notify('Position cursor on a column to resize', vim.log.levels.WARN)
    return
  end
  
  -- Minimum width is 4
  if M.state.column_widths[col_name] <= 4 then
    vim.notify('Column already at minimum width (4)', vim.log.levels.WARN)
    return
  end
  
  -- Decrease width by 2
  M.state.column_widths[col_name] = M.state.column_widths[col_name] - 2
  
  -- Show feedback
  vim.notify(
    string.format('Column "%s" width: %d', col_name, M.state.column_widths[col_name]),
    vim.log.levels.INFO
  )
  
  -- Re-render
  M.refresh()
end

-- Reset column widths to config defaults
function M.reset_column_widths()
  local cfg = config.get()
  M.state.column_widths = vim.deepcopy(cfg.ui.column_widths or {
    id = 4,
    pipeline = 16,
    name = 30,
    status = 12,
    depends = 12,
    started = 10,
    duration = 10,
  })
  
  vim.notify('Column widths reset to defaults', vim.log.levels.INFO)
  
  -- Re-render
  M.refresh()
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
