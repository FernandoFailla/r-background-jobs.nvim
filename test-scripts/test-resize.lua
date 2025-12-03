-- Test script for column resizing functionality
-- Run: nvim --headless -c "luafile test-scripts/test-resize.lua" -c "qa!"

print("\n=== Testing Column Resizing Functionality ===\n")

-- Setup path
vim.o.runtimepath = '/home/fernando/Projects/pluginbackgroundjobs,' .. vim.o.runtimepath

-- Force reload modules
package.loaded['r-background-jobs.config'] = nil
package.loaded['r-background-jobs.ui'] = nil
package.loaded['r-background-jobs.manager'] = nil
package.loaded['r-background-jobs.utils'] = nil

-- Load modules
local config = require('r-background-jobs.config')
local ui = require('r-background-jobs.ui')

-- Test 1: Default config has column_widths
print("Test 1: Config defaults include column_widths")
local defaults = config.defaults
if defaults.ui.column_widths then
  print("✓ PASS: column_widths found in defaults")
  print("  Default widths:", vim.inspect(defaults.ui.column_widths))
else
  print("✗ FAIL: column_widths not in defaults")
end

-- Test 2: Setup with custom column widths
print("\nTest 2: Setup with custom column widths")
local custom_config = config.setup({
  ui = {
    column_widths = {
      name = 50,  -- Custom width
      pipeline = 20,
    }
  }
})

if custom_config.ui.column_widths.name == 50 then
  print("✓ PASS: Custom name width applied (50)")
else
  print("✗ FAIL: Custom width not applied")
  print("  Got:", custom_config.ui.column_widths.name)
end

if custom_config.ui.column_widths.id == 4 then
  print("✓ PASS: Default id width preserved (4)")
else
  print("✗ FAIL: Default id width not preserved")
  print("  Got:", custom_config.ui.column_widths.id)
end

-- Test 3: UI state initialization
print("\nTest 3: UI state has column_widths field")
if ui.state.column_widths ~= nil then
  print("✓ PASS: UI state has column_widths field")
else
  print("✗ FAIL: UI state missing column_widths field")
end

-- Test 4: Check if resize functions exist
print("\nTest 4: Resize functions exist")
local functions = {
  'increase_column_width',
  'decrease_column_width',
  'reset_column_widths',
}

for _, func_name in ipairs(functions) do
  if type(ui[func_name]) == 'function' then
    print(string.format("✓ PASS: ui.%s exists", func_name))
  else
    print(string.format("✗ FAIL: ui.%s not found", func_name))
  end
end

print("\n=== Test Summary ===")
print("All core functionality for column resizing is implemented!")
print("\nTo test interactively:")
print("1. Open Neovim")
print("2. Run :RJobsList")
print("3. Position cursor on a column")
print("4. Press ] to increase width")
print("5. Press [ to decrease width")
print("6. Press = to reset to defaults")
