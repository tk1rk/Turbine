# ⚡ Turbine

A blazingly fast, asynchronous plugin manager for Neovim with intelligent caching and advanced lazy loading.

## ✨ Features

- **⚡ Lightning Fast**: True async operations using libuv with concurrent job processing
- **🧠 Intelligent Caching**: TTL-based cache system with automatic invalidation
- **🔄 Lazy Loading**: Load plugins on events, commands, filetypes, or keymaps
- **🎯 Parallel Operations**: Install/update multiple plugins simultaneously with configurable concurrency
- **📦 Smart Git**: Shallow clones, branch support, and commit tracking
- **🛡️ Robust Error Handling**: Graceful failures with detailed error reporting
- **🧹 Auto Cleanup**: Remove unused plugins automatically
- **📊 Status Monitoring**: Real-time plugin status and diagnostics

## 📋 Requirements

- Neovim ≥ 0.9.0
- Git

## 🚀 Installation

### Bootstrap Installation

Add this to your `init.lua` before any plugin configuration:

```lua
-- Bootstrap Turbine
local turbine_path = vim.fn.stdpath("data") .. "/turbine/plugins/turbine"
if vim.fn.isdirectory(turbine_path) == 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/yourusername/turbine.nvim",
    turbine_path,
  })
end
vim.opt.rtp:prepend(turbine_path)
```

## ⚙️ Configuration

### Basic Setup

```lua
local turbine = require('turbine')

-- Setup with default options
turbine.setup()

-- Add your plugins
turbine.add({
  ['plenary.nvim'] = 'nvim-lua/plenary.nvim',
  ['telescope.nvim'] = 'nvim-telescope/telescope.nvim',
})

-- Install and load
turbine.install(function()
  turbine.load()
end)
```

### Advanced Configuration

```lua
local turbine = require('turbine')

turbine.setup({
  root = vim.fn.stdpath("data") .. "/turbine",  -- Installation directory
  git_timeout = 60000,                          -- Git operation timeout (ms)
  max_concurrent_jobs = 10,                     -- Max parallel operations
  cache_ttl = 3600,                             -- Cache lifetime (seconds)
  lazy_load = true,                             -- Enable lazy loading
  auto_sync = false,                            -- Auto-sync on startup
})
```

## 📚 Usage

### Adding Plugins

#### Simple Plugin

```lua
turbine.add({
  ['plugin-name'] = 'username/repo'
})
```

#### Plugin with Branch

```lua
turbine.add({
  ['plugin-name'] = {
    url = 'username/repo',
    branch = 'develop'
  }
})
```

#### Plugin with Configuration

```lua
turbine.add({
  ['nvim-treesitter'] = {
    url = 'nvim-treesitter/nvim-treesitter',
    config = function()
      require('nvim-treesitter.configs').setup({
        highlight = { enable = true },
        indent = { enable = true }
      })
    end
  }
})
```

### Lazy Loading

#### Load on Event

```lua
turbine.add({
  ['gitsigns.nvim'] = {
    url = 'lewis6991/gitsigns.nvim',
    event = 'BufReadPost',  -- Single event
    -- OR
    event = {'BufReadPost', 'BufNewFile'},  -- Multiple events
    config = function()
      require('gitsigns').setup()
    end
  }
})
```

#### Load on Filetype

```lua
turbine.add({
  ['rust-tools.nvim'] = {
    url = 'simrat39/rust-tools.nvim',
    ft = 'rust',  -- Single filetype
    -- OR
    ft = {'rust', 'toml'},  -- Multiple filetypes
  }
})
```

#### Load on Command

```lua
turbine.add({
  ['trouble.nvim'] = {
    url = 'folke/trouble.nvim',
    cmd = 'Trouble',  -- Single command
    -- OR
    cmd = {'Trouble', 'TroubleToggle'},  -- Multiple commands
  }
})
```

#### Load on Keymap

```lua
turbine.add({
  ['which-key.nvim'] = {
    url = 'folke/which-key.nvim',
    keys = '<leader>',  -- Single key
    -- OR
    keys = {'<leader>', '<C-w>'},  -- Multiple keys
  }
})
```

#### Disable Lazy Loading

```lua
turbine.add({
  ['critical-plugin'] = {
    url = 'username/critical-plugin',
    lazy = false  -- Load immediately on startup
  }
})
```

### Complete Example

```lua
local turbine = require('turbine')

turbine.setup({
  max_concurrent_jobs = 15,
  cache_ttl = 1800,
})

turbine.add({
  -- Core dependencies (load immediately)
  ['plenary.nvim'] = {
    url = 'nvim-lua/plenary.nvim',
    lazy = false
  },

  -- UI plugins (load on event)
  ['telescope.nvim'] = {
    url = 'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    config = function()
      require('telescope').setup()
    end
  },

  -- LSP (load on filetype)
  ['nvim-lspconfig'] = {
    url = 'neovim/nvim-lspconfig',
    ft = {'lua', 'python', 'javascript'},
    config = function()
      require('lspconfig').lua_ls.setup({})
    end
  },

  -- Git integration (load on command)
  ['fugitive'] = {
    url = 'tpope/vim-fugitive',
    cmd = {'Git', 'Gdiff', 'Gblame'}
  },

  -- Keybinding helper (load on keymap)
  ['which-key.nvim'] = {
    url = 'folke/which-key.nvim',
    keys = '<leader>',
    config = function()
      require('which-key').setup()
    end
  },

  -- Syntax highlighting (load on buffer open)
  ['nvim-treesitter'] = {
    url = 'nvim-treesitter/nvim-treesitter',
    event = {'BufReadPost', 'BufNewFile'},
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {'lua', 'vim', 'vimdoc'},
        highlight = { enable = true }
      })
    end
  }
})

-- Install missing plugins and load
turbine.install(function(results)
  turbine.load()
end)
```

## 🔧 Commands

Turbine provides the following commands:

| Command | Description |
|---------|-------------|
| `:TurbineInstall` | Install all configured plugins |
| `:TurbineUpdate` | Update all installed plugins |
| `:TurbineClean` | Remove plugins not in config |
| `:TurbineStatus` | Show plugin status and info |

## 🔌 API Reference

### `turbine.setup(opts)`

Initialize Turbine with custom options.

**Parameters:**
- `opts` (table, optional): Configuration options

**Default options:**
```lua
{
  root = vim.fn.stdpath("data") .. "/turbine",
  git_timeout = 60000,
  max_concurrent_jobs = 10,
  cache_ttl = 3600,
  lazy_load = true,
  auto_sync = false,
}
```

### `turbine.add(plugins)`

Register plugins with Turbine.

**Parameters:**
- `plugins` (table): Dictionary of plugin name → plugin spec

**Plugin spec fields:**
- `url` or `[1]` (string): Git repository URL (required)
- `branch` (string): Git branch to use
- `lazy` (boolean): Disable lazy loading (default: true)
- `event` (string|table): Load on event(s)
- `cmd` (string|table): Load on command(s)
- `ft` (string|table): Load on filetype(s)
- `keys` (string|table): Load on keymap(s)
- `config` (function): Configuration function

### `turbine.install(callback)`

Install all registered plugins.

**Parameters:**
- `callback` (function, optional): Called when installation completes

**Callback receives:**
- `results` (table): Dictionary of plugin name → {success: bool, message: string}

### `turbine.update(callback)`

Update all installed plugins.

**Parameters:**
- `callback` (function, optional): Called when update completes

### `turbine.load()`

Load all plugins according to their lazy loading configuration.

### `turbine.status()`

Get detailed status of all plugins.

**Returns:**
- `status` (table): Dictionary of plugin name → status info

### `turbine.clean(callback)`

Remove plugins not in configuration.

**Parameters:**
- `callback` (function, optional): Called with list of removed plugins

## 🎯 Performance Tips

1. **Increase Concurrency**: For faster operations, increase `max_concurrent_jobs`:
   ```lua
   turbine.setup({ max_concurrent_jobs = 20 })
   ```

2. **Optimize Cache TTL**: Adjust cache lifetime based on your workflow:
   ```lua
   turbine.setup({ cache_ttl = 7200 })  -- 2 hours
   ```

3. **Strategic Lazy Loading**: Use the most specific trigger for each plugin:
   - Use `ft` for language-specific plugins
   - Use `cmd` for utility plugins
   - Use `event` for UI plugins
   - Use `keys` for keymap-heavy plugins

4. **Batch Operations**: Group related plugins together for better caching

## 🆚 Comparison with Other Plugin Managers

| Feature | Turbine | lazy.nvim | packer.nvim |
|---------|---------|-----------|-------------|
| True Async | ✅ | ✅ | ❌ |
| Concurrent Jobs | ✅ (Configurable) | ✅ (Fixed) | ❌ |
| TTL Caching | ✅ | ❌ | ❌ |
| Job Queue | ✅ | ❌ | ❌ |
| Event Loading | ✅ | ✅ | ✅ |
| Command Loading | ✅ | ✅ | ✅ |
| Keymap Loading | ✅ | ✅ | ❌ |
| Commit Tracking | ✅ | ✅ | ❌ |
| Status API | ✅ | ✅ | ✅ |

## 🐛 Troubleshooting

### Plugins Not Loading

Check if lazy loading is interfering:
```vim
:TurbineStatus
```

Force immediate loading:
```lua
turbine.add({
  ['plugin-name'] = {
    url = 'username/repo',
    lazy = false
  }
})
```

### Slow Installation

Increase concurrent jobs:
```lua
turbine.setup({ max_concurrent_jobs = 20 })
```

### Cache Issues

Clear the cache:
```lua
vim.fn.delete(vim.fn.stdpath("data") .. "/turbine/cache", "rf")
```

## 📝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

Inspired by lazy.nvim and packer.nvim, built to push the boundaries of plugin manager performance.
