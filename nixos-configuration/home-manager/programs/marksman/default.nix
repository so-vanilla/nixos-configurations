{ pkgs, lib, ... }:
let
  configText = ''
    [code_action]
    toc.enable = false
  '';
in
{
  home.file =
    lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      ".config/marksman/config.toml".text = configText;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      "Library/Application Support/marksman/config.toml".text = configText;
    };
}
