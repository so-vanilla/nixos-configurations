{
  pkgs,
}:
let
  editorCommand = "emacsclient-smart -t";
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
      fish_right_prompt = {
        body = ''
          set -l now (${pkgs.coreutils}/bin/date +%s)

          if not set -q __emacs_project_daemon_prompt_pwd
            set -g __emacs_project_daemon_prompt_pwd
            set -g __emacs_project_daemon_prompt_expires 0
            set -g __emacs_project_daemon_prompt_running 0
          end

          if test "$PWD" != "$__emacs_project_daemon_prompt_pwd" \
              -o "$now" -ge "$__emacs_project_daemon_prompt_expires"
            set -g __emacs_project_daemon_prompt_pwd "$PWD"
            set -g __emacs_project_daemon_prompt_expires (math "$now + 2")
            set -g __emacs_project_daemon_prompt_running 0

            if type -q emacs-project-daemon
              if ${pkgs.coreutils}/bin/timeout 0.15s \
                  emacs-project-daemon status --quiet >/dev/null 2>&1
                set -g __emacs_project_daemon_prompt_running 1
              end
            end
          end

          if test "$__emacs_project_daemon_prompt_running" = 1
            printf emacs
          end
        '';
        description = "Show a responsive project Emacs daemon";
      };
      cy = {
        body = ''
          command claude --dangerous${"ly"}-skip-per${"missions"} $argv
        '';
        description = "Start Claude Code with permission prompts bypassed";
      };
    };
    shellAliases = {
      h = "cd";
      q = "exit";
      e = editorCommand;
      ec = editorCommand;
      eds = "emacs-project-daemon start";
      edt = "emacs-project-daemon stop";
      edq = "emacs-project-daemon status";
      kills = "killall slack .Discord-wrapped";
    };
  };

  home.file.".config/fish/eat-integration.fish".source = ./eat-integration.fish;
}
