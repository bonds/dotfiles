# A dead opencode plugin reload poisons the server's provider registry

## Symptom

Every Deep Infra request failed with

```
SessionRunnerModel.ModelUnavailableError: Model unavailable: deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017
```

and `opencode models` listed only the built-in providers — no `deepinfra/` line
at all — even though `opencode debug config` showed the provider with its
resolved API key. A fresh `opencode run` failed identically, which makes it look
like `opencode.jsonc` had broken.

## Cause

`opencode run` and `opencode models` do not build their own provider registry:
they talk to the long-lived background service (`opencode service status`). While
`plugins/agent-model.js` was mid-edit it referenced a variable that did not exist
yet, so the server logged

```
level=ERROR message="failed to reload plugins" cause="Cause([Die(ReferenceError: probeHook is not defined)])"
```

and the aborted reload left the in-memory registry without the config-defined
providers. The on-disk config was valid the whole time; only that process was
stale. Nothing in the CLI surfaces this — the model just reads as unavailable.

## Fix

Check the log before suspecting the config, then restart the service:

```bash
rg 'failed to reload plugins' ~/.local/share/opencode/log/opencode.log
opencode service restart
opencode models | rg '^deepinfra/'   # provider is back
```

To rule the server out entirely, run a private one — if this works, the config is
fine and the service is the problem:

```bash
opencode run --standalone --model deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017 "hi"
```

Corollary: editing a file under `plugins/` triggers a hot reload on save, so save
it in a parseable state. A placeholder name (`const probeHook = ...` half
written) costs every config-defined provider until the next restart.
