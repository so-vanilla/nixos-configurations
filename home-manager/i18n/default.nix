{
  pkgs,
}:
let
  inputMethod = import ./inputMethod { inherit pkgs; };
in
[
  inputMethod
]
