#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$ROOT/.build/release/apple-vision-ocr"
PAGE_COUNT="${1:-120}"
if [[ "$#" -gt 0 ]]; then
    shift
fi
if [[ "$#" -gt 0 ]]; then
    WORKER_COUNTS=("$@")
else
    WORKER_COUNTS=(1 4 8 12)
fi

if [[ ! -x "$BINARY" ]]; then
    echo "Missing release binary: $BINARY" >&2
    echo "swift build -c release --product apple-vision-ocr" >&2
    exit 1
fi
if [[ ! "$PAGE_COUNT" =~ '^[1-9][0-9]*$' ]]; then
    echo "PAGE_COUNT must be a positive integer" >&2
    exit 2
fi
for workers in "${WORKER_COUNTS[@]}"; do
    if [[ ! "$workers" =~ '^[1-9][0-9]*$' ]] || (( workers != 1 && (workers < 2 || workers > 16) )); then
        echo "WORKER_COUNTS must be 1 or integers from 2 through 16" >&2
        exit 2
    fi
done

BENCH_DIR="$ROOT/.build/bench"
FIXTURE="$BENCH_DIR/dense-$PAGE_COUNT.pdf"
mkdir -p "$BENCH_DIR"
if [[ -f "$FIXTURE" ]]; then
    echo "Reusing fixture: $FIXTURE"
else
    /usr/bin/python3 "$ROOT/scripts/make-bench-fixture.py" "$FIXTURE" "$PAGE_COUNT"
fi

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apple-vision-ocr-bench.XXXXXX")"
ACTIVE_PID=""
SAMPLER_PID=""
cleanup() {
    if [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        kill "$ACTIVE_PID" 2>/dev/null || true
        wait "$ACTIVE_PID" 2>/dev/null || true
    fi
    if [[ -n "$SAMPLER_PID" ]] && kill -0 "$SAMPLER_PID" 2>/dev/null; then
        kill "$SAMPLER_PID" 2>/dev/null || true
        wait "$SAMPLER_PID" 2>/dev/null || true
    fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

sample_process_tree() {
    local root_pid="$1"
    local result_path="$2"
    local maximum=0
    local current
    while kill -0 "$root_pid" 2>/dev/null; do
        current="$(ps -axo pid=,ppid=,rss= | awk -v root="$root_pid" '
            { pid[NR] = $1; parent[NR] = $2; rss[NR] = $3 }
            END {
                included[root] = 1
                changed = 1
                while (changed) {
                    changed = 0
                    for (i = 1; i <= NR; i++) {
                        if (included[parent[i]] && !included[pid[i]]) {
                            included[pid[i]] = 1
                            changed = 1
                        }
                    }
                }
                for (i = 1; i <= NR; i++) {
                    if (included[pid[i]]) total += rss[i]
                }
                print total + 0
            }
        ')"
        if (( current > maximum )); then
            maximum="$current"
        fi
        sleep 0.2
    done
    print -r -- "$maximum" > "$result_path"
}

SUMMARY_PATH="$RUN_DIR/summary.tsv"
: > "$SUMMARY_PATH"

for workers in "${WORKER_COUNTS[@]}"; do
    WALL_PATH="$RUN_DIR/wall-$workers.txt"
    PEAK_PATH="$RUN_DIR/peak-$workers.txt"
    SPREAD_PATH="$RUN_DIR/spread-$workers.txt"
    : > "$WALL_PATH"
    : > "$PEAK_PATH"
    : > "$SPREAD_PATH"

    for run in 1 2 3; do
        OUTPUT_PATH="$RUN_DIR/output.txt"
        STDERR_PATH="$RUN_DIR/stderr-$workers-$run.txt"
        STDOUT_PATH="$RUN_DIR/stdout-$workers-$run.txt"
        RSS_PATH="$RUN_DIR/rss-$workers-$run.txt"
        rm -f "$OUTPUT_PATH"

        command=("$BINARY" "$FIXTURE" --txt-only --txt-output "$OUTPUT_PATH")
        if (( workers != 1 )); then
            command+=(--split-workers "$workers")
        fi

        /usr/bin/time -p /usr/bin/env APPLE_VISION_OCR_SPLIT_TIMING=1 \
            "${command[@]}" > "$STDOUT_PATH" 2> "$STDERR_PATH" &
        ACTIVE_PID="$!"
        sample_process_tree "$ACTIVE_PID" "$RSS_PATH" &
        SAMPLER_PID="$!"

        run_status=0
        wait "$ACTIVE_PID" || run_status="$?"
        ACTIVE_PID=""
        wait "$SAMPLER_PID"
        SAMPLER_PID=""
        if (( run_status != 0 )); then
            cat "$STDERR_PATH" >&2
            echo "benchmark run failed: workers=$workers run=$run status=$run_status" >&2
            exit "$run_status"
        fi

        wall="$(awk '$1 == "real" { value = $2 } END { print value }' "$STDERR_PATH")"
        peak_kb="$(<"$RSS_PATH")"
        peak_mb="$(awk -v kb="$peak_kb" 'BEGIN { printf "%.1f", kb / 1024 }')"
        print -r -- "$wall" >> "$WALL_PATH"
        print -r -- "$peak_mb" >> "$PEAK_PATH"

        if (( workers == 1 )); then
            echo "workers 1 run $run: wall ${wall}s | peak RSS ${peak_mb} MB | worker spread n/a"
        else
            durations=("${(@f)$(awk '/^\[split\] worker / { sub(/s$/, "", $NF); print $NF }' "$STDERR_PATH")}")
            if (( ${#durations[@]} == 0 )); then
                echo "no per-worker timing lines captured: workers=$workers run=$run" >&2
                exit 1
            fi
            fastest="$(printf '%s\n' "${durations[@]}" | sort -n | head -1)"
            slowest="$(printf '%s\n' "${durations[@]}" | sort -n | tail -1)"
            spread="$(awk -v fastest="$fastest" -v slowest="$slowest" 'BEGIN { printf "%.2f", slowest - fastest }')"
            print -r -- "$spread" >> "$SPREAD_PATH"
            echo "workers $workers run $run: wall ${wall}s | peak RSS ${peak_mb} MB | fastest ${fastest}s | slowest ${slowest}s | spread ${spread}s"
        fi
    done

    median_wall="$(sort -n "$WALL_PATH" | sed -n '2p')"
    peak_mb="$(sort -nr "$PEAK_PATH" | head -1)"
    if (( workers == 1 )); then
        median_spread="n/a"
    else
        median_spread="$(sort -n "$SPREAD_PATH" | sed -n '2p')"
    fi
    printf '%s\t%s\t%s\t%s\n' "$workers" "$median_wall" "$peak_mb" "$median_spread" >> "$SUMMARY_PATH"
done

echo
printf '%-8s | %13s | %11s | %15s\n' "workers" "median wall s" "peak RSS MB" "worker spread s"
printf '%-8s-+-%13s-+-%11s-+-%15s\n' "--------" "-------------" "-----------" "---------------"
while IFS=$'\t' read -r workers wall peak spread; do
    printf '%-8s | %13s | %11s | %15s\n' "$workers" "$wall" "$peak" "$spread"
done < "$SUMMARY_PATH"
