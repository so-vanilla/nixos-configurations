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
    defaultCacheTtl = 315360000;
    maxCacheTtl = 315360000;
    pinentry = {
      package = pkgs.pinentry-curses;
      program = "pinentry-curses";
    };
  };
}
