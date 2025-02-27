{
  programs.git = {
    enable = true;
    userName = "somura";
    userEmail = "somura-vanilla@so-icecream.com";
    extraConfig = {
      core = {
        editor = "emacsclient -c";
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
