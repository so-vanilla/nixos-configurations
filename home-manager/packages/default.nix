{
  pkgs,
}:
let
  nodePkgs = pkgs.callPackage ./node2nix { inherit pkgs; };
  
  frompkgs = with pkgs; [
    babashka
    browsh
    cargo
    clang-tools
    claude-code
    clojure
    clojure-lsp
    copilot-language-server
    devcontainer
    dockerfile-language-server
    dot-language-server
    firefox
    enchant
    eslint
    fd
    gcc
    gh
    ghq
    git-credential-manager
    github-copilot-cli
    gnumake
    gopls
    gotools
    graphviz
    hunspellDicts.en_US-large
    jdt-language-server
    killall
    leiningen
    lua
    lua-language-server
    marksman
    nixd
    nixfmt-rfc-style
    nodePackages.bash-language-server
    nodejs_22
    pyright
    (python3.withPackages (ps: with ps; [ numpy pandas matplotlib ]))
    ruff
    rust-analyzer
    rustc
    rustfmt
    svelte-language-server
    texlab
    # traceroute
    terraform-ls
    trash-cli
    typescript-language-server
    unzip
    vim-language-server
    vscode-langservers-extracted
    whois
    yaml-language-server
    zed-editor
    zip
    # nodePkgs."@github/copilot"
  ];
in
[
  {
    home.packages = frompkgs;
  }
]
