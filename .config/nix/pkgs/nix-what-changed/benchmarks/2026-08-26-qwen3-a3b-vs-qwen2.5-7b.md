# Model→qwen3.6-35b-a3b evaluation (2026-08-26)

**Verdict: keep `qwen2.5-7b`.**

`qwen3.6-35b-a3b` is a **reasoning model**. The stock `what-changed --benchmark`
scored it 0/4 because with a 128-token budget it spends *all* tokens on hidden
`reasoning_content` and never emits visible output.

With `chat_template_kwargs {enable_thinking: false}` (which the client does not
currently send), the honest comparison on the same curate prompt is:

| metric                 | qwen2.5-7b | qwen3.6-35b-a3b |
|------------------------|-----------|-----------------|
| generation speed       | ~5.0 tps  | **~7.2 tps**    |
| big-changelog summary  | 39.2 s (truncated `length`) | **26.6 s (completed `stop`)** |
| bullet quality (4 smp) | **0.82**  | 0.70            |

The a3b is ~45% faster (and finishes the big changelog without truncation) but
is lower-quality. First call also pays ~75 s auto-load. Since reliability was the
goal and quality matters for the nightly `nr` changelogs, we kept `qwen2.5-7b`.

If speed is ever preferred over quality, the switch needs (1) a one-line
`enable_thinking:false` kwarg in `summarize.py::_call_openai`, and (2) the
config model → `qwen3.6-35b-a3b`.