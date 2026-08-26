local utils = require "will.utils"
local packadd = utils.packadd

---@diagnostic disable: missing-fields

-- diffview picks its VCS adapter when a command runs, trying git before jj, so in a
-- colocated repo git wins. Only the history panel wants jj, for change IDs and jj
-- commit stats: jujutsu.nvim shells out to `DiffviewOpen <sha>^!`, git revspec syntax
-- that jj cannot parse, so global detection has to stay on git.
local function jj_file_history(paths)
  local config = require("diffview.config").get_config()
  local previous = config.preferred_adapter
  config.preferred_adapter = "jj"
  local ok, err = pcall(vim.cmd, "DiffviewFileHistory " .. paths)
  config.preferred_adapter = previous
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

---@type lz.n.Spec
return {
  {
    "which-key.nvim", -- https://github.com/folke/which-key.nvim
    event = "DeferredUIEnter",
    after = function() require("which-key").setup { preset = "modern" } end,
  },

  {
    "telescope.nvim", -- https://github.com/nvim-telescope/telescope.nvim
    cmd = "Telescope",
    before = function()
      packadd "plenary.nvim"
      packadd "telescope-zf-native.nvim"
    end,
    after = function()
      local actions = require "telescope.actions"
      local action_state = require "telescope.actions.state"

      -- ripgrep's --hidden is baked into the finder's command when the picker is
      -- built, so flipping it means relaunching the picker with the prompt,
      -- directory and title carried across. Sticky for the rest of the session.
      --
      -- live_grep only: a picker does not keep the opts it was built from, and
      -- grep_string's search term is one of them, so relaunching it would silently
      -- re-search vim.fn.expand "<cword>" of whatever buffer we closed back to.
      local grep_hidden = false
      local function toggle_grep_hidden(prompt_bufnr)
        grep_hidden = not grep_hidden
        local picker = action_state.get_current_picker(prompt_bufnr)
        local title = picker.prompt_title:gsub(" %(hidden%)$", "")
        local opts = {
          hidden = grep_hidden,
          default_text = action_state.get_current_line(),
          cwd = picker.cwd,
          prompt_title = grep_hidden and title .. " (hidden)" or title,
        }
        actions.close(prompt_bufnr)
        require("telescope.builtin").live_grep(opts)
      end

      require("telescope").setup {
        pickers = {
          live_grep = {
            mappings = { i = { ["<M-h>"] = toggle_grep_hidden }, n = { ["<M-h>"] = toggle_grep_hidden } },
          },
        },
        defaults = {
          prompt_prefix = " ",
          selection_caret = " ",
          path_display = { shorten = { len = 3, exclude = { 1, 2, -1 } } },

          extensions = { live_grep_args = { auto_quoting = true } },

          mappings = {
            i = {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
            },
          },
        },
      }
      require("telescope").load_extension "zf-native"
    end,
    keys = {
      { "<leader>ss", "<cmd>Telescope resume<cr>", desc = "Resume" },
      { "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "Files" },
      { "<leader>sb", "<cmd>Telescope git_branches<cr>", desc = "Checkout branch" },
      { "<leader>st", "<cmd>Telescope live_grep<cr>", desc = "Find text" },
      { "<leader>sc", "<cmd>Telescope colorscheme<cr>", desc = "Colorscheme" },
      { "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Find Help" },
      { "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages" },
      { "<leader>sn", "<cmd>Telescope notify theme=get_dropdown<cr>", desc = "Notifications" },
      { "<leader>sR", "<cmd>Telescope registers<cr>", desc = "Registers" },
      { "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
      { "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands" },
    },
  },

  {
    "neo-tree.nvim", -- https://github.com/nvim-neo-tree/neo-tree.nvim
    beforeAll = function()
      if vim.fn.argc() == 1 then
        local stat = vim.uv.fs_stat(vim.fn.argv(0)) ---@diagnostic disable-line
        if stat and stat.type == "directory" then require("lz.n").trigger_load "neo-tree.nvim" end
      end
    end,
    before = function() packadd { "plenary.nvim", "nvim-web-devicons", "nui.nvim" } end,
    after = function()
      require("neo-tree").setup {
        close_if_last_window = true,
        filesystem = {
          use_libuv_file_watcher = true,
          group_empty_dirs = true,
        },
      }
    end,
    keys = { { "<leader>e", "<CMD>Neotree toggle reveal<CR>", desc = "NeoTree toggle" } },
  },

  {
    "fileline.nvim", -- https://github.com/lewis6991/fileline.nvim
    event = "BufNewFile",
  },

  {
    "nvim-treesitter-context", -- https://github.com/nvim-treesitter/nvim-treesitter-context
    event = "BufReadPre",
    after = function() require("treesitter-context").setup { multiline_threshold = 1 } end,
  },

  {
    "toggleterm.nvim", -- https://github.com/akinsho/toggleterm.nvim
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      { "<c-j>", desc = "ToggleTerm" },
      { "<leader>jj", "<cmd>TermExec cmd='!!'<CR>", desc = "Rerun last command" },
    },
    after = function()
      local tt = require "toggleterm"
      tt.setup {
        open_mapping = [[<c-j>]],
        shade_terminals = true,
        shading_factor = 2,
        direction = "float",
        highlights = require "rose-pine.plugins.toggleterm",
        float_opts = {
          border = "curved",
          winblend = 10,
        },
      }

      local set_km = function(map, cmd) vim.api.nvim_buf_set_keymap(0, "t", map, cmd, { noremap = true }) end
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          set_km("jk", [[<C-\><C-n>]])
          set_km("<C-h>", [[<C-\><C-n><C-W>h]])
          set_km("<C-j>", [[<C-\><C-n><C-W>j]])
          set_km("<C-k>", [[<C-\><C-n><C-W>k]])
          set_km("<C-l>", [[<C-\><C-n><C-W>l]])
        end,
        group = vim.api.nvim_create_augroup("CustomToggleTerm", { clear = true }),
      })
    end,
  },

  {
    "vim-test", -- https://github.com/vim-test/vim-test
    cmd = { "TestNearest", "TestFile", "TestSuite", "TestLast" },
    before = function()
      vim.g["test#strategy"] = "toggleterm"
      vim.g["test#ruby#rspec#executable"] = "ppspec"
    end,
    keys = {
      { "<leader>jd", "<cmd>TestNearest<CR>", desc = "Nearest" },
      { "<leader>jf", "<cmd>TestFile<CR>", desc = "File" },
      { "<leader>js", "<cmd>TestSuite<CR>", desc = "Suite" },
    },
  },

  {
    "neotest", -- https://github.com/nvim-neotest/neotest
    before = function() packadd "nvim-nio" end,
    after = function()
      packadd "neotest-rspec"
      require("neotest").setup {
        adapters = {
          require "neotest-rspec" {
            -- rspec_cmd = function() return { "pspec" } end
          },
        },
      }
    end,
    keys = {
      { "<leader>jk", function() require("neotest").run.run() end, desc = "Nearest (neotest)" },
      { "<leader>jK", function() require("neotest").run.attach() end, desc = "Nearest Attach (neotest)" },
      { "<leader>jo", function() require("neotest").output_panel.toggle() end, desc = "Toggle Output (neotest)" },
      { "<leader>jp", function() require("neotest").summary.toggle() end, desc = "Toggle Summary (neotest)" },
    },
  },

  {
    "gitsigns.nvim", -- https://github.com/lewis6991/gitsigns.nvim
    event = "BufReadPre",
    after = function()
      require("gitsigns").setup {
        numhl = true,
        -- git signs are rendered into 'statuscolumn' (see will.options) so they
        -- sit beside the line number instead of fighting diagnostics for the
        -- sign column
        signcolumn = false,
        current_line_blame_opts = { delay = 0 },
        on_attach = function(bufnr)
          local gitsigns = require "gitsigns"

          local function map(mode, l, r, desc, opts)
            opts = opts or { desc = desc }
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map("n", "]c", function()
            if vim.wo.diff then
              vim.cmd.normal { "]c", bang = true }
            else
              gitsigns.nav_hunk "next"
            end
          end, "Next Hunk")

          map("n", "[c", function()
            if vim.wo.diff then
              vim.cmd.normal { "[c", bang = true }
            else
              gitsigns.nav_hunk "prev"
            end
          end, "Prev Hunk")

          -- Actions
          map("n", "<leader>hs", gitsigns.stage_hunk, "Stage Hunk")
          map("n", "<leader>hr", gitsigns.reset_hunk, "Reset Hunk")
          map("v", "<leader>hs", function() gitsigns.stage_hunk { vim.fn.line ".", vim.fn.line "v" } end, "Stage Hunk")
          map("v", "<leader>hr", function() gitsigns.reset_hunk { vim.fn.line ".", vim.fn.line "v" } end, "Reset Hunk")
          map("n", "<leader>hS", gitsigns.stage_buffer, "Stage Buffer")
          -- only touches the index, unlike <leader>hR
          map("n", "<leader>hU", gitsigns.reset_buffer_index, "Unstage Buffer")
          map("n", "<leader>hR", gitsigns.reset_buffer, "Reset Buffer")
          map("n", "<leader>hp", gitsigns.preview_hunk, "Preview Hunk")
          map("n", "<leader>hb", function() gitsigns.blame_line { full = true } end, "Blame Line")
          map("n", "<leader>tb", gitsigns.toggle_current_line_blame, "Toggle Line Blame")
          map("n", "<leader>hd", gitsigns.diffthis, "Diff this")
          map("n", "<leader>hD", function() gitsigns.diffthis "~" end, "Diff This ~")
          -- clears itself on CursorMoved, so it does not belong in the <leader>t toggles
          map("n", "<leader>hi", gitsigns.preview_hunk_inline, "Preview Hunk Inline")
          map("n", "<leader>hc", gitsigns.show_commit, "Show Commit")

          -- Text object
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")
        end,
      }
    end,
  },

  {
    "jujutsu.nvim", -- https://github.com/yannvanhalewyn/jujutsu.nvim
    before = function()
      packadd { "plenary.nvim", "diffview-plus.nvim" }
      vim.cmd.runtime "plugin/diffview.lua"
    end,
    after = function()
      local jj = require "jujutsu-nvim"
      jj.setup { diff_preset = "diffview" }

      -- Patch to support custom jj log format (short lowercase change IDs like "mup")
      local jj_internal = require "jujutsu-nvim.jujutsu"
      jj_internal.extract_change_id = function(line)
        local clean = line:gsub("\27%[[@-~?]", ""):gsub("\27%[[0-9:;<=>?]*[!-/]*[@-~]", "")
        local change_id = clean:match "^%W*([a-z]+)%s"
        if change_id and #change_id >= 2 and #change_id <= 8 then return change_id end
      end

      -- Patch to accept 2+ char change IDs (default requires 4+)
      jj.with_change_at_cursor = function(operation)
        local line = vim.api.nvim_get_current_line()
        local change_id = jj_internal.extract_change_id(line)
        if change_id then
          operation(change_id)
        else
          vim.notify("Could not find change ID on current line", vim.log.levels.WARN)
        end
      end
    end,
    cmd = "JJ",
    keys = {
      { "<leader>jl", "<cmd>JJ log<cr>", desc = "JJ Log" },
      { "<leader>jh", function() jj_file_history "%" end, desc = "File history (jj)" },
      { "<leader>jH", function() jj_file_history "" end, desc = "Repo history (jj)" },
    },
  },

  {
    "trouble.nvim",
    cmd = "Trouble",
    after = function() require("trouble").setup() end,
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
      { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbols (Trouble)" },
      {
        "<leader>cl",
        "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
        desc = "LSP Definitions / references / ... (Trouble)",
      },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List (Trouble)" },
    },
  },

  {
    "other.nvim", -- https://github.com/rgroli/other.nvim
    cmd = { "Other", "OtherSplit", "OtherVSplit" },
    keys = {
      { "<leader>a", "<cmd>Other<cr>", desc = "Other file" },
    },
    after = function()
      require("other-nvim").setup {
        mappings = {
          {
            pattern = "/app/(.*)/(.*).rb$",
            target = "/spec/%1/%2_spec.rb",
          },
          {
            pattern = "/spec/(.*)/(.*)_spec.rb$",
            target = "/app/%1/%2.rb",
          },
        },
      }
    end,
  },
}
