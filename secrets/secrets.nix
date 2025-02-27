let
  somura_chocolate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICpLknzjjRI5ocXsoPC9xKCqmVmq17ddgEOqogxZYPPI";
  users = [ somura_chocolate ];

  chocolate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAm7YMm9zfTuPs1U9tEPhR07/Rl0Fer4LEjrltCFK7Xo";
  systems = [ chocolate ];
in
{
  "general.fish.age".publicKeys = users ++ systems;
  "links.fish.age".publicKeys = users ++ systems;
}
