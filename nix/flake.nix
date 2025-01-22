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
          pkgs.awscli2
          pkgs.bartender
          pkgs.bat
          pkgs.coreutils
          pkgs.discord
          pkgs.dive
          pkgs.elixir
          pkgs.fastfetch
          pkgs.fd
          pkgs.fzf
          pkgs.ghostty
          pkgs.google-chrome
          pkgs.htop
          pkgs.jq
          pkgs.kubectl
          pkgs.kubernetes-helm
          pkgs.kubeswitch
          pkgs.kubie
          pkgs.lazygit
          pkgs.lens
          pkgs.libyaml
          pkgs.lua51Packages.lua
          pkgs.luarocks
          pkgs.mkalias
          pkgs.ncdu
          pkgs.neovim
          pkgs.nmap
          pkgs.obsidian
          pkgs.opentofu
          pkgs.openvpn
          pkgs.p7zip
          pkgs.rectangle-pro
          pkgs.ripgrep
          pkgs.sqlite
          pkgs.starship
          pkgs.stow
          pkgs.tmux
          pkgs.tree
          pkgs.unnaturalscrollwheels
          pkgs.vifm
          pkgs.wezterm
          pkgs.wget
          pkgs.yazi
          pkgs.zoom-us
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
          "asdf"
          # "weaveworks/tap/eksctl"
        ];
        casks = [
          "appcleaner"
          "chatgpt"
          "dropbox"
          "firefox"
          "google-drive"
          "hammerspoon"
          "keyboardcleantool"
          "shottr"
          "the-unarchiver"
          "whisky"
          "yaak"
        ];
        taps = [
          "weaveworks/tap"
        ];
        masApps = {
          # "Firewatch" = 1164603847; # too big
          # "Stray" = 6451498949; # too big
          "Amphetamine" = 937984704;
          "Peek" = 1554235898;
          "Slack" = 803453959;
          "WhatApp" = 310633997;
          "Wireguard" = 1451685025;
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

      # use touch id when sudo
      security.pam.enableSudoTouchIdAuth = true;
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
