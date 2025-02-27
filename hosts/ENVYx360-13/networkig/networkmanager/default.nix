{ pkgs, ... }:
{
  networking.networkmanager = {
    enable = true;
    plugins = [
      pkgs.networkmanager-fortisslvpn
    ];
    wifi.backend = "iwd";
  };
}
