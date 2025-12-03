-- Telescope integration for r-background-jobs.nvim
local manager = require('r-background-jobs.manager')
local utils = require('r-background-jobs.utils')

local M = {}

-- Check if Telescope is available
function M.is_available()
  return pcall(require, 'telescope')
end

-- Show job picker using Telescope
-- @param opts table Options for the picker
-- @param on_select function Callback when job is selected (receives job object)
function M.pick_job(opts, on_select)
  opts = opts or {}
  
  -- Try to use Telescope if available
  if M.is_available() then
    M.telescope_picker(opts, on_select)
  else
    -- Fallback to vim.ui.select
    M.vim_ui_select_picker(opts, on_select)
  end
end

-- Telescope picker implementation
function M.telescope_picker(opts, on_select)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')
  
  local jobs = manager.get_jobs()
  
  if #jobs == 0 then
    vim.notify('No jobs available', vim.log.levels.WARN)
    return
  end
  
  -- Create picker
  pickers.new(opts, {
    prompt_title = 'R Background Jobs',
    finder = finders.new_table({
      results = jobs,
      entry_maker = function(job)
        return {
          value = job,
          display = string.format(
            '[%d] %s - %s (%s)',
            job.id,
            job.name,
            job:get_status_display(),
            job:get_duration_str()
          ),
          ordinal = string.format('%d %s %s', job.id, job.name, job.status),
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = 'Job Output',
      define_preview = function(self, entry)
        local job = entry.value
        
        -- Show job info in preview
        local info_lines = {
          'Job Information:',
          '  ID: ' .. job.id,
          '  Name: ' .. job.name,
          '  Script: ' .. job.script_path,
          '  Status: ' .. job:get_status_display(),
          '  Started: ' .. job:get_start_time_str(),
          '  Duration: ' .. job:get_duration_str(),
          '',
          'Output:',
          string.rep('─', 60),
        }
        
        -- Read output file if available
        if job.output_file and utils.file_exists(job.output_file) then
          local output = utils.read_file(job.output_file)
          if output then
            -- Split into lines
            for line in output:gmatch('[^\r\n]+') do
              table.insert(info_lines, line)
            end
          else
            table.insert(info_lines, '(Failed to read output file)')
          end
        else
          table.insert(info_lines, '(No output file available)')
        end
        
        -- Set preview content
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, info_lines)
        
        -- Set filetype for syntax highlighting
        vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'r')
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        
        if selection and on_select then
          on_select(selection.value)
        end
      end)
      
      return true
    end,
  }):find()
end

-- Fallback vim.ui.select picker
function M.vim_ui_select_picker(opts, on_select)
  local jobs = manager.get_jobs()
  
  if #jobs == 0 then
    vim.notify('No jobs available', vim.log.levels.WARN)
    return
  end
  
  -- Create display items
  local items = {}
  for _, job in ipairs(jobs) do
    table.insert(items, {
      text = string.format(
        '[%d] %s - %s (%s)',
        job.id,
        job.name,
        job:get_status_display(),
        job:get_duration_str()
      ),
      job = job,
    })
  end
  
  vim.ui.select(items, {
    prompt = 'Select job:',
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice and on_select then
      on_select(choice.job)
    end
  end)
end

-- Helper: Pick a job and view its output
function M.pick_and_view_output()
  M.pick_job({}, function(job)
    if not job then
      return
    end
    
    if not job.output_file or not utils.file_exists(job.output_file) then
      vim.notify('Output file not found for job ' .. job.id, vim.log.levels.WARN)
      return
    end
    
    -- Open output in new split
    vim.cmd('rightbelow split ' .. vim.fn.fnameescape(job.output_file))
    vim.api.nvim_buf_set_option(0, 'filetype', 'r')
    vim.api.nvim_buf_set_option(0, 'modifiable', false)
    
    if job:is_running() then
      vim.cmd('normal! G')
    end
  end)
end

-- Helper: Pick a job and cancel it
function M.pick_and_cancel()
  M.pick_job({}, function(job)
    if not job then
      return
    end
    
    if not job:is_running() then
      vim.notify('Job ' .. job.id .. ' is not running', vim.log.levels.WARN)
      return
    end
    
    local success, err = manager.cancel_job(job.id)
    if success then
      vim.notify('Job ' .. job.id .. ' cancelled', vim.log.levels.INFO)
    else
      vim.notify('Failed to cancel job: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end
  end)
end

-- Helper: Pick a job and show its info
function M.pick_and_show_info()
  M.pick_job({}, function(job)
    if not job then
      return
    end
    
    local info = job:get_info()
    local lines = {
      'Job Information:',
      '  ID: ' .. info.id,
      '  Name: ' .. info.name,
      '  Script: ' .. info.script_path,
      '  Status: ' .. info.status,
      '  Started: ' .. info.start_time,
      '  Duration: ' .. info.duration,
      '  Output: ' .. (info.output_file or 'N/A'),
      '  PID: ' .. (info.pid or 'N/A'),
    }
    
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end)
end

return M
