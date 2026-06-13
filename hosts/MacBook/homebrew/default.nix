{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = [ "nikitabobko/tap" ];
    brews = [ ];
    casks = [
      "codex"
      "zen"
      "aerospace"
      "raycast"
      "aquaskk"
      "discord"
      "thunderbird"
    ];
    masApps = { };
  };
}
