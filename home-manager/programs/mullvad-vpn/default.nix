{ pkgs-stable }:
{
  programs.mullvad-vpn = {
    enable = true;
    package = pkgs-stable.mullvad-vpn;
  };
}
