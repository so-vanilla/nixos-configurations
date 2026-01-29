{
  programs.claude-code = {
    enable = true;
    mcpServers = {
      filesystem = {
        command = "nix";
        args = [
          "run"
          "github:natsukium/mcp-servers-nix#filesystem"
          "--"
          "~/tmp"
          "/tmp"
        ];
        git = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#git"
          ];
        };
        memory = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#memory"
          ];
        };
        sequential-thinking = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#sequential-thinking"
          ];
        };
        time = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#time"
          ];
        };
        context7 = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#context7"
          ];
        };
        github = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#github"
          ];
        };
        fetch = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#fetch"
          ];
        };
        nixos = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#nixos"
          ];
        };
        notion = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#notion"
          ];
        };
        serena = {
          command = "nix";
          args = [
            "run"
            "github:natsukium/mcp-servers-nix#serena"
          ];
        };
      };
    };
  };
}
