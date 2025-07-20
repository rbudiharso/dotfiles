{
  config,
  pkgs,
  nixgl,
  lib,
  ...
}:

{
  home.stateVersion = "25.05"; # Match your Home Manager release
  home.username = "rb";
  home.homeDirectory = "/home/rb";
  home.enableNixpkgsReleaseCheck = false;
  home.activation = {
    runStow = lib.hm.dag.entryAfter [ "installPackages" ] ''
      PATH="${config.home.path}/bin:$PATH"
      rm -rf ~/.config/atuin
      [ ! -d ~/.tmux/plugins/tpm ] && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
      cd ~/.dotfiles && \
        stow atuin \
        direnv \
        ghostty \
        kanshi \
        kubie \
        nvim \
        starship \
        tmux \
        wezterm \
        yazi \
        zshenv \
        zsh

      if [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        update-desktop-database
      fi
    '';
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  nixGL = {
    packages = import nixgl { inherit pkgs; };
  };

  # Install user packages
  home.packages = with pkgs; [
    ast-grep
    atuin
    awscli2
    chafa
    desktop-file-utils
    devbox
    direnv
    fd
    fish
    fzf
    gcc
    git
    gnome-tweaks
    gnomeExtensions.caffeine
    gnomeExtensions.pop-shell
    gnumake
    kubectl
    kubie
    lazygit
    lua51Packages.jsregexp
    lua51Packages.lua
    lua51Packages.luarocks-nix
    neovim
    nerd-fonts.blex-mono
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nixfmt-rfc-style
    redhat-official-fonts
    ripgrep
    rust-analyzer
    slack
    starship
    stow
    wl-clipboard
    yazi
  ];

  # Flatpak support
  services.flatpak = {
    enable = true;
    packages = [
      "app.freelens.Freelens"
      "com.spotify.Client"
      "md.obsidian.Obsidian"
    ];
    uninstallUnmanaged = true;
    update.onActivation = true;
  };

  # Manage dotfiles
  # home.file = {
  #   ".config/starship.toml" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/starship/.config/starship.toml";
  #   };
  #   ".zshenv" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/zshenv/.zshenv";
  #   };
  #   ".config/zsh/.zshrc" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/zsh/.config/zsh/.zshrc";
  #   };
  #   ".config/nvim" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/nvim/.config/nvim";
  #     recursive = true;
  #   };
  #   ".config/ghostty" = {
  #     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/ghostty/.config/ghostty";
  #     recursive = true;
  #   };
  # };

  # Configure programs
  # programs.zsh.enable = true;
  programs.gnome-shell.enable = true;

  programs.wezterm = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.wezterm;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.ghostty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.ghostty;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

}
