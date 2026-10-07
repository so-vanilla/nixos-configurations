{ pkgs, hostname, ... }:
let
  networkmanager = import ./networkmanager { inherit pkgs; };
  firewall =
    if builtins.pathExists ./firewall/default.nix then
      ./firewall
    else
      abort "hosts/.../firewall/default.nix is not exist. Make it.";
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
