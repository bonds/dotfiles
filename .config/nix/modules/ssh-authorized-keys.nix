{
  config,
  isDarwin,
  ...
}: let
  text = ''
    mkdir -p ${config.users.users.scott.home}/.ssh
    ln -sf ${config.users.users.scott.home}/.config/ssh/keys ${config.users.users.scott.home}/.ssh/authorized_keys
  '';
in
  if isDarwin
  then {
    # nix-darwin 26.05 ignores custom activationScripts names (and `deps`);
    # only its built-in attr names are rendered. Put it in extraActivation.
    system.activationScripts.extraActivation.text = text;
  }
  else {
    system.activationScripts.sshAuthorizedKeys = {
      inherit text;
      deps = [];
    };
  }
