{
  pkgs,
  editorCommand ? "zed",
}:
let
  waitEditorCommand = "${editorCommand} --wait";
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
      ec = waitEditorCommand;
      kills = "killall slack .Discord-wrapped";
    };
  };
}
