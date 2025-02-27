''
  * {
    font-family: FontAwesome, Roboto, Helvetica, Arial, sans-serif;
    font-size: 12px;
    min-height: 0;
  }

  window#waybar {
    background-color: transparent;
    border: transparent;
    transition-property: background-color;
    transition-duration: .5s;
  }

  button {
    box-shadow: inset 0 -3px transparent;
    border: none;
    border-radius: 0;
  }

  /* https://github.com/Alexays/Waybar/wiki/FAQ#the-workspace-buttons-have-a-strange-hover-effect */
  button:hover {
    background: inherit;
    box-shadow: inset 0 -3px #ffffff;
  }

  #network,
  #cpu,
  #memory,
  #temperature,
  #wireplumber,
  #backlight,
  #battery,
  #clock,
  #tray,
  #custom-notification {
    background-color: alpha(#ccd0da, 0.1);
    padding: 0 10px;
    border-radius: 12px;
  }

  .modules-left,
  .modules-center,
  .modules-right {
    margin: 3px 0;
  }

  .modules-left,
  .modules-right {
    color: #04a5e5;
  }

  .modules-left:first-child {
    margin-left: 5px;
  }

  .modules-right:last-child {
    margin-right: 5px;
  }

  #workspaces button:nth-child(odd) {
    color: #04a5e5;
  }

  #workspaces button:nth-child(even) {
    color: #179299;
  }

  #workspaces button.active {
    color: #d20f39;
  }

  #window {
    color: #04a5e5;
  }
''
