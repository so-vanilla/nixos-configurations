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
}
