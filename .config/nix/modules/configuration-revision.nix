{
  self,
  lib,
  isDarwin,
  ...
}:
{
  system.configurationRevision = self.rev or self.dirtyRev or null;
}
// lib.optionalAttrs (!isDarwin) {
  system.nixos.tags = lib.optionals (self ? rev) [self.rev];
}
