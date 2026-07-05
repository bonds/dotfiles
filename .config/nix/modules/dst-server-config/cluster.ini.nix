cfg: ''
  [NETWORK]
  cluster_name = ${cfg.clusterName}
  cluster_description = ${cfg.clusterDescription}
  cluster_password = ${cfg.clusterPassword}
  offline_cluster = false
  lan_only_cluster = false
  whitelist_slots = 1
  cluster_intention = social
  autosaver_enabled = true

  [GAMEPLAY]
  game_mode = ${cfg.gameMode}
  max_players = ${toString cfg.maxPlayers}
  pvp = ${
    if cfg.pvpEnabled
    then "true"
    else "false"
  }
  pause_when_empty = ${
    if cfg.pauseWhenEmpty
    then "true"
    else "false"
  }
  vote_kick_enabled = false

  [STEAM]
  steam_group_only = false
  steam_group_id = 0
  steam_group_admins = false

  [MISC]
  console_enabled = true
  max_snapshots = 6

  [SHARD]
  shard_enabled = true
  bind_ip = 127.0.0.1
  master_ip = 127.0.0.1
  master_port = ${toString cfg.ports.shardMaster}
  cluster_key = MsAhBOXhhnElO5IPKr4G

  ${cfg.extraClusterConfig}
''
