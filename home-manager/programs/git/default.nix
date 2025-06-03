{
  programs.git = {
    enable = true;
    userName = "somura";
    userEmail = "somura-vanilla@so-icecream.com";
    extraConfig = {
      core = {
        editor = "nvim";
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
