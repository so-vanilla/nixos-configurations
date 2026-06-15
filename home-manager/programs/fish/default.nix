{
  pkgs,
  catppuccin-flavor,
}:
let
  editorCommand = "emacsclient -t";
in
{
  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
    ];
    interactiveShellInit = ''
      set fish_greeting
      set pure_enable_nixdevshell true
      set -x PYTHON_HOME $(, python3 -c 'import sys; print(sys.prefix, end="")')
      set -x GITHUB_PERSONAL_ACCESS_TOKEN $(, gh auth token)
      set -x HM_USERNAME $(whoami)
      set -x HM_GIT_EMAIL $(git config user.email)

      if test -f ~/.config/fish/general.fish
        source ~/.config/fish/general.fish
      end

      if test -f ~/.config/fish/links.fish
        source ~/.config/fish/links.fish
      end

      if status is-interactive; and test -n $EAT_SHELL_INTEGRATION_DIR
        set -g fish_autosuggestion_enabled 0
        source ~/.config/fish/eat-integration.fish
      end

      if test -d ~/.local/bin
        set -x PATH $HOME/.local/bin $PATH
      end

      if test -d /opt/homebrew/bin
        set -x PATH /opt/homebrew/bin $PATH
      end

      if test -d ~/.rd/bin
        set -x PATH $HOME/.rd/bin $PATH
      end
    '';
    shellAbbrs = {
      ls = "eza";
      cat = "bat";
      grep = "rg";
      rm = "trash-put";
    };
    functions = {
      update-nix = {
        body = builtins.readFile ./update-nix.fish;
        description = "Update nix environment (flake update → rebuild → commit & push)";
      };
      magit = {
        body = ''
          set -l cwd_b64 (printf '%s' (pwd) | base64 | tr -d '\n')
          ${editorCommand} --eval "(progn (require 'magit) (let ((default-directory (file-name-as-directory (decode-coding-string (base64-decode-string \"$cwd_b64\") 'utf-8)))) (magit-status default-directory)))"
        '';
        description = "Open Magit for the current shell directory";
      };
      cy = {
        body = ''
          command claude --dangerously-skip-permissions $argv
        '';
        description = "Start Claude Code with permission prompts bypassed";
      };
    };
    shellAliases = {
      h = "cd";
      q = "exit";
      e = editorCommand;
      ec = editorCommand;
      kills = "killall slack .Discord-wrapped";
    };
  };

  home.file.".config/fish/eat-integration.fish".source = ./eat-integration.fish;

  catppuccin.fish = {
    enable = true;
    flavor = catppuccin-flavor;
  };
}
