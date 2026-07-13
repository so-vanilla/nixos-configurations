{
  pkgs,
  email,
}:
let
  credentialSettings =
    if pkgs.stdenv.isDarwin then
      {
        credential = {
          helper = "";
        };
        "credential \"https://github.com\"" = {
          helper = "!gh auth git-credential";
        };
      }
    else
      {
        credential = {
          helper = "store";
        };
      };
in
{
  programs.git = {
    enable = true;
    ignores = [
      ".claude"
      "claude-plans"
      "result"
    ]
    ++ (
      if pkgs.stdenv.isDarwin then
        [
          ".envrc"
          ".dir-locals.el"
          "devenv.nix"
          "devenv.yaml"
          "devenv.lock"
          ".devenv.flake.nix"
        ]
      else
        [ ]
    );
    settings = {
      core = {
        editor = "emacsclient-smart -t";
        commentChar = ";";
      };
      user = {
        name = "somura";
        email = email;
      };
      init = {
        defaultbranch = "main";
      };
      github = {
        user = "so-vanilla";
      };
      ghq = {
        root = "~/repos";
      };
    }
    // credentialSettings;
  };
}
