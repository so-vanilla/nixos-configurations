{
  pkgs,
  email,
}:
{
  programs.git = {
    enable = true;
    ignores =
      [
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
        editor = "nvim";
        commentChar = ";";
      };
      user = {
        name = "somura";
        email = email;
      };
      init = {
        defaultbranch = "main";
      };
      credential = {
        helper = "store";
      };
      github = {
        user = "so-vanilla";
      };
      ghq = {
        root = "~/repos";
      };
    };
  };
}
