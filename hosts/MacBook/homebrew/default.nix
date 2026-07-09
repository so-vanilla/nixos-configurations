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
      "codex"
      "codex-app"
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
