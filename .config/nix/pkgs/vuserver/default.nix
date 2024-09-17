{ lib
, python3Packages
, fetchFromGitHub
, makeWrapper
}:

python3Packages.buildPythonApplication rec {
  pname = "vuserver";
  version = "20240329";

  src = fetchFromGitHub {
    owner = "SasaKaranovic";
    repo = "VU-Server";
    rev = "v${version}";
    sha256 = "sha256-K2oJrqgNGRus5bvYHdhtyDQeHvCbW+fAlQLMn00Ovco=";
  };

  format = "other";

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = with python3Packages; [
    tornado
    numpy
    pillow
    requests
    pyyaml
    ruamel-yaml
    pyserial
  ];

  dontBuild = true;

  patchPhase = ''
    substituteInPlace dials/base_logger.py \
      --replace "logFile = f'/home/{getpass.getuser()}/KaranovicResearch/vudials/server.log'" \
                "logFile = os.path.join(os.environ.get('LOGSDIR'), 'vuserver.log')"
    substituteInPlace server.py \
      --replace "pid_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), file_name)" \
                "pid_file = os.path.join(os.environ.get('RUNTIMEDIR'), 'vuserver.pid')"
    substituteInPlace server.py \
      --replace "WEB_ROOT = os.path.join(BASEDIR_PATH, 'www')" \
                "WEB_ROOT = os.path.join(os.environ.get('RUNTIMEDIR'), 'www')"
    substituteInPlace database.py \
      --replace "database_path = os.path.join(os.path.dirname(__file__))" \
                "database_path = os.environ.get('STATEDIR')"
    # substituteInPlace server_config.py \
    #   --replace "server_default = {'hostname': 'localhost', 'port': 3000, 'communication_timeout': 10, 'master_key': 'cTpAWYuRpA2zx75Yh961Cg' }" \
    #             "server_default = YAML(typ='safe', pure=True).load(os.environ.get('CONFIG'))"
    substituteInPlace server_config.py \
      --replace "'port': 3000" \
                "'port': os.environ.get('PORT')"
    substituteInPlace server_config.py \
      --replace "'master_key': 'cTpAWYuRpA2zx75Yh961Cg'" \
                "'master_key': os.environ.get('KEY')"
    # substituteInPlace www/assets/js/vu1_gui_root.js \
    #   --replace "const API_MASTER_KEY = 'cTpAWYuRpA2zx75Yh961Cg';" \
    #             "const API_MASTER_KEY = '$KEY';"
  '';

  installPhase = ''
    mkdir -p "$out/lib"
    cp -r * "$out/lib"
    rm "$out/lib/config.yaml"

    makeWrapper \
      ${python3Packages.python.interpreter} \
      $out/bin/vuserver \
      --run "cp -r $out/lib/www /run/vuserver/www" \
      --run "chown -R vuserver:vuserver /run/vuserver/www" \
      --run "chmod 770 /run/vuserver/www/assets/js/" \
      --run "cat /tmp/vuserver.key | sed \"s/KEY=\(.*\)/const API_MASTER_KEY = '\1';/g\" > /run/vuserver/www/assets/js/vu1_gui_root.js.new" \
      --run "sed 1d /run/vuserver/www/assets/js/vu1_gui_root.js >> /run/vuserver/www/assets/js/vu1_gui_root.js.new" \
      --run "mv /run/vuserver/www/assets/js/vu1_gui_root.js.new /run/vuserver/www/assets/js/vu1_gui_root.js" \
      --chdir "$out/lib" \
      --add-flags "$out/lib/server.py" \
      --set PYTHONPATH "$PYTHONPATH:$out/lib" \
  '';

  doCheck = false;

  meta = with lib; {
    description = "VU Server for controlling VU dials";
    homepage = "https://github.com/SasaKaranovic/VU-Server";
    license = licenses.mit;
    maintainers = with maintainers; [ bonds ];
  };
}
