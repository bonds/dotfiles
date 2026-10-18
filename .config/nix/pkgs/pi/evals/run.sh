#!/usr/bin/env bash
# Routing evals for the agent context.
#
# Runs every case in cases.txt through `pi --print` in a throwaway directory
# and checks that the answer contains the expected substrings. The point is to
# make context edits measurable: after changing `~/AGENTS.md` or a skill
# description you get "9/13" instead of a feeling.
#
# Why the scratch dir is under $HOME: context files load from the working
# directory and its ancestors, so `~/AGENTS.md` only applies below `$HOME`.
# Running from /tmp would test a bare pi with none of this repo's context.
#
# Usage:
#   run.sh [cases.txt] [case-name ...]
#   MODEL=deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017 run.sh
#
# Before a rebuild (the skills under ~/.agents/skills are still nix-store
# symlinks from the previous generation), test the repo copies instead:
#   PI_EVAL_ARGS="--no-skills --skill $HOME/.config/nix/agent-skills" run.sh
#
# Cost: one small request per case on the cheap model (~$0.01 for the suite).
# Sessions are not saved (--no-session) so evals do not pollute `recall`.
# `set -u` is deliberately absent: macOS ships bash 3.2, where expanding an
# empty array under `set -u` is an error. Empty arrays use ${a[@]+"${a[@]}"}.
set -o pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cases="${1:-$here/cases.txt}"
if [[ $# -gt 0 ]]; then shift; fi
only=("$@")

model="${MODEL:-deepinfra/deepseek-ai/DeepSeek-V4-Flash}"
extra=()
if [[ -n ${PI_EVAL_ARGS:-} ]]; then
    read -r -a extra <<< "$PI_EVAL_ARGS"
fi
scratch="${HOME}/.cache/pi-evals"
timeout_cmd=()
if command -v timeout > /dev/null 2>&1; then
    timeout_cmd=(timeout 180)
elif command -v gtimeout > /dev/null 2>&1; then
    timeout_cmd=(gtimeout 180)
fi

if [[ ! -f $cases ]]; then
    echo "no such cases file: $cases" >&2
    exit 2
fi
if ! command -v pi > /dev/null 2>&1; then
    echo "pi is not on PATH" >&2
    exit 2
fi

name=""
prompt=""
expects=()
rejects=()
declare -a names=()
declare -a statuses=()
declare -a details=()

reset_case() {
    name=""
    prompt=""
    expects=()
    rejects=()
}

run_case() {
    if [[ -z $name || -z $prompt ]]; then
        return
    fi
    if [[ ${#only[@]} -gt 0 ]]; then
        local wanted=0
        local candidate
        for candidate in ${only[@]+"${only[@]}"}; do
            [[ $candidate == "$name" ]] && wanted=1
        done
        if [[ $wanted -eq 0 ]]; then
            reset_case
            return
        fi
    fi

    local dir="${scratch}/${name}"
    mkdir -p "$dir"

    local answer
    # `< /dev/null` matters: the case loop reads the cases file from stdin, and
    # pi would otherwise consume every remaining case as its own input.
    answer="$(cd "$dir" && ${timeout_cmd[@]+"${timeout_cmd[@]}"} pi \
        --print \
        --no-session \
        --no-mcp \
        --no-approve \
        --thinking minimal \
        --model "$model" \
        --tools read,grep,find,ls \
        ${extra[@]+"${extra[@]}"} \
        "$prompt" 2>&1 < /dev/null)"
    local rc=$?

    local problems=()
    local expected
    for expected in ${expects[@]+"${expects[@]}"}; do
        if ! printf '%s' "$answer" | grep -Fqi -- "$expected"; then
            problems+=("missing: ${expected}")
        fi
    done
    local rejected
    for rejected in ${rejects[@]+"${rejects[@]}"}; do
        if printf '%s' "$answer" | grep -Fqi -- "$rejected"; then
            problems+=("unexpected: ${rejected}")
        fi
    done
    if [[ $rc -ne 0 ]]; then
        problems+=("pi exited ${rc}")
    fi

    names+=("$name")
    if [[ ${#problems[@]} -eq 0 ]]; then
        statuses+=("PASS")
        details+=("")
        printf 'PASS  %s\n' "$name"
    else
        statuses+=("FAIL")
        details+=("$(printf '%s; ' ${problems[@]+"${problems[@]}"})$(printf '%s' "$answer" | tr '\n' ' ' | cut -c1-400)")
        printf 'FAIL  %s\n' "$name"
        printf '      %s\n' "$(printf '%s; ' ${problems[@]+"${problems[@]}"})"
        printf '      answer: %s\n' "$(printf '%s' "$answer" | tr '\n' ' ' | cut -c1-300)"
    fi

    reset_case
}

while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
        '### '*)
            run_case
            name="${line#\#\#\# }"
            ;;
        'prompt: '*)
            prompt="${line#prompt: }"
            ;;
        'expect: '*)
            expects+=("${line#expect: }")
            ;;
        'reject: '*)
            rejects+=("${line#reject: }")
            ;;
        '' | '#'*)
            ;;
        *)
            echo "unrecognized line in $cases: $line" >&2
            ;;
    esac
done < "$cases"
run_case

total=${#names[@]}
passed=0
for status in "${statuses[@]}"; do
    [[ $status == PASS ]] && passed=$((passed + 1))
done

echo
echo "${passed}/${total} passed (model ${model})"
if [[ $passed -ne $total ]]; then
    exit 1
fi
