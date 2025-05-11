{
  pkgs,
}:
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-unstable-pgtk;
    extraPackages = import ./epkgs { inherit pkgs; };
  };
  home.file.".emacs.d/init.el".source = ./init.el;
  home.file.".emacs.d/templates".source = ./templates;
}
