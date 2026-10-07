{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
    ];
    allowedUDPPorts = [
      59010 # SoundWire
    ];
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };
}
