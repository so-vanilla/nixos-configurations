{
  pkgs,
  email,
}:
import ./default.nix {
  inherit pkgs email;
  editor = "zed.exe --wait";
}
