{config, ...}: {
  system.activationScripts.sshAuthorizedKeys = {
    text = ''
      mkdir -p ${config.users.users.scott.home}/.ssh
      ln -sf ${config.users.users.scott.home}/.config/ssh/keys ${config.users.users.scott.home}/.ssh/authorized_keys
    '';
    deps = [];
  };
}
