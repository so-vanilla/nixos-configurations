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
      emacs-restart="emacsclient -e \"(kill-emacs)\" && emacs --daemon";
      kills="killall slack .Discord-wrapped";
    };
  };

  catppuccin.fish = {
    enable = true;
    flavor = catppuccin-flavor;
  };
}
