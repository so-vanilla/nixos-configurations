{ pkgs-stable }:
{
  services.mullvad-vpn = {
    enable = true;
    package = pkgs-stable.pkgs.mullvad;
  };
}
