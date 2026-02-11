{
  pkgs,
}:
{
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
  };

  home.file.".claude/CLAUDE.md".source = ./global-CLAUDE.md;
}
