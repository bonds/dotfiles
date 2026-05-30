{
  self,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    (pkgs.runCommand "secrets-check"
      {
        buildInputs = [pkgs.gitleaks];
        preferLocalBuild = true;
        allowSubstitutes = false;
      } ''
        gitleaks detect \
          --source ${self} \
          --no-git \
          -c ${self}/.gitleaks.toml \
          --verbose \
          --exit-code 1 || (
          echo "Secrets found! Remove or allowlist them before building." && exit 1
        )
        mkdir -p $out
      '')
  ];
}
