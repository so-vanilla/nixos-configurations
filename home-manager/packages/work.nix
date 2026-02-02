{
  pkgs,
}:
let
  frompkgs = with pkgs; [
    copilot-language-server
    devenv
    enchant
    fd
    gawk
    gh
    # git-credential-manager
    github-copilot-cli
    hunspellDicts.en_US-large
    killall
    # marksman
    nixd
    nixfmt
    nodejs_25
    tenv
    trash-cli
    unzip
    zip
  ];
in
[
  {
    home.packages = frompkgs;
  }
]
