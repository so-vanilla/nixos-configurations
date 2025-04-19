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
      ghq = {
        root = "~/repos";
      };
    };
  };
}
