self: [
  "${self}/modules/nix.nix"
  "${self}/modules/configuration-revision.nix"
  "${self}/modules/ssh-authorized-keys.nix"
  "${self}/modules/secrets-check.nix"
  "${self}/modules/packages/dev.nix"
  "${self}/modules/packages/utils.nix"
  "${self}/modules/home/common.nix"
  "${self}/modules/nix-registry.nix"
  "${self}/modules/fish-command-not-found.nix"
]
