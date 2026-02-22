{
  pkgs,
}:
{
  services.gpg-agent = {
    enable = true;
    enableFishIntegration = true;
    defaultCacheTtl = 2592000;
    maxCacheTtl = 2592000;
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
