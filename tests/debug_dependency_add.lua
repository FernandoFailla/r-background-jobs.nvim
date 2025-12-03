-- Debug test for dependency.add()

-- Mock vim global
_G.vim = {
  notify = function(msg, level) print("VIM NOTIFY:", msg) end,
  log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
  api = {
    nvim_get_runtime_file = function() return {} end,
  },
  fn = {
    expand = function(path) return path end,
    fnamemodify = function(path, mod) return path end,
    filereadable = function(path) return 1 end,
  },
  loop = {
    os_uname = function() return { sysname = "Linux" } end,
  },
  deepcopy = function(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end,
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then return true end
    end
    return false
  end,
  inspect = function(t)
    if type(t) ~= 'table' then return tostring(t) end
    local items = {}
    for k, v in pairs(t) do
      table.insert(items, tostring(k) .. "=" .. tostring(v))
    end
    return "{ " .. table.concat(items, ", ") .. " }"
  end,
}

local dependency = require('r-background-jobs.dependency')
local Job = require('r-background-jobs.job')
local manager = require('r-background-jobs.manager')

print("=== Debug Test for dependency.add() ===\n")

-- Reset
manager.jobs = {}

-- Create jobs
local job1 = Job.new(1, "/tmp/test1.R")
job1.status = 'running'
job1.depends_on = {}
job1.dependents = {}
table.insert(manager.jobs, job1)

local job2 = Job.new(2, "/tmp/test2.R")
job2.status = 'running'
job2.depends_on = {}
job2.dependents = {}
table.insert(manager.jobs, job2)

print("Created Job 1:", job1.id, job1.name)
print("Created Job 2:", job2.id, job2.name)
print("Manager has", #manager.jobs, "jobs")

-- Try to add dependency
print("\nCalling dependency.add(2, 1)...")
local success, err = dependency.add(2, 1)

print("Result:", success)
print("Error:", err or "(none)")

if success then
  print("\nJob 2 depends_on:", vim.inspect(job2.depends_on))
  print("Job 1 dependents:", vim.inspect(job1.dependents))
else
  print("\nFailed to add dependency!")
end

-- Check what manager.get_job returns
print("\nTesting manager.get_job(1):")
local retrieved = manager.get_job(1)
print("Retrieved job:", retrieved and retrieved.id or "nil")

print("\nTesting manager.get_job(2):")
local retrieved2 = manager.get_job(2)
print("Retrieved job:", retrieved2 and retrieved2.id or "nil")
