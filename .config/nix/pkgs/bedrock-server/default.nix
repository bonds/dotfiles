{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
}:
stdenv.mkDerivation rec {
  pname = "bedrock-server";
  version = "1.26.32.2";

  src = fetchurl {
    url = "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-${version}.zip";
    hash = "sha256-d4iEPnHSt6+Kk+4wGDAB6c0jupad6Mnu96oG00pNvKs=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [unzip autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/minecraft $out/share/minecraft

    cp -v bedrock_server $out/lib/minecraft/

    for d in behavior_packs resource_packs definitions config data; do
      [ -d "$d" ] && cp -r "$d" $out/share/minecraft/
    done

    for f in allowlist.json permissions.json server.properties \
      packetlimitconfig.json profanity_filter.wlist; do
      [ -f "$f" ] && cp "$f" $out/share/minecraft/
    done

    runHook postInstall
  '';

  meta = {
    description = "Minecraft Bedrock Dedicated Server";
    homepage = "https://www.minecraft.net/download/server/bedrock";
    sourceProvenance = with lib; [sourceTypes.binaryNativeCode];
    license = lib.licenses.unfree;
    platforms = ["x86_64-linux"];
    maintainers = with lib; [];
  };
}
