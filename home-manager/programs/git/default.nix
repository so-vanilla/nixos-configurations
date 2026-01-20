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
        email = "somura-vanilla@so-icecream.com";
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
