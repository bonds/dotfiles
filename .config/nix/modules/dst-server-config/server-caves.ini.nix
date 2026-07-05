cfg: ''
  [SHARD]
  is_master = false
  name = Caves

  [NETWORK]
  server_port = ${toString cfg.ports.caves}

  [STEAM]
  master_server_port = ${toString cfg.ports.cavesSteam}
  authentication_port = 8767

  [ACCOUNT]
  encode_user_path = true

  ${cfg.extraCavesConfig}
''
