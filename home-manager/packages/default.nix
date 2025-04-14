{
  pkgs,
  zen-browser-pkg,
}:
let
  frompkgs = with pkgs; [
    babashka
    bitwarden-cli
    brightnessctl
    cargo
    clang-tools
    clojure
    clojure-lsp
    cmake
    copilot-language-server
    deno
    discord
    efm-langserver
    gcc
    ghq
    gnumake
    gopls
    graphviz
    hyprcursor
    hyprland-qtutils
    jdt-language-server
    killall
    leiningen
    libnotify
    lua
    lua-language-server
    markdown-oxide
    networkmanagerapplet
    nil
    nixfmt-rfc-style
    nodePackages.bash-language-server
    nodejs_22
    playerctl
    pyright
    (python3.withPackages (ps: with ps; [ numpy pandas matplotlib ]))
    rust-analyzer
    rustc
    rustfmt
    slack
    soundwireserver
    texlab
    texliveFull
    thunderbird
    traceroute
    trash-cli
    unzip
    whois
    wl-clipboard
    zip
    zoom-us
    gimp
  ];
  zen-browser = [
    zen-browser-pkg
  ];
in
[
  {
    home.packages = frompkgs ++ zen-browser;
  }
]
