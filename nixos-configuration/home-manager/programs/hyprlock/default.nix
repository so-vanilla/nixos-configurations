let
  settings = import ./settings.nix;
in
{
  programs.hyprlock = {
    enable = true;
    settings = settings;
  };
}
