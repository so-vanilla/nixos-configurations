{
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "catppuccin-latte";
  };
  catppuccin.sddm = {
    enable = true;
    flavor = "latte";
    assertQt6Sddm = false;
  };
}
