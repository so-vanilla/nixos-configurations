{
  email,
}:
{
  programs.git = {
    enable = true;
    settings = {
      core = {
        editor = "nvim";
        commentChar = ";";
        excludesFile = "~/.gitignore_global";
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
      ghq = {
        root = "~/repos";
      };
    };
  };

  home.file.".gitignore_global".source = ./gitignore_global;
}
