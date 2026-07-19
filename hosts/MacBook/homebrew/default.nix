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
      "thunderbird"
      "vivaldi"
      "steam"
    ];
    masApps = { };
  };
}
