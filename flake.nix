{
  outputs =
    { self, nixpkgs, neovim-nightly, mnw, blink, gen-luarc, dirtytalk, ... }:
    let
      overlays = [
        gen-luarc.overlays.default
        #   neovim-nightly.overlays.default
        # NOTE: when readding nightly, remove unrapped line
      ];
      utils = import ./utils.nix { inherit nixpkgs overlays; };

    in
    utils.with-system {
      formatter = { pkgs, ... }:
        pkgs.writeShellApplication {
          name = "lint";
          runtimeInputs = builtins.attrValues {
            inherit (pkgs)
              nixfmt-classic# -rfc-style
              deadnix statix fd stylua;
          };
          text = ''
            fd '.*\.nix' . -x statix fix -- {} \;
            fd '.*\.nix' . -X deadnix -e -- {} \; -X nixfmt {} \;
            fd '.*\.lua' . -X stylua --indent-type Spaces --indent-width 2 {} \;
          '';
        };

      dvim = { pkgs, system }:
        pkgs.writeShellApplication {
          name = "dvim";
          text = ''${self.packages.${system}.neovim.devMode}/bin/nvim "$@"'';
        };

      ppspec = { pkgs }:
        pkgs.writeShellApplication {
          name = "ppspec";
          text = ''[ $# -eq 0 ] && pspec || rspec "$@" '';
        };

      devShells = { pkgs, system }: {
        default = pkgs.mkShellNoCC {
          packages =
            [ self.dvim.${system} self.formatter.${system} pkgs.npins ];
          shellHook =
            let
              luarc = pkgs.mk-luarc-json { plugins = self.plugins.${system}; };
            in
            "ln -fs ${luarc} .luarc.json";
        };
      };

      plugins = { pkgs, system }:
        [ pkgs.vimPlugins.nvim-treesitter.withAllGrammars ]
        ++ (utils.npins-plugins "npins") ++ [
          blink.packages.${system}.default
          (pkgs.callPackage ./dirtytalk.nix { src = dirtytalk; })
        ];

      packages = { pkgs, system }: {
        default = self.packages.${system}.neovim;

        neovim = mnw.lib.wrap pkgs {
          neovim = pkgs.neovim-unwrapped; # for released
          # inherit (pkgs) neovim; # for neovim-nightly overlay

          wrapperArgs =
            [ "--set" "FZF_DEFAULT_OPTS" "--layout=reverse --inline-info" ];

          appName = "wim";

          # Source lua config
          initLua = "require('will')";

          devExcludedPlugins = [ ./will ];
          devPluginPaths = [ "/Users/will/code/wim-public/will" ];
          plugins = self.plugins.${system};

          extraBinPath = builtins.attrValues
            {
              #
              # Runtime dependencies
              #
              inherit (pkgs)
                nixd deadnix statix nil

                lua-language-server stylua

                fzy

                ripgrep fd chafa;
            } ++ [
            (pkgs.writeShellApplication {
              name = "ppspec";
              text = ''if [ $# -eq 0 ]; then pspec; else rspec "$@"; fi '';
            })

          ];
        };
      };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    neovim-nightly.url = "github:nix-community/neovim-nightly-overlay";
    mnw.url = "github:will/mnw/after";
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
    blink.inputs.flake-parts.follows = "flake-parts";
    # neovim-nightly.inputs.neovim-src = { flake=false; url="github:gpanders/neovim/theme-change-notifications";};
  };
}
