{ pkgs, hostname, ... }:
let
  networkmanager = import ./networkmanager { inherit pkgs; };
  firewall = ./firewall;
in
[
  {
    networking = {
      hostName = hostname;
      wireless.iwd.enable = true;
    };
  }
  networkmanager
  firewall
]
