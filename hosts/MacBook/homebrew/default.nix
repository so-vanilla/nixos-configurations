{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = [
      {
        name = "nikitabobko/tap";
        trusted = true;
      }
    ];
    brews = [ ];
    casks = [
      "chatgpt"
      "aerospace"
      "raycast"
      "aquaskk"
      "discord"
      "espanso"
      "karabiner-elements"
      "vivaldi"
      "steam"
      "sparrow"
      "todoist-app"
      "zed"
    ];
    masApps = { };
  };
}
