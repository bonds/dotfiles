cfg: ''
  [SHARD]
  is_master = true

  [NETWORK]
  server_port = ${toString cfg.ports.master}

  [STEAM]
  master_server_port = ${toString cfg.ports.masterSteam}
  authentication_port = 8766

  [ACCOUNT]
  encode_user_path = true

  ${cfg.extraMasterConfig}
''
