{
  outputs,
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs.python311Packages; [
    python-kasa
  ];
}
