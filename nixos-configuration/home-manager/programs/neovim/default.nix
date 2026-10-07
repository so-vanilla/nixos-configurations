{ pkgs }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      lazy-nvim
    ];
    extraPackages = with pkgs; [
      nil
    ];
  };
}
