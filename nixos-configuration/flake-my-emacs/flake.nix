{
  description = "Terminal Emacs configuration flake for home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { ... }@inputs:
    let
      emacsOverlay = import inputs.emacs-overlay;

      mkPkgs =
        system:
        import inputs.nixpkgs {
          inherit system;
          overlays = [ emacsOverlay ];
        };

      mkEmacsPackage =
        pkgs: if pkgs.stdenv.hostPlatform.isDarwin then pkgs.emacs-unstable else pkgs.emacs-unstable-pgtk;

      mkTreeSitterGrammarBundle =
        pkgs:
        let
          lib = pkgs.lib;
          sharedLibrarySuffix = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";

          grammars = with pkgs.tree-sitter-grammars; {
            bash = tree-sitter-bash;
            dockerfile = tree-sitter-dockerfile;
            go = tree-sitter-go;
            gomod = tree-sitter-gomod;
            hcl = tree-sitter-hcl;
            java = tree-sitter-java;
            json = tree-sitter-json;
            lua = tree-sitter-lua;
            markdown = tree-sitter-markdown;
            markdown-inline = tree-sitter-markdown-inline;
            nix = tree-sitter-nix;
            python = tree-sitter-python;
            toml = tree-sitter-toml;
            yaml = tree-sitter-yaml;
          };
        in
        pkgs.runCommand "emacs-tree-sitter-grammars" { } ''
          mkdir -p "$out"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              language: grammar:
              ''ln -s ${grammar}/parser "$out/libtree-sitter-${language}.${sharedLibrarySuffix}"''
            ) grammars
          )}
        '';

      mkLanguageTools =
        pkgs:
        with pkgs;
        [
          basedpyright
          bash-language-server
          deadnix
          dockerfile-language-server
          emacs-lsp-booster
          fd
          fzf
          git
          google-java-format
          gopls
          gotools
          hadolint
          jdt-language-server
          luajitPackages.luacheck
          lua-language-server
          markdownlint-cli
          marksman
          nixd
          nixfmt
          nodejs_24
          prettier
          ripgrep
          ruff
          shellcheck
          shfmt
          statix
          stylua
          taplo
          terraform-ls
          tflint
          vscode-langservers-extracted
          yaml-language-server
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.wl-clipboard ];

      mkTerminalTools = pkgs: with pkgs; [ zellij ];

      mkZellijRoomPlugin =
        pkgs:
        pkgs.fetchurl {
          url = "https://github.com/rvcas/room/releases/download/v1.2.1/room.wasm";
          hash = "sha256-kLSDpAt2JGj7dYYhYFh6BfvtzVwTrcs+0jHwG/nActE=";
        };

      mkWeztermConfigText = builtins.readFile ./wezterm/wezterm.lua;
      mkWeztermConfig = pkgs: pkgs.writeText "wezterm.lua" mkWeztermConfigText;
      mkWindowsWeztermConfig =
        pkgs: pkgs.writeText "windows.wezterm.lua" (builtins.readFile ./wezterm/windows.wezterm.lua);
      mkZellijConfig = pkgs: pkgs.writeText "config.kdl" (builtins.readFile ./zellij/config.kdl);
      mkZellijWorkspaceLayout =
        pkgs: pkgs.writeText "workspace.kdl" (builtins.readFile ./zellij/layouts/workspace.kdl);

      homeManagerModule =
        {
          lib,
          pkgs,
          ...
        }:
        let
          modulePkgs = mkPkgs pkgs.stdenv.hostPlatform.system;
          treeSitterGrammarBundle = mkTreeSitterGrammarBundle modulePkgs;
          emacsPackage = mkEmacsPackage modulePkgs;
          zellijRoomPlugin = mkZellijRoomPlugin modulePkgs;
        in
        {
          home.packages = mkLanguageTools modulePkgs ++ mkTerminalTools modulePkgs;

          home.sessionVariables = {
            EDITOR = lib.mkOverride 900 "emacsclient -t";
            VISUAL = lib.mkOverride 900 "emacsclient -t";
          };

          programs.emacs = {
            enable = true;
            package = emacsPackage;
            extraPackages = import ./epkgs { pkgs = modulePkgs; };
          };

          programs.wezterm = {
            enable = true;
            package = modulePkgs.wezterm;
            extraConfig = mkWeztermConfigText;
          };

          services.emacs = {
            enable = lib.mkForce false;
          };

          home.file = {
            ".emacs.d/init.el".source = ./init.el;
            ".emacs.d/early-init.el".source = ./early-init.el;
            ".emacs.d/lisp".source = ./.emacs.d/lisp;
            ".ddskk/init".source = ./.ddskk/init;
            ".emacs.d/tree-sitter-grammars".source = treeSitterGrammarBundle;
            ".config/zellij/config.kdl".source = ./zellij/config.kdl;
            ".config/zellij/layouts/workspace.kdl".source = ./zellij/layouts/workspace.kdl;
            ".config/zellij/plugins/room.wasm".source = zellijRoomPlugin;
          };
        };
      perSystemOutputs = inputs.flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = mkPkgs system;
          treeSitterGrammarBundle = mkTreeSitterGrammarBundle pkgs;
          emacsPackage = mkEmacsPackage pkgs;
          configuredEmacs = (pkgs.emacsPackagesFor emacsPackage).emacsWithPackages (
            import ./epkgs { inherit pkgs; }
          );
        in
        {
          packages = {
            default = configuredEmacs;
            emacs = configuredEmacs;
            tree-sitter-grammars = treeSitterGrammarBundle;
            wezterm-config = mkWeztermConfig pkgs;
            windows-wezterm-config = mkWindowsWeztermConfig pkgs;
            zellij-config = mkZellijConfig pkgs;
            zellij-workspace-layout = mkZellijWorkspaceLayout pkgs;
            zellij-room-plugin = mkZellijRoomPlugin pkgs;
          };

          homeManagerModules.default = homeManagerModule;
        }
      );
    in
    perSystemOutputs
    // {
      homeManagerModules = perSystemOutputs.homeManagerModules // {
        default = homeManagerModule;
      };
    };
}
