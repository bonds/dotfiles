# bge-m3 embeddings are not bitwise deterministic, so compare recall scores with a tolerance

**Date:** 2026-11-21

## Symptom

After rewriting the vector scan in `bin/mem` (skipping the keyword paths in `--mode semantic` and replacing the dot product's generator expression with `map(operator.mul)`), A/B-ing the old and new binaries showed the same texts with different scores: 0.6825 vs 0.6829, and 0.6515 vs 0.6514 on a re-run. Three of four queries matched byte for byte, the fourth differed by 0.0001.

## Cause

Deep Infra's `BAAI/bge-m3` returns a float vector whose low bits vary between calls for the same input. The exact integer dot product is not the variable: packing rounds the query's float components to int8, and a component sitting on a rounding boundary flips by one unit (1/16129 ≈ 0.00006 of cosine) from one call to the next. Two runs of the *same* binary a minute apart can therefore differ, which makes "identical output" a flaky acceptance test for any recall change.

## Fix / takeaway

Compare recall results with a tolerance, not for equality: same `(session, text)` set and scores within ~0.001, or compare only the ranking. When a difference is smaller than that, check the embedder before the code — call `mem recall` twice with the same binary and see whether it reproduces; if the two runs disagree with each other, the jitter is upstream. Observed 2026-11-21 while proving two speedups (4.8 s → 1.3 s on a semantic recall) did not change results.
