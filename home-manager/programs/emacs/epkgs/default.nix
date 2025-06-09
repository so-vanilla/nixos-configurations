{
  pkgs
}:
epkgs:
import ./leaf.nix { inherit epkgs; }
++ import ./lsp.nix { inherit epkgs; }
++ import ./coding.nix { inherit epkgs; }
++ import ./paren.nix { inherit epkgs; }
++ import ./cursor.nix { inherit epkgs; }
++ import ./vcs.nix { inherit epkgs; }
++ import ./minibuffer.nix { inherit epkgs; }
++ import ./completion.nix { inherit epkgs; }
++ import ./org.nix { inherit epkgs; }
++ import ./language.nix { inherit epkgs; }
++ import ./ai.nix { inherit epkgs; }
++ import ./utils.nix { inherit epkgs; }
++ import ./appearance.nix { inherit epkgs; }
