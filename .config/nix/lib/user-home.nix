pkgs:
if pkgs.stdenv.hostPlatform.isDarwin
then "/Users/scott"
else "/home/scott"
