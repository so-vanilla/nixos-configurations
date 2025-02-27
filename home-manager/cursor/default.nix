{
  pkgs,
}:
[
  {
    home.pointerCursor = {
      name = "catppuccin-latte-pink-cursors";
      package = pkgs.catppuccin-cursors.lattePink;
      size = 24;
      gtk.enable = true;
      hyprcursor = {
        enable = true;
        size = 24;
      };
      x11.enable = true;
    };
  }
]
