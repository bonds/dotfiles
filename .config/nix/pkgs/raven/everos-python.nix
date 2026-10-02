{
  pkgs,
  python3,
}: let
  # The `everos-memory` plugin and its substrate. `everos` is on PyPI but
  # `everos-memory` is NOT — it ships as a wheel asset on the Raven release
  # (like the raven wheel itself), so both the plugin and the substrate are
  # built from prebuilt wheels here.
  #
  # All wheels are pure-Python (py3-none-any) EXCEPT the two native ones:
  #   - lancedb 0.34.0 — nixpkgs 26.05 ships 0.32.0, `everos` wants
  #     >=0.34,<0.35. Its macos wheel is cp39-abi3 (stable-ABI, works on 3.13)
  #     and self-contained, so no Rust build is needed.
  #   - pyarrow 25.0.1 — nixpkgs 26.05 ships 23.0.0, `everos` wants >=25.0.1.
  #     The wheel is matched to the interpreter it installs into, so it is
  #     selected per Python minor below.
  #
  # These cannot simply be extra entries in raven's propagatedBuildInputs:
  # the wheels of lancedb/lance-namespace declare a *range* on pyarrow
  # (>=16, >=19) which the standalone nixpkgs attrs satisfy with 23.0.0,
  # producing two pyarrow copies in one closure. Building the whole substrate
  # under a single `python3.override` scope keeps one pyarrow (25.0.1) and one
  # lancedb (0.34.0) in the closure.
  # pyarrow publishes one wheel per interpreter minor; pick the right one.
  pyarrowWheels = {
    "3.12" = {
      name = "pyarrow-25.0.1-cp312-cp312-macosx_12_0_arm64.whl";
      hash = "sha256-35YfLnrpz0lkWSWdeYZSxwYl9sCAZQ1pUvjAQFPFjuk=";
      url = "https://files.pythonhosted.org/packages/a6/e2/9ab15b88cbfac28e16419ce5439ec29234c5172cb8259301b4ba639bdec0/pyarrow-25.0.1-cp312-cp312-macosx_12_0_arm64.whl";
    };
    "3.13" = {
      name = "pyarrow-25.0.1-cp313-cp313-macosx_12_0_arm64.whl";
      hash = "sha256-x8U07APDWKduo+UF50wbau8pCvkMRE39CS2/4j51W4U=";
      url = "https://files.pythonhosted.org/packages/cc/8d/8f271a7a034c834910ec925d56fa4b29733b1380f5289419f5aaa3b02777/pyarrow-25.0.1-cp313-cp313-macosx_12_0_arm64.whl";
    };
    "3.14" = {
      name = "pyarrow-25.0.1-cp314-cp314-macosx_12_0_arm64.whl";
      hash = "sha256-vwtnI5DNy2QNcoj5a4Jtcf9OmrslSobImJC69RopzuY=";
      url = "https://files.pythonhosted.org/packages/36/4c/b525824ad3094076919273cd97db61fb3d78252dee76fa3b8dc8f76774aa/pyarrow-25.0.1-cp314-cp314-macosx_12_0_arm64.whl";
    };
  };
  pyarrowWheel = pyarrowWheels.${python3.pythonVersion};

  pinnedWheels = {
    # ── native / substrate pins ──────────────────────────────────────────
    lancedb = {
      version = "0.34.0";
      name = "lancedb-0.34.0-cp39-abi3-macosx_11_0_arm64.whl";
      hash = "sha256-xGLy5vkzytZZ/QF5OU6qtXisvJFR/i70G8KbNuzKUFg=";
      url = "https://files.pythonhosted.org/packages/df/f7/5262b9aa593f790757163c0165ab0da1dda054758901bea7e4f02c9cb633/lancedb-0.34.0-cp39-abi3-macosx_11_0_arm64.whl";
    };
    pyarrow = {
      version = "25.0.1";
      inherit (pyarrowWheel) name url hash;
    };

    # ── everalgo-* (the everos algorithm substrate) ──────────────────────
    everalgo-core = {
      version = "0.3.0";
      name = "everalgo_core-0.3.0-py3-none-any.whl";
      hash = "sha256-WiW3hKLSTiinYv7ldRF0powu2haMNTwzdAyjGDBpwCs=";
      url = "https://files.pythonhosted.org/packages/2b/5d/ad60747004d873b23443412a74449b39640f08c4f6548fd4442641c3ff17/everalgo_core-0.3.0-py3-none-any.whl";
    };
    everalgo-boundary = {
      version = "0.2.1";
      name = "everalgo_boundary-0.2.1-py3-none-any.whl";
      hash = "sha256-layJgikQQbVkGxPJFXkO8gzKjEQBjCAB/2CLE8eua40=";
      url = "https://files.pythonhosted.org/packages/73/6f/6cb00d36ee007360ac0e2e62c44da782ef881f0f5def9f9d5a64142d88fb/everalgo_boundary-0.2.1-py3-none-any.whl";
    };
    everalgo-clustering = {
      version = "0.2.1";
      name = "everalgo_clustering-0.2.1-py3-none-any.whl";
      hash = "sha256-QNLkLdZHKjYSawEt9b4IVeoakhUDyGMp/dXZAvKKvAQ=";
      url = "https://files.pythonhosted.org/packages/3c/41/76a14d1aa18a164eef0dd25b8fe43b2aca7a606c33c6af58ec9806a13762/everalgo_clustering-0.2.1-py3-none-any.whl";
    };
    everalgo-rank = {
      version = "0.4.1";
      name = "everalgo_rank-0.4.1-py3-none-any.whl";
      hash = "sha256-Z1qBidmuOCTHbSHZvECeDGKj/HMCPQJ0e8/ws5gqLJI=";
      url = "https://files.pythonhosted.org/packages/bb/1c/5e829ef1176a3e5d030b4a34ff5a0475dcc480d30fdcad7055d48b003e1e/everalgo_rank-0.4.1-py3-none-any.whl";
    };
    everalgo-agent-memory = {
      version = "0.4.0";
      name = "everalgo_agent_memory-0.4.0-py3-none-any.whl";
      hash = "sha256-mxHQZqYg34zD5tL6bNCIxE2aoy7vMLxVs8jnku/ua0s=";
      url = "https://files.pythonhosted.org/packages/5e/7c/98632538a43a1b9a14310e95dd3400c1768b0a15b89072a49ce87e06ba46/everalgo_agent_memory-0.4.0-py3-none-any.whl";
    };
    everalgo-user-memory = {
      version = "0.4.0";
      name = "everalgo_user_memory-0.4.0-py3-none-any.whl";
      hash = "sha256-pAzDuoqoBilCVy7VDjQ0iH+7nnPjHTGIUSRQZTTZ3D4=";
      url = "https://files.pythonhosted.org/packages/cf/ba/5c7e65281efae449b01b92f37181c39445f763a31b32f798da740413f17a/everalgo_user_memory-0.4.0-py3-none-any.whl";
    };
    everalgo-parser = {
      version = "0.2.1";
      name = "everalgo_parser-0.2.1-py3-none-any.whl";
      hash = "sha256-OHbImNg14q5OO9fy9hWF3p/4TBPaVPe71lj3lfjfAH8=";
      url = "https://files.pythonhosted.org/packages/3f/6d/0a79a847e48d4417846916229ad90b0f13e7d348f31c84af30f31a7e0607/everalgo_parser-0.2.1-py3-none-any.whl";
    };
    everalgo-knowledge = {
      version = "0.1.1";
      name = "everalgo_knowledge-0.1.1-py3-none-any.whl";
      hash = "sha256-aqb8cKZedfOA5Jl9xYtp2PXafv/PXE+83r1/5YygGjY=";
      url = "https://files.pythonhosted.org/packages/0a/8d/3f860b72987f2028facf51733e8e3d85d722808136ea3dd1314bf462b7bd/everalgo_knowledge-0.1.1-py3-none-any.whl";
    };

    # ── the substrate itself ─────────────────────────────────────────────
    everos = {
      version = "1.4.1";
      name = "everos-1.4.1-py3-none-any.whl";
      hash = "sha256-FkPSUZitZQeMHF7WbSCgvEtyNgNIh7/SkMJfah9H+DM=";
      url = "https://files.pythonhosted.org/packages/24/dc/c41d8c7461e48b1fac7333545a3f05e2035393201cde22019e8394a5ab83/everos-1.4.1-py3-none-any.whl";
    };

    # ── the Raven plugin ─────────────────────────────────────────────────
    # NOT on PyPI; ships as a release asset beside the raven wheel. Carries
    # `raven_everos/raven-plugin.toml` as package data (discovery reads it
    # through importlib.resources) and the `raven.plugins` entry point
    # `everos-memory = raven_everos`.
    everos-memory = {
      version = "1.4.0";
      name = "everos_memory-1.4.0-py3-none-any.whl";
      hash = "sha256-mxlmWY/rkjk7z8x0ON/Khv3imh0HaT0Fur+CNRM5Lig=";
      url = "https://github.com/EverMind-AI/Raven/releases/download/v0.2.3/everos_memory-1.4.0-py3-none-any.whl";
    };
  };

  # The `everos[multimodal]` extra: `everalgo-parser[svg]` -> cairosvg.
  # `everos-memory` 1.4.0 hard-pins `everos[multimodal]==1.4.1`, so the extra
  # is part of the required closure, not optional.
  everosPython = python3.override {
    packageOverrides = self: _super: let
      mk = {
        pname,
        version,
        url,
        name,
        hash,
        deps ? [],
        imports ? [],
      }:
        self.buildPythonPackage {
          inherit pname version;
          format = "wheel";
          src = pkgs.fetchurl {
            inherit url name;
            sha256 = hash;
          };
          propagatedBuildInputs = deps;
          doCheck = false;
          # nixpkgs 26.05's own versions satisfy the wheel's declared ranges
          # (e.g. textual 8.2.6 for >=8.2.7, jieba 0.42.1), so skip the strict
          # runtime-dep version check rather than vendoring more copies.
          dontCheckRuntimeDeps = true;
          pythonImportsCheck = imports;
        };
    in {
      pyarrow = mk {
        pname = "pyarrow";
        version = pinnedWheels.pyarrow.version;
        inherit (pinnedWheels.pyarrow) name url hash;
        deps = [self.numpy];
        imports = ["pyarrow"];
      };

      lancedb = mk {
        pname = "lancedb";
        version = pinnedWheels.lancedb.version;
        inherit (pinnedWheels.lancedb) name url hash;
        deps = [
          self.pyarrow
          self.deprecation
          self.lance-namespace
          self.numpy
          self.packaging
          self.pydantic
          self.tqdm
        ];
        imports = ["lancedb"];
      };

      everalgo-core = mk {
        pname = "everalgo-core";
        version = pinnedWheels.everalgo-core.version;
        inherit (pinnedWheels.everalgo-core) name url hash;
        deps = [self.openai self.pydantic self.tiktoken];
        imports = ["everalgo.config"];
      };

      everalgo-boundary = mk {
        pname = "everalgo-boundary";
        version = pinnedWheels.everalgo-boundary.version;
        inherit (pinnedWheels.everalgo-boundary) name url hash;
        deps = [self.asgiref self.everalgo-core];
        imports = ["everalgo.boundary.chat"];
      };

      everalgo-clustering = mk {
        pname = "everalgo-clustering";
        version = pinnedWheels.everalgo-clustering.version;
        inherit (pinnedWheels.everalgo-clustering) name url hash;
        deps = [self.everalgo-core self.numpy];
        imports = ["everalgo.clustering"];
      };

      everalgo-rank = mk {
        pname = "everalgo-rank";
        version = pinnedWheels.everalgo-rank.version;
        inherit (pinnedWheels.everalgo-rank) name url hash;
        deps = [self.asgiref self.everalgo-core];
        imports = ["everalgo.rank"];
      };

      everalgo-agent-memory = mk {
        pname = "everalgo-agent-memory";
        version = pinnedWheels.everalgo-agent-memory.version;
        inherit (pinnedWheels.everalgo-agent-memory) name url hash;
        deps = [
          self.asgiref
          self.everalgo-boundary
          self.everalgo-clustering
          self.everalgo-core
        ];
        imports = ["everalgo.agent_memory"];
      };

      everalgo-user-memory = mk {
        pname = "everalgo-user-memory";
        version = pinnedWheels.everalgo-user-memory.version;
        inherit (pinnedWheels.everalgo-user-memory) name url hash;
        deps = [
          self.asgiref
          self.everalgo-boundary
          self.everalgo-core
          self.pydantic
        ];
        imports = ["everalgo.user_memory"];
      };

      everalgo-parser = mk {
        pname = "everalgo-parser";
        version = pinnedWheels.everalgo-parser.version;
        inherit (pinnedWheels.everalgo-parser) name url hash;
        deps = [
          self.asgiref
          self.beautifulsoup4
          self.everalgo-core
          self.httpx
          self.pillow
          self.cairosvg
        ];
        imports = ["everalgo.parser"];
      };

      everalgo-knowledge = mk {
        pname = "everalgo-knowledge";
        version = pinnedWheels.everalgo-knowledge.version;
        inherit (pinnedWheels.everalgo-knowledge) name url hash;
        deps = [
          self.asgiref
          self.everalgo-core
          self.everalgo-parser
          self.tiktoken
        ];
        imports = ["everalgo.knowledge"];
      };

      everos = mk {
        pname = "everos";
        version = pinnedWheels.everos.version;
        inherit (pinnedWheels.everos) name url hash;
        deps = [
          self.aiosqlite
          self.alembic
          self.anyio
          self.apscheduler
          self.click
          self.everalgo-agent-memory
          self.everalgo-boundary
          self.everalgo-clustering
          self.everalgo-core
          self.everalgo-knowledge
          self.everalgo-rank
          self.everalgo-user-memory
          self.fastapi
          self.greenlet
          self.jieba
          self.lancedb
          self.openai
          self.portalocker
          self.prometheus-client
          self.pyarrow
          self.pydantic
          self.pydantic-settings
          self.python-multipart
          self.pyyaml
          self.sqlmodel
          self.structlog
          self.textual
          self.typer
          # `uvicorn[standard]`: the extra's backends, spelled out so no
          # eval of uvicorn's optional meta is needed.
          self.uvicorn
          self.httptools
          self.uvloop
          self.websockets
          self.python-dotenv
          self.watchfiles
          self.watchdog
        ];
        imports = ["everos"];
      };

      everos-memory = mk {
        pname = "everos-memory";
        version = pinnedWheels.everos-memory.version;
        inherit (pinnedWheels.everos-memory) name url hash;
        deps = [
          self.everos
          self.httpx
          self.loguru
          self.tomli-w
        ];
        imports = ["raven_everos"];
      };
    };
  };
in {
  inherit everosPython;

  # What raven must propagate: the plugin and every module it can reach at
  # runtime. Propagating the two top-level wheels carries their own
  # propagatedBuildInputs transitively, so the whole closure lands in raven's
  # environment.
  packages = [
    everosPython.pkgs.everos-memory
    everosPython.pkgs.everos
  ];

  # `raven web` re-spawns a bare python with only PYTHONPATH — makePythonPath
  # does not recurse, so raven's wrapper needs every site-packages dir spelled
  # out. All are taken from the overridden scope so the child sees pyarrow 25
  # / lancedb 0.34 (and the rebuilt lance-namespace), not nixpkgs' originals.
  pathPackages = with everosPython.pkgs; [
    everos-memory
    everos
    pyarrow
    lancedb
    deprecation
    lance-namespace
    numpy
    packaging
    tqdm
    everalgo-core
    everalgo-boundary
    everalgo-clustering
    everalgo-rank
    everalgo-agent-memory
    everalgo-user-memory
    everalgo-parser
    everalgo-knowledge
    aiosqlite
    alembic
    anyio
    apscheduler
    click
    fastapi
    greenlet
    jieba
    openai
    portalocker
    prometheus-client
    pydantic
    pydantic-settings
    python-multipart
    pyyaml
    sqlmodel
    structlog
    textual
    typer
    uvicorn
    httptools
    uvloop
    websockets
    python-dotenv
    watchfiles
    watchdog
    asgiref
    tiktoken
    beautifulsoup4
    pillow
    cairosvg
    httpx
    loguru
    tomli-w
  ];
}
