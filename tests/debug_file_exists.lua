-- Quick debug test for file_exists mock

_G.vim = {
  loop = {
    fs_stat = function(path)
      print("fs_stat called with:", path)
      if path:match("%.R$") or path:match("%.r$") then
        print("  Returning file stat")
        return { type = 'file', size = 100 }
      end
      print("  Returning nil")
      return nil
    end,
  },
  fn = {
    fnamemodify = function(path, mod)
      if mod == ':e' then
        return path:match("%.(%w+)$") or ""
      end
      return path
    end,
  },
}

local utils = require('r-background-jobs.utils')

print("\nTesting file_exists:")
local exists = utils.file_exists("/path/to/script.R")
print("Result:", exists)

print("\nTesting validate_script_path:")
local valid, err = utils.validate_script_path("/path/to/script.R")
print("Valid:", valid)
print("Error:", err)
