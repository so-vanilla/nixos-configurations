{
  pkgs,
  email,
  editor ? "zed --wait",
}:
let
  credentialSettings =
    if pkgs.stdenv.hostPlatform.isDarwin then
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
      "/.claude/"
      "/.agent/"
      "/.local/"
      "/claude-plans/"
      "result"
    ]
    ++ (
      if pkgs.stdenv.hostPlatform.isDarwin then
        [
          ".envrc"
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
        editor = editor;
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
