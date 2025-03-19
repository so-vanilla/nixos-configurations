let
  somura_vanilla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN06dm12KnxrWJ6AAjyjLHXYbvjxL26QR9xZlfKeL6bO";
  somura_chocolate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICpLknzjjRI5ocXsoPC9xKCqmVmq17ddgEOqogxZYPPI";
  users = [ somura_vanilla somura_chocolate ];

  vanilla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHy9skF2XWJ6eJ5lx9OpiL60ExkgQuh1OqpEbSM7UT32";
  chocolate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAm7YMm9zfTuPs1U9tEPhR07/Rl0Fer4LEjrltCFK7Xo";
  systems = [ vanilla chocolate ];
in
{
  "general.fish.age".publicKeys = users ++ systems;
  "links.fish.age".publicKeys = users ++ systems;
}
