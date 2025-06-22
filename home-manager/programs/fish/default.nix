{
  pkgs,
  catppuccin-flavor,
}:
{
  programs.fish = {
    enable = true;
    plugins = [
      { name = "pure"; src = pkgs.fishPlugins.pure.src; }
    ];
    interactiveShellInit = ''
      set fish_greeting
      set pure_enable_nixdevshell true
      set -x PYTHON_HOME $(python3 -c 'import sys; print(sys.prefix, end="")')
      source ~/.config/fish/general.fish
      source ~/.config/fish/links.fish
    '';
    shellAbbrs = {
      ls="eza";
      cat="bat";
      grep="rg";
      rm="trash-put";
    };
    shellAliases = {
      h="cd";
      q="exit";
      v="emacsclient -nc";
      ed="XMODIFIERS= GTK_IM_MODULE= QT_IM_MODULE= emacs --daemon";
      ek="emacsclient -e \"(kill-emacs)\"";
      ec="emacsclient -c";
      kills="killall slack .Discord-wrapped";
    };
  };

  catppuccin.fish = {
    enable = true;
    flavor = catppuccin-flavor;
  };
}
