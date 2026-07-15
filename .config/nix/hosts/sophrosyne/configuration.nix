{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  self,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos-common.nix
    ./security.nix
    ./networking.nix
    ./services.nix
    ./storage.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "sophrosyne";

  console.keyMap = "dvorak";

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.fish;
    packages = with pkgs; [];
  };

  environment.systemPackages = with pkgs; [
    pkgs-unstable.python313Packages.huggingface-hub
    nvme-cli
    util-linux
    dmidecode
    edac-utils
    lm_sensors
  ];

  services.openssh.settings.KbdInteractiveAuthentication = false;

  age.identityPaths = ["/etc/age/identity"];

  system.activationScripts.agenixIdentity = {
    deps = ["specialfs"];
    text = ''
      mkdir -p /etc/age
      if [ ! -f /etc/age/identity ]; then
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /etc/age/identity
        chmod 600 /etc/age/identity
      fi
    '';
  };

  system.activationScripts.agenixInstall.deps = ["agenixIdentity"];

  age.secrets = {
    ddns-token = {
      file = ../../secrets/ddns-token.age;
      owner = "scott";
      group = "root";
      mode = "0400";
    };
    email-pass = {
      file = ../../secrets/email-pass.age;
      owner = "scott";
      group = "root";
      mode = "0400";
    };
    dst-cluster-token = {
      file = ../../secrets/dst-cluster-token.age;
      owner = "scott";
      group = "root";
      mode = "0400";
    };
  };

  services.minecraft-bedrock = {
    enable = true;
    eula = true;
    dataDir = "/dragon/servers/minecraft";
    openFirewall = true;
  };

  services.dst-server = {
    enable = true;
    clusterTokenFile = config.age.secrets.dst-cluster-token.path;
    openFirewall = true;
  };

  programs.nix-ld.enable = true;

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "scott";
    group = "users";
    configDir = "${config.users.users.scott.home}/.config/syncthing";
    settings = {
      devices."accismus" = {id = "YH5SQ6S-U6AEOAS-F7JU4F2-YBBZFMH-VT2N6OA-BAVSABW-LBVHDZ7-R3FQLQ5";};
      folders."Documents" = {
        path = "${config.users.users.scott.home}/Documents";
        id = "mz9zh-usrfi";
        devices = ["accismus"];
      };
    };
  };

  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama;
    models = "/dragon/servers/ollama";
    host = "127.0.0.1";
  };

  programs.firesafe-backup = {
    enable = true;
    sources = {
      Archive = "/dragon/archive";
      Backups = "/dragon/backups";
      Documents = "/dragon/documents";
      "Media/audiobooks" = "/dragon/media/audiobooks";
      "Media/books" = "/dragon/media/books";
      "Media/iphone" = "/dragon/media/iphone";
      "Media/manuals" = "/dragon/media/manuals";
      "Media/music" = "/dragon/media/music";
      "Media/software" = "/dragon/media/software";
      Photos = "/dragon/media/photos";
      "Servers/Dontstarve" = "/dragon/servers/dontstarve/data";
      "Servers/Minecraft" = "/dragon/servers/minecraft";
    };
    emailRecipient = "root";
  };

  hardware.bluetooth.enable = true;
  hardware.rasdaemon.enable = true;

  home-manager = {
    users.scott = {pkgs, ...}: {
      home.stateVersion = "26.05";
      home.homeDirectory = config.users.users.scott.home;
      imports = [
        ../../modules/home/tmux.nix
        ../../modules/home/what-changed.nix
      ];
      programs.what-changed.enable = true;
    };
  };

  system.stateVersion = "26.05";
}
