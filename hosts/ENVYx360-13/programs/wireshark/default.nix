{ pkgs, ... }:
let
  extraCfg = import ./extraCfg.nix;
in
{
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };
}
