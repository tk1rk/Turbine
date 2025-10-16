-- Turbine: A high-performance, asynchronous Neovim plugin manager
-- Features: Async operations, intelligent caching, lazy loading, parallel processing

local M = {}
local uv = vim.loop
local api = vim.api
local fn = vim.fn

-- Core configuration
M.config = {
  root = vim.fn.stdpath("data") .. "/turbine",
  git_timeout = 60000,
  max_concurrent_jobs = 10,
  cache_ttl = 3600, -- 1 hour
  lazy_load = true,
  auto_sync = false,
}

-- State management
local state = {
  plugins = {},
  jobs = {},
  cache = {},
  loaded = {},
  job_queue = {},
  active_jobs = 0,
}

-- Utility functions
local function log(level, msg, ...)
  vim.notify(string.format("[Turbine] " .. msg, ...), level)
end

local function ensure_dir(path)
  if fn.isdirectory(path) == 0 then
    fn.mkdir(path, "p")
  end
end

local function file_exists(path)
  return fn.filereadable(path) == 1
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(content)
  file:close()
  return true
end

-- Cache management with TTL
local function get_cache_path(key)
  return M.config.root .. "/cache/" .. key .. ".json"
end

local function cache_get(key)
  local cache_file = get_cache_path(key)
  if not file_exists(cache_file) then return nil end
  
  local content = read_file(cache_file)
  if not content then return nil end
  
  local ok, data = pcall(vim.json.decode, content)
  if not ok then return nil end
  
  -- Check TTL
  if data.timestamp and (os.time() - data.timestamp) > M.config.cache_ttl then
    os.remove(cache_file)
    return nil
  end
  
  return data.value
end

local function cache_set(key, value)
  ensure_dir(M.config.root .. "/cache")
  local cache_file = get_cache_path(key)
  local data = {
    value = value,
    timestamp = os.time()
  }
  write_file(cache_file, vim.json.encode(data))
end

-- Async job runner with queue management
local function run_job(cmd, cwd, on_complete, on_error)
  if state.active_jobs >= M.config.max_concurrent_jobs then
    table.insert(state.job_queue, {cmd, cwd, on_complete, on_error})
    return
  end

  state.active_jobs = state.active_jobs + 1
  
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()
  local output = {}
  local errors = {}

  local handle
  handle = uv.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    cwd = cwd,
    stdio = {nil, stdout, stderr}
  }, function(code, signal)
    stdout:close()
    stderr:close()
    handle:close()
    
    state.active_jobs = state.active_jobs - 1
    
    -- Process next job in queue
    if #state.job_queue > 0 then
      local next_job = table.remove(state.job_queue, 1)
      vim.schedule(function()
        run_job(unpack(next_job))
      end)
    end
    
    vim.schedule(function()
      if code == 0 then
        if on_complete then on_complete(table.concat(output)) end
      else
        if on_error then on_error(table.concat(errors)) end
      end
    end)
  end)

  if not handle then
    state.active_jobs = state.active_jobs - 1
    if on_error then on_error("Failed to spawn process") end
    return
  end

  stdout:read_start(function(err, data)
    if data then table.insert(output, data) end
  end)

  stderr:read_start(function(err, data)
    if data then table.insert(errors, data) end
  end)
end

-- Git operations
local function git_clone(url, path, branch, on_complete, on_error)
  local cmd = {"git", "clone", "--depth=1"}
  if branch and branch ~= "main" and branch ~= "master" then
    table.insert(cmd, "--branch")
    table.insert(cmd, branch)
  end
  table.insert(cmd, url)
  table.insert(cmd, path)
  
  run_job(cmd, nil, on_complete, on_error)
end

local function git_pull(path, on_complete, on_error)
  run_job({"git", "pull", "--ff-only"}, path, on_complete, on_error)
end

local function git_get_commit(path, on_complete)
  run_job({"git", "rev-parse", "HEAD"}, path, function(output)
    on_complete(vim.trim(output))
  end)
end

-- Plugin installation and management
local function install_plugin(name, spec, callback)
  local plugin_path = M.config.root .. "/plugins/" .. name
  
  if fn.isdirectory(plugin_path) == 1 then
    if callback then callback(true, "Already installed") end
    return
  end
  
  ensure_dir(M.config.root .. "/plugins")
  
  local url = spec.url or spec[1]
  if not url then
    if callback then callback(false, "No URL specified") end
    return
  end
  
  log(vim.log.levels.INFO, "Installing %s...", name)
  
  git_clone(url, plugin_path, spec.branch, function()
    -- Cache plugin info
    git_get_commit(plugin_path, function(commit)
      cache_set("plugin_" .. name, {
        url = url,
        commit = commit,
        installed_at = os.time()
      })
    end)
    
    log(vim.log.levels.INFO, "Installed %s", name)
    if callback then callback(true, "Installed") end
  end, function(err)
    log(vim.log.levels.ERROR, "Failed to install %s: %s", name, err)
    if callback then callback(false, err) end
  end)
end

local function update_plugin(name, spec, callback)
  local plugin_path = M.config.root .. "/plugins/" .. name
  
  if fn.isdirectory(plugin_path) == 0 then
    install_plugin(name, spec, callback)
    return
  end
  
  log(vim.log.levels.INFO, "Updating %s...", name)
  
  git_pull(plugin_path, function()
    git_get_commit(plugin_path, function(commit)
      cache_set("plugin_" .. name, {
        url = spec.url or spec[1],
        commit = commit,
        updated_at = os.time()
      })
    end)
    
    log(vim.log.levels.INFO, "Updated %s", name)
    if callback then callback(true, "Updated") end
  end, function(err)
    log(vim.log.levels.ERROR, "Failed to update %s: %s", name, err)
    if callback then callback(false, err) end
  end)
end

-- Lazy loading system
local function should_load_plugin(name, spec)
  if spec.lazy == false then return true end
  if not M.config.lazy_load then return true end
  if state.loaded[name] then return false end
  
  -- Check load conditions
  if spec.event then return false end -- Will be loaded on event
  if spec.cmd then return false end -- Will be loaded on command
  if spec.ft then return false end -- Will be loaded on filetype
  if spec.keys then return false end -- Will be loaded on keymap
  
  return true -- Load immediately if no lazy conditions
end

local function load_plugin(name, spec)
  if state.loaded[name] then return end
  
  local plugin_path = M.config.root .. "/plugins/" .. name
  if fn.isdirectory(plugin_path) == 0 then return end
  
  -- Add to runtimepath
  vim.opt.rtp:prepend(plugin_path)
  
  -- Source plugin files
  local plugin_file = plugin_path .. "/plugin/**/*.vim"
  local lua_file = plugin_path .. "/plugin/**/*.lua"
  
  for _, file in ipairs(fn.glob(plugin_file, true, true)) do
    vim.cmd("source " .. file)
  end
  
  for _, file in ipairs(fn.glob(lua_file, true, true)) do
    dofile(file)
  end
  
  -- Run config function
  if spec.config and type(spec.config) == "function" then
    spec.config()
  end
  
  state.loaded[name] = true
  log(vim.log.levels.INFO, "Loaded %s", name)
end

-- Event system for lazy loading
local function setup_lazy_loading()
  local function create_autocmd(event, pattern, callback)
    api.nvim_create_autocmd(event, {
      pattern = pattern,
      callback = callback,
      once = true
    })
  end
  
  for name, spec in pairs(state.plugins) do
    if not should_load_plugin(name, spec) then
      -- Event-based loading
      if spec.event then
        local events = type(spec.event) == "table" and spec.event or {spec.event}
        for _, event in ipairs(events) do
          create_autocmd(event, "*", function()
            load_plugin(name, spec)
          end)
        end
      end
      
      -- Filetype-based loading
      if spec.ft then
        local filetypes = type(spec.ft) == "table" and spec.ft or {spec.ft}
        create_autocmd("FileType", filetypes, function()
          load_plugin(name, spec)
        end)
      end
      
      -- Command-based loading
      if spec.cmd then
        local commands = type(spec.cmd) == "table" and spec.cmd or {spec.cmd}
        for _, cmd in ipairs(commands) do
          api.nvim_create_user_command(cmd, function()
            load_plugin(name, spec)
            vim.cmd(cmd)
          end, {})
        end
      end
      
      -- Key-based loading
      if spec.keys then
        local keys = type(spec.keys) == "table" and spec.keys or {spec.keys}
        for _, key in ipairs(keys) do
          local map_opts = {
            callback = function()
              load_plugin(name, spec)
              -- Re-trigger the keymap
              api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, true, true), "n", false)
            end
          }
          vim.keymap.set("n", key, "", map_opts)
        end
      end
    end
  end
end

-- Public API
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  ensure_dir(M.config.root)
  
  -- Load plugin specs from cache
  local cached_specs = cache_get("plugin_specs")
  if cached_specs then
    state.plugins = cached_specs
  end
end

function M.add(plugins)
  for name, spec in pairs(plugins) do
    if type(spec) == "string" then
      spec = {url = spec}
    end
    state.plugins[name] = spec
  end
  
  -- Cache plugin specs
  cache_set("plugin_specs", state.plugins)
end

function M.install(callback)
  local total = 0
  local completed = 0
  local results = {}
  
  for name, _ in pairs(state.plugins) do
    total = total + 1
  end
  
  if total == 0 then
    log(vim.log.levels.INFO, "No plugins to install")
    if callback then callback(results) end
    return
  end
  
  for name, spec in pairs(state.plugins) do
    install_plugin(name, spec, function(success, message)
      completed = completed + 1
      results[name] = {success = success, message = message}
      
      if completed == total then
        log(vim.log.levels.INFO, "Installation complete: %d/%d", completed, total)
        if callback then callback(results) end
      end
    end)
  end
end

function M.update(callback)
  local total = 0
  local completed = 0
  local results = {}
  
  for name, _ in pairs(state.plugins) do
    total = total + 1
  end
  
  if total == 0 then
    log(vim.log.levels.INFO, "No plugins to update")
    if callback then callback(results) end
    return
  end
  
  for name, spec in pairs(state.plugins) do
    update_plugin(name, spec, function(success, message)
      completed = completed + 1
      results[name] = {success = success, message = message}
      
      if completed == total then
        log(vim.log.levels.INFO, "Update complete: %d/%d", completed, total)
        if callback then callback(results) end
      end
    end)
  end
end

function M.load()
  -- Load non-lazy plugins immediately
  for name, spec in pairs(state.plugins) do
    if should_load_plugin(name, spec) then
      load_plugin(name, spec)
    end
  end
  
  -- Setup lazy loading for the rest
  setup_lazy_loading()
end

function M.status()
  local status = {}
  for name, spec in pairs(state.plugins) do
    local plugin_path = M.config.root .. "/plugins/" .. name
    local installed = fn.isdirectory(plugin_path) == 1
    local loaded = state.loaded[name] or false
    local cached_info = cache_get("plugin_" .. name)
    
    status[name] = {
      installed = installed,
      loaded = loaded,
      url = spec.url or spec[1],
      commit = cached_info and cached_info.commit,
      lazy = spec.lazy ~= false and M.config.lazy_load
    }
  end
  return status
end

function M.clean(callback)
  local plugin_dir = M.config.root .. "/plugins"
  local installed_plugins = {}
  
  -- Get list of installed plugins
  for name in vim.fs.dir(plugin_dir) do
    if fn.isdirectory(plugin_dir .. "/" .. name) == 1 then
      table.insert(installed_plugins, name)
    end
  end
  
  local to_remove = {}
  for _, name in ipairs(installed_plugins) do
    if not state.plugins[name] then
      table.insert(to_remove, name)
    end
  end
  
  if #to_remove == 0 then
    log(vim.log.levels.INFO, "No plugins to clean")
    if callback then callback({}) end
    return
  end
  
  for _, name in ipairs(to_remove) do
    local plugin_path = plugin_dir .. "/" .. name
    fn.delete(plugin_path, "rf")
    log(vim.log.levels.INFO, "Removed %s", name)
  end
  
  if callback then callback(to_remove) end
end

-- Commands
local function create_commands()
  api.nvim_create_user_command("TurbineInstall", function()
    M.install()
  end, {desc = "Install plugins"})
  
  api.nvim_create_user_command("TurbineUpdate", function()
    M.update()
  end, {desc = "Update plugins"})
  
  api.nvim_create_user_command("TurbineClean", function()
    M.clean()
  end, {desc = "Clean unused plugins"})
  
  api.nvim_create_user_command("TurbineStatus", function()
    local status = M.status()
    local lines = {"# Turbine Status", ""}
    
    for name, info in pairs(status) do
      local line = string.format("- %s: %s%s%s", 
        name,
        info.installed and "✓" or "✗",
        info.loaded and " (loaded)" or "",
        info.lazy and " (lazy)" or ""
      )
      table.insert(lines, line)
    end
    
    api.nvim_echo({{table.concat(lines, "\n"), "Normal"}}, true, {})
  end, {desc = "Show plugin status"})
end

-- Auto-setup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    create_commands()
  end,
  once = true
})

return M
