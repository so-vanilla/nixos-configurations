{ pkgs, ... }:
{
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };
}
