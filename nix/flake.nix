{
  description = "rbudiharso nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    mac-app-util.url = "github:hraban/mac-app-util";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, mac-app-util }:
  let
    configuration = { pkgs, config, ... }: {

      nixpkgs.config.allowUnfree = true;
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [
          pkgs.neovim
          pkgs.tmux
          pkgs.ghostty
          pkgs.mkalias
          pkgs.obsidian
          pkgs.libyaml
          pkgs.sqlite
          pkgs.coreutils
          pkgs.asdf-vm
          pkgs.awscli2
          pkgs.bat
          pkgs.dive
          pkgs.docker
          pkgs.docker-compose
          pkgs.docker-buildx
          pkgs.elixir
          pkgs.fastfetch
          pkgs.fd
          pkgs.fzf
          pkgs.kubernetes-helm
          pkgs.kubectl
          pkgs.htop
          pkgs.jq
          pkgs.kubie
          pkgs.lazygit
          pkgs.luarocks
          pkgs.luajitPackages.luarocks-nix
          pkgs.nmap
          pkgs.ncdu
          pkgs.opentofu
          pkgs.p7zip
          pkgs.ripgrep
          pkgs.starship
          pkgs.stow
          pkgs.tree
          pkgs.vifm
          pkgs.wget
          pkgs.yazi
          pkgs.unnaturalscrollwheels
        ];

      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.nerd-fonts.fira-code
        pkgs.redhat-official-fonts
      ];

      homebrew = {
        enable = true;
        brews = [
          "mas"
        ];
        casks = [
          "hammerspoon"
          # "firefox"
          "the-unarchiver"
        ];
        masApps = {
          # "Firewatch" = 1164603847; # too big
          # "Stray" = 6451498949; # too big
          "Wireguard" = 1451685025;
          "WhatApp" = 310633997;
          "Amphetamine" = 937984704;
          "Slack" = 803453959;
        };
        onActivation.cleanup = "zap";
        onActivation.autoUpdate = true;
        onActivation.upgrade = true;
      };

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;
      programs.zsh.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;
      system.defaults = {
        dock.autohide = true;
        dock.persistent-apps = [
          "/System/Applications/System Settings.app"
          "/System/Applications/App Store.app"
          "/System/Applications/Mail.app"
          "/System/Applications/Calendar.app"
          "/Applications/Firefox.app"
          "/Applications/Slack.app"
          "/Applications/WhatsApp.app"
          "${pkgs.ghostty}/Applications/Ghostty.app"
          "${pkgs.obsidian}/Applications/Obsidian.app"
        ];
        finder._FXSortFoldersFirst = true;
        finder.FXPreferredViewStyle = "Nlsv";
        finder.FXRemoveOldTrashItems = true;
        finder.NewWindowTarget = "Home";
        finder.ShowPathbar = true;
        finder.ShowStatusBar = true;
        loginwindow.LoginwindowText = "Here be dragon";
        loginwindow.GuestEnabled = false;
        NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
        NSGlobalDomain.KeyRepeat = 2;
        SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
      };

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#mac
    darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        mac-app-util.darwinModules.default
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "rahmat";

            # Optional: Declarative tap management
            # taps = {
            # };

            # Optional: Enable fully-declarative tap management
            # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
            # mutableTaps = false;
          };
        }
      ];
    };

    # expose the package set, including overlays, for convenient
    darwinPackages = self.darwinConfigurations."mac".pkgs;
  };
}
