{
  pkgs,
}:
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
    extraPackages = import ./epkgs { inherit pkgs; };
  };
  home.file.".emacs.d/init.el".source = ./init.el;
}
