{
  config,
  pkgs,
  pkgs-unstable,
  ...
}: let
  userHome = import ../../lib/user-home.nix pkgs;
in {
  imports = [
    ./hardware-configuration.nix
    ./security.nix
    ./networking.nix
    ./services.nix
    ./storage.nix
    ../../modules/ollama-server.nix
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
      owner = "dst";
      group = "dst";
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

  services.syncthing = let
    syncthingIds = import ../../lib/syncthing-ids.nix;
  in {
    enable = true;
    openDefaultPorts = true;
    user = "scott";
    group = "users";
    configDir = "${config.users.users.scott.home}/.config/syncthing";
    settings = {
      devices."accismus" = {id = syncthingIds.accismus;};
      folders."Documents" = {
        path = "${config.users.users.scott.home}/Documents";
        id = "mz9zh-usrfi";
        devices = ["accismus"];
      };
    };
  };

  services.ollama-server.enable = true;
  services.ollama = {
    models = "/dragon/servers/ollama";
    host = "0.0.0.0";
  };
  networking.firewall.allowedTCPPorts = [11434];

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
    users.scott = {...}: {
      home.homeDirectory = config.users.users.scott.home;

      imports = [
        ../../modules/home/base.nix
      ];
    };
  };

  system.stateVersion = "26.05";
}
