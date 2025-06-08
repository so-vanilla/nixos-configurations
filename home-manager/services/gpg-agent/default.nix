{
  pkgs,
}:
{
  services.gpg-agent = {
    enable = true;
    enableFishIntegration = true;
    extraConfig = ''
      allow-emacs-pinentry
      allow-loopback-pinentry
    '';
    pinentry = {
      package = pkgs.pinentry-curses;
      program = "pinentry-curses";
    };
  };
}
