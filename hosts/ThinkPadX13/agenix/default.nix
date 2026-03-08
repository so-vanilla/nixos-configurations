[
  {
    age.secrets = {
      general_fish = {
        file = ../../../secrets/general.fish.age;
        path = "/home/somura/.config/fish/general.fish";
        owner = "somura";
        group = "users";
      };
      links_fish = {
        file = ../../../secrets/links.fish.age;
        path = "/home/somura/.config/fish/links.fish";
        owner = "somura";
        group = "users";
      };
      emacs_private = {
        file = ../../../secrets/emacs-private.el.age;
        path = "/home/somura/.emacs.d/private.el";
        owner = "somura";
        group = "users";
      };
    };
  }
]
