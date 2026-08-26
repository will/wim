{
  outputs =
    {
      self,
      nixpkgs,
      mnw,
      blink,
      gen-luarc,
      dirtytalk,
      ...
    }:
    let
      overlays = [ gen-luarc.overlays.default ];
      utils = import ./utils.nix { inherit nixpkgs overlays; };

    in
    utils.with-system {
      formatter =
        { pkgs, ... }:
        pkgs.writeShellApplication {
          name = "lint";
          runtimeInputs = builtins.attrValues {
            inherit (pkgs)
              nixfmt
              deadnix
              statix
              fd
              stylua
              ;
          };
          text = ''
            fd '.*\.nix' . -x statix fix -- {} \;
            fd '.*\.nix' . -X deadnix -e -- {} \; -X nixfmt {} \;
            fd '.*\.lua' . -X stylua --indent-type Spaces --indent-width 2 {} \;
          '';
        };

      # `nix run .#dvim` — the configured editor, reading will/ from the working tree, so
      # config edits need no rebuild. Every program below drives this same binary.
      dvim =
        { pkgs, system }:
        pkgs.writeShellApplication {
          name = "dvim";
          text = ''${self.packages.${system}.neovim.devMode}/bin/nvim "$@"'';
        };

      # `nix run .#ntest [test/test_foo.lua] [--filter PATTERN]` — the smoke suite.
      #
      # --filter narrows a red-green loop to one test by substring. It is a debugging aid
      # rather than a verdict: tests here load and drive plugins that later tests observe,
      # so believe a full run over a filtered one.
      ntest =
        { pkgs, system }:
        pkgs.writeShellApplication {
          name = "ntest";
          text = ''
            file="test/run.lua"
            while [ $# -gt 0 ]; do
              case "$1" in
                --filter)
                  export WIM_TEST_FILTER="$2"
                  shift 2
                  ;;
                --filter=*)
                  export WIM_TEST_FILTER="''${1#*=}"
                  shift
                  ;;
                -h | --help)
                  echo "usage: ntest [test/test_foo.lua] [--filter PATTERN]"
                  exit 0
                  ;;
                *)
                  file="$1"
                  shift
                  ;;
              esac
            done

            if [[ "$file" == "test/run.lua" ]]; then
              ${self.packages.${system}.neovim.devMode}/bin/nvim --headless -c "luafile $file"
            else
              # Individual test files: setup global helpers, run file, then exit
              ${self.packages.${system}.neovim.devMode}/bin/nvim --headless \
                -c "lua _G._test_helpers = dofile('test/helpers.lua')" \
                -c "luafile $file" \
                -c "lua _G._test_helpers.report_and_exit()"
            fi
          '';
        };

      # `nix run .#nprobe -- [-e EXPR | FILE.lua] [--load PLUGIN,...] [--load-all] [--open FILE]`
      #
      # Runs a snippet inside the real config and exits nonzero if it errored, for the
      # one-off questions that would otherwise become a throwaway script under /tmp.
      #
      # It exists because a headless nvim is not the editor you get interactively: lz.n
      # defers half the config to a UIEnter that never fires, and every npins plugin waits
      # for its own trigger, so an unprepared probe reports an empty config in good faith.
      # test/probe.lua and test/boot.lua carry the details.
      nprobe =
        { pkgs, system }:
        pkgs.writeShellApplication {
          name = "nprobe";
          runtimeInputs = builtins.attrValues { inherit (pkgs) git coreutils; };
          text = ''
            usage() {
              echo "usage: nprobe [-e EXPR | FILE.lua] [--load PLUGIN[,PLUGIN...]] [--load-all] [--open FILE]"
            }

            export WIM_PROBE_EXPR="" WIM_PROBE_FILE="" WIM_PROBE_LOAD="" WIM_PROBE_LOAD_ALL="" WIM_PROBE_OPEN=""
            while [ $# -gt 0 ]; do
              case "$1" in
                -e)
                  WIM_PROBE_EXPR="$2"
                  shift 2
                  ;;
                --load)
                  WIM_PROBE_LOAD="$2"
                  shift 2
                  ;;
                --load-all)
                  WIM_PROBE_LOAD_ALL=1
                  shift
                  ;;
                --open)
                  WIM_PROBE_OPEN="$2"
                  shift 2
                  ;;
                -h | --help)
                  usage
                  exit 0
                  ;;
                *)
                  WIM_PROBE_FILE="$1"
                  shift
                  ;;
              esac
            done

            if [ -z "$WIM_PROBE_EXPR" ] && [ -z "$WIM_PROBE_FILE" ]; then
              usage >&2
              exit 2
            fi

            # test/ is read from the working tree, like the config itself
            cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

            # </dev/null because a headless nvim that reaches a prompt waits forever, and a
            # timeout because a probe is usually the thing establishing whether this config
            # hangs at all
            timeout="''${WIM_PROBE_TIMEOUT:-120}"
            status=0
            timeout "$timeout" \
              ${self.packages.${system}.neovim.devMode}/bin/nvim --headless -c "luafile test/probe.lua" \
              </dev/null || status=$?
            if [ "$status" -eq 124 ]; then
              echo "nprobe: gave up after ''${timeout}s, nvim was probably waiting for input" >&2
            fi
            exit "$status"
          '';
        };

      # `nix run .#ndump -- <report> [nprobe flags]`
      #
      # JSON snapshots of the booted config, for the questions that otherwise mean reading
      # a health buffer or a wall of :map output. Reports: keymaps, plugins, lsp, autocmds,
      # treesitter, deprecations.
      #
      # Takes nprobe's flags, and most reports want them, since nothing lazy is loaded and
      # nothing filetype-scoped exists until a file is open:
      #   ndump lsp --open will/lua/will/init.lua
      #   ndump plugins
      # A deprecation only records when the offending line runs, so for that report drive
      # the feature first, in one session:
      #   WIM_DUMP_REPORT=deprecations nprobe --load toggleterm.nvim \
      #     -e 'vim.cmd "ToggleTerm" return dofile "test/dump.lua"'
      # test/dump.lua carries the reports themselves.
      ndump =
        { pkgs, system }:
        pkgs.writeShellApplication {
          name = "ndump";
          runtimeInputs = [
            self.nprobe.${system}
            pkgs.git
          ];
          text = ''
            usage="usage: ndump <keymaps|plugins|lsp|autocmds|treesitter|deprecations> [nprobe flags]"
            case "''${1:-}" in
              "")
                echo "$usage" >&2
                exit 2
                ;;
              -h | --help)
                echo "$usage"
                exit 0
                ;;
            esac

            export WIM_DUMP_REPORT="$1"
            shift
            root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            exec nprobe "$@" "$root/test/dump.lua"
          '';
        };

      # nix run's own schema. Without it every invocation has to name the system by hand,
      # because dvim and friends are plain attributes rather than apps: `nix run .#ntest`
      # fails with "attribute 'ntest.type' does not exist".
      apps =
        { pkgs, system }:
        let
          app = attr: {
            type = "app";
            program = pkgs.lib.getExe self.${attr}.${system};
          };
        in
        {
          default = app "dvim";
          dvim = app "dvim";
          ntest = app "ntest";
          nprobe = app "nprobe";
          ndump = app "ndump";
          lint = app "formatter";
        };

      devShells = { pkgs, system }: {
        default = pkgs.mkShellNoCC {
          packages = [
            self.dvim.${system}
            self.ntest.${system}
            self.nprobe.${system}
            self.ndump.${system}
            self.formatter.${system}
            pkgs.npins
          ];
          shellHook =
            let
              luarc = pkgs.mk-luarc-json {
                # mnw resolves a plugin's own dependencies (blink.cmp pulls in blink.lib,
                # which ships a lua/ directory), so they never appear in this list
                plugins =
                  with self.plugins.${system};
                  start ++ builtins.concatMap (p: p.dependencies or [ ]) start ++ builtins.attrValues optAttrs;
              };
            in
            "ln -fs ${luarc} .luarc.json";
        };
      };

      plugins = { pkgs, system }: {
        start = [
          (pkgs.vimPlugins.nvim-treesitter.withPlugins (
            _:
            pkgs.vimPlugins.nvim-treesitter.allGrammars
            ++ [
              pkgs.tree-sitter-grammars.tree-sitter-norg-meta
              pkgs.tree-sitter-grammars.tree-sitter-norg
            ]
          ))
          blink.packages.${system}.default
          (pkgs.callPackage ./dirtytalk.nix { src = dirtytalk; })
        ];

        # everything from npins goes into /opt/ and is loaded with packadd
        optAttrs = mnw.lib.npinsToPluginsAttrs pkgs ./npins/sources.json;

        dev.will = {
          pure = ./will;
          impure = "~/code/wim-public/will";
        };
      };

      packages = { pkgs, system }: {
        default = self.packages.${system}.neovim;

        neovim = mnw.lib.wrap pkgs {
          neovim = pkgs.neovim-unwrapped;

          wrapperArgs = [
            "--set"
            "FZF_DEFAULT_OPTS"
            "--layout=reverse --inline-info"
          ];

          appName = "wim";

          # Source lua config
          initLua = "require('will')";

          plugins = self.plugins.${system};

          extraBinPath =
            builtins.attrValues {
              #
              # Runtime dependencies
              #
              inherit (pkgs)
                nixd
                # nixd's default formatting command, and the same derivation the
                # formatter output uses, so the LSP and `nix fmt` cannot disagree
                nixfmt
                deadnix
                statix
                nil

                lua-language-server
                stylua

                fzy

                ripgrep
                fd
                chafa
                ;
            }
            ++ [
              (pkgs.writeShellApplication {
                name = "ppspec";
                text = ''if [ $# -eq 0 ]; then pspec; else rspec "$@"; fi '';
              })

            ];
        };
      };

      checks = { pkgs, system }: {
        smoke =
          pkgs.runCommand "wim-smoke-test"
            {
              nativeBuildInputs = [ self.packages.${system}.neovim ];
            }
            ''
              export HOME=$(mktemp -d)
              cd ${./.}
              nvim --headless -c "luafile test/run.lua"
              touch $out
            '';
      };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    mnw.url = "github:Gerg-L/mnw";
    blink = {
      url = "github:Saghen/blink.cmp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";
    dirtytalk = {
      url = "github:psliwka/vim-dirtytalk";
      flake = false;
    };

    # just cutting down on transitive input differences
    flake-parts.url = "github:hercules-ci/flake-parts";
    gen-luarc.inputs.flake-parts.follows = "flake-parts";
  };
}
