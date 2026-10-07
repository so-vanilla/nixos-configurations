let
  settings = import ./settings.nix;
  style = import ./style.nix;
in
{
  programs.waybar = {
    enable = true;
    settings = settings;
    style = style;
  };
}
