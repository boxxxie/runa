# Temple Benchmarks & Optimization Architecture

This directory contains the benchmark suite for **Temple**, measuring both **runtime rendering & context-aware escaping** (`runtime.odin`) and the **3-stage CLI compiler pipeline** (`cli/`).

---

## Running the Benchmarks

Run and record the benchmark suite via [`hugi`](../../hugi/README.md) (`-o:speed` is applied automatically):

```sh
# Optional: regenerate benchmarks/templates_gen.odin and verify no unused templates exist
odin run cli -- --warn-unused benchmarks -out:benchmarks/templates_gen.odin -pkg:benchmarks -temple-import:..

# Verify generated benchmark templates are up-to-date (used in CI)
odin run cli -- --check --warn-unused benchmarks -out:benchmarks/templates_gen.odin -pkg:benchmarks -temple-import:..

# Run the benchmark suite and ingest results into benchmarks/history.hugidb
hugi run benchmarks

# Compare the latest commit against the previous commit
hugi compare --last

# Optional: regenerate or verify the AOT report templates in tools/bench_report
odin run cli -- --warn-unused tools/bench_report -out:tools/bench_report/templates_gen.odin -pkg:bench_report -temple-import:../..
odin run cli -- --check --warn-unused tools/bench_report -out:tools/bench_report/templates_gen.odin -pkg:bench_report -temple-import:../..

# Regenerate both README.md and benchmarks/README.md tables from benchmarks/history.hugidb
odin run tools/bench_report
```

### Harness Methodology (`benchmarks/main.odin`)

* **Calibrated Timing & Untimed Allocation Checks (`hugi` / `obench`):** Hot loops execute in calibrated timed batches without allocation-counter overhead (`untimed_alloc_check = true` + vDSO `clock_gettime` on 64-bit Linux), followed by an untimed `Counting_Allocator` pass that enforces `@zero_alloc` invariants and reports exact heap/temp allocations per operation.
* **Compressed Transactional History (`benchmarks/history.hugidb`):** Runs are serialized as `HPKT` packets and ingested into an `xitdb` transactional history store with Byte-Stream-Split + zlib compression; regressions are checked via Mann-Whitney U and Welch `t`.
* **Isolated Buffer Modes:** Runtime benchmarks test both a pre-allocated 128 KB `strings.Builder` (measuring pure template execution and verifying `0 allocs/op`) and per-render buffer allocations using `Compiled.approx_bytes` vs unbuffered dynamic growth.
* **AOT Markdown Report Renderer (`tools/bench_report`):** Exports `benchmarks/history.hugidb` via `hugi export --format json` and renders both the grouped suite tables below and the headline summary in [`../README.md`](../README.md) using AOT-compiled `temple` templates (`suite_report.temple.twig` and `headline_table.temple.twig`).

---

## Benchmark Results (`-o:speed`)

<!-- BEGIN_BENCHMARK_TABLE -->
> **Suite:** `temple` · **Commit:** `7d07647be48c` · **Benchmarks:** 42 (26 zero-alloc) · **Samples/bench:** 50 (1 run)

### `html_escape` — HTML Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `clean_ascii_70b` | 50 | **43.32 ns** | 46.43 ns | ±0.68 ns | 23,083,628 | 1,541.0 MB/s | 5.4% | 0 |
| `dense_xss_88b` | 50 | **242.28 ns** | 243.82 ns | ±0.27 ns | 4,127,448 | 346.4 MB/s | 0.4% | 0 |
| `clean_64kb` | 50 | **26.66 µs** | 26.96 µs | ±100.15 ns | 37,508 | 2,344.2 MB/s | 1.3% | 0 |
| `mixed_xss_64kb` | 50 | **115.29 µs** | 134.97 µs | ±2.50 µs | 8,673 | 542.1 MB/s | 7.5% | 0 |

### `url_and_js` — URL Sanitization & JS / Magic Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `safe_url_relative` | 50 | **48.55 ns** | 71.62 ns | ±2.44 ns | 20,599,339 | 589.4 MB/s | 16.5% | 0 |
| `safe_url_https` | 50 | **62.53 ns** | 68.35 ns | ±1.00 ns | 15,991,723 | 625.3 MB/s | 5.6% | 0 |
| `safe_url_data_png` | 50 | **49.72 ns** | 51.40 ns | ±0.30 ns | 20,111,547 | 959.0 MB/s | 2.1% | 0 |
| `safe_url_blocked_js` | 50 | **24.44 ns** | 24.51 ns | ±0.01 ns | 40,909,605 | 1,014.4 MB/s | 0.1% | 0 |
| `url_param_fast_path` | 50 | **26.12 ns** | 27.49 ns | ±0.43 ns | 38,284,287 | 1,095.3 MB/s | 5.7% | 0 |
| `url_param_encoded_query` | 50 | **59.16 ns** | 72.82 ns | ±1.26 ns | 16,903,494 | 451.4 MB/s | 7.3% | 0 |
| `js_string_escape` | 50 | **139.64 ns** | 141.37 ns | ±0.18 ns | 7,161,179 | 327.8 MB/s | 0.4% | 0 |
| `magic_string_8word` | 50 | **173.08 ns** | 179.50 ns | ±1.00 ns | 5,777,838 | 275.5 MB/s | 2.0% | 0 |

### `formatting` — Numeric Writers, Formatters & Pipes

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `write_int_and_f64` | 50 | **61.38 ns** | 63.27 ns | ±0.29 ns | 16,293,036 | 388.5 MB/s | 1.7% | 0 |
| `write_large_numbers` | 50 | **67.17 ns** | 70.62 ns | ±0.44 ns | 14,888,452 | 440.2 MB/s | 2.3% | 0 |
| `fmt_strength_reduced` | 50 | **55.72 ns** | 56.01 ns | ±0.03 ns | 17,948,117 | 1,044.1 MB/s | 0.2% | 0 |
| `default_chained_pipe` | 50 | **99.73 ns** | 99.86 ns | ±0.11 ns | 10,027,548 | 353.8 MB/s | 0.4% | 0 |
| `fmt_escaped_streaming` | 50 | **465.20 ns** | 478.48 ns | ±1.86 ns | 2,149,597 | 84.1 MB/s | 1.4% | 0 |
| `fmt_raw` | 50 | **394.70 ns** | 399.37 ns | ±0.72 ns | 2,533,571 | 74.9 MB/s | 0.6% | 0 |
| `fmt_tprintf_escaped` | 50 | **561.39 ns** | 568.15 ns | ±1.38 ns | 1,781,284 | 69.6 MB/s | 0.9% | 3 (68 B) |

### `components` — Macros & Embedded Components

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `macro_badge` | 50 | **71.92 ns** | 72.52 ns | ±0.13 ns | 13,903,663 | 835.4 MB/s | 0.6% | 0 |
| `embed_badge` | 50 | **71.66 ns** | 73.15 ns | ±1.04 ns | 13,954,422 | 851.7 MB/s | 5.0% | 0 |

### `rendering` — End-to-End Template Rendering

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `card_reused_buf` | 50 | **74.54 ns** | 76.63 ns | ±0.94 ns | 13,416,297 | 1,125.9 MB/s | 4.4% | 0 |
| `card_approx_bytes` | 50 | **96.56 ns** | 97.33 ns | ±0.26 ns | 10,356,337 | 869.1 MB/s | 0.9% | 1 (109 B) |
| `card_unbuffered` | 50 | **141.13 ns** | 145.31 ns | ±0.65 ns | 7,085,794 | 594.7 MB/s | 1.6% | 3 (176 B) |
| `dashboard_50_reused_buf` | 50 | **16.21 µs** | 16.50 µs | ±64.24 ns | 61,697 | 898.8 MB/s | 1.4% | 0 |
| `dashboard_50_approx_bytes` | 50 | **16.11 µs** | 16.69 µs | ±99.84 ns | 62,072 | 904.3 MB/s | 2.2% | 1 (15.6 KB) |
| `dashboard_50_sized_16kb` | 50 | **16.05 µs** | 16.55 µs | ±79.74 ns | 62,313 | 907.8 MB/s | 1.7% | 1 (16.0 KB) |
| `dashboard_50_unbuffered` | 50 | **16.18 µs** | 16.67 µs | ±102.68 ns | 61,794 | 900.2 MB/s | 2.2% | 8 (18.3 KB) |

### `compiler_cli` — AOT Compiler CLI Pipeline

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `stage1_ast_collect` | 50 | **991.31 µs** | 1.01 ms | ±3.56 µs | 1,009 | 33.6 MB/s | 1.3% | 7,687 (1.10 MB) |
| `lexer_tokenize` | 50 | **3.83 µs** | 3.87 µs | ±5.49 ns | 260,966 | 301.9 MB/s | 0.5% | 0 |
| `parse_expr_check` | 50 | **10.81 µs** | 10.86 µs | ±9.20 ns | 92,481 | 107.0 MB/s | 0.3% | 13 (6.9 KB) |
| `parse_complex_ast` | 50 | **10.42 µs** | 10.46 µs | ±4.96 ns | 95,948 | 29.3 MB/s | 0.2% | 67 (12.9 KB) |
| `inheritance_resolve_2level` | 50 | **14.26 µs** | 14.36 µs | ±22.31 ns | 70,139 | 125.4 MB/s | 0.5% | 32 (11.2 KB) |
| `inheritance_resolve_3level` | 50 | **4.78 µs** | 8.26 µs | ±299.75 ns | 209,024 | 213.7 MB/s | 20.5% | 37 (7.9 KB) |
| `embed_props_transpile` | 50 | **3.24 µs** | 3.26 µs | ±4.19 ns | 308,679 | 54.2 MB/s | 0.5% | 5 (984 B) |
| `diagnostic_undefined_macro` | 50 | **1.86 µs** | 1.89 µs | ±3.18 ns | 536,477 | 46.0 MB/s | 0.6% | 7 (1,013 B) |
| `diagnostic_multiframe_trace` | 50 | **10.99 µs** | 11.03 µs | ±9.29 ns | 90,958 | 88.6 MB/s | 0.3% | 38 (8.3 KB) |
| `pure_transpile_loc_on` | 50 | **6.05 µs** | 6.06 µs | ±4.36 ns | 165,325 | 865.7 MB/s | 0.3% | 0 |
| `pure_transpile_loc_off` | 50 | **5.19 µs** | 5.24 µs | ±15.16 ns | 192,538 | 810.1 MB/s | 1.0% | 0 |
| `full_parse_inherit_transpile` | 50 | **21.18 µs** | 21.27 µs | ±16.55 ns | 47,209 | 84.4 MB/s | 0.3% | 32 (11.2 KB) |
| `batch_compile_3_warm_cache` | 50 | **33.31 µs** | 33.40 µs | ±10.65 ns | 30,022 | 65.4 MB/s | 0.1% | 89 (21.3 KB) |
| `watch_snapshot_diff_32` | 50 | **1.65 µs** | 1.65 µs | ±1.22 ns | 605,387 | — | 0.3% | 0 |
<!-- END_BENCHMARK_TABLE -->

---

## Runtime Optimization Deep Dive (`runtime.odin`)

### 1. Lookup-Table Fast Paths & Stack-Batched Cold Escapers
`__temple_write_escaped_string`, `__temple_write_url_param`, and `__temple_write_js_string` are split into a small, inlinable hot fast-path and a `@(optimization_mode = "favor_size")` cold slow-path:

* **`@(rodata)` 256-Byte Lookup Tables:** Each escaper indexes a constant 256-entry table (`HTML_ESCAPE_TABLE`, `URL_UNRESERVED_TABLE`, `JS_ESCAPE_TABLE`) in a tight loop. When an input string requires no escaping (the common case in HTML rendering), the fast path completes the scan and issues a single `io.write_string(w, str)` call (`~3.84 GB/s` on 64 KB clean HTML, `26.2 ns` on 70B ASCII).
* **256-Byte Stack-Buffered Batching:** When the fast scan encounters the first byte requiring escaping at index `first_esc`, it delegates to the slow path (`__temple_write_escaped_string_slow`, `__temple_write_url_param_slow`, `__temple_write_js_string_slow`) passing `first_esc` so prefix bytes are never rescanned. Instead of calling `io.write_string` for every entity and 1–3 byte run between special characters, the slow path coalesces prefixes, entity replacements, and contiguous unescaped runs into a `[256]byte` stack buffer before flushing to `w`.

### 2. Early-Exit URL Sanitizer (`__temple_write_safe_url`)
* **Relative URL Fast-Path:** Scans for `/`, `?`, `#`, or `:`. Any URL that hits `/`, `?`, or `#` before `:` (or contains no `:`) is immediately recognized as a safe relative URL without scheme parsing (`31.1 ns`).
* **Zero-Allocation Case-Insensitive Scheme Validation:** Uses allocation-free ASCII folding (`__temple_ascii_eq_fold`, `__temple_ascii_has_prefix_fold`) to allow `http`, `https`, `mailto`, `tel`, and safe non-SVG `data:image/{png,gif,jpeg,jpg,webp};` URIs while neutralizing obfuscated `javascript:` / `vbscript:` / `data:text/html` payloads to `#ZgotmplZ` in `17.4 ns`.

### 3. Direct Base-10 Integer & Fixed-Point Float Writers
Using `fmt.wprintf` for simple numeric fields incurs format-string parsing and `any` reflection overhead. Temple provides two specialized stack-buffered writers in `runtime.odin`:

* **`__temple_write_int`:** Uses a `@(rodata)` 200-byte two-digit lookup table (`DEC_DIGITS_2 = "000102...99"`). Single-digit (`0..9`) and two-digit (`10..99`) non-negative integers slice directly into `DEC_DIGITS_2` without a loop or stack copy; larger 64-bit signed integers are formatted two digits per division into a `[24]byte` stack buffer.
* **`__temple_write_f64_prec`:** Formats `f64` values with a fixed decimal precision (`0..6` decimal places, `|val| < 1e12`) using precomputed power-of-10 tables (`F64_POW10`, `U64_POW10`), round-half-to-even (banker's rounding matching `strconv.write_float` / `fmt.wprintf`), and `DEC_DIGITS_2` into a `[64]byte` stack buffer. Writing both a price (`$149.95`) and item count (`12`) with surrounding text takes **`38.3 ns` (`0 allocs`)** vs **`280.5 ns`** for `fmt.wprintf`.

### 4. Zero-Allocation Streaming `fmt` Adapter
For multi-argument format strings like `{{ fmt("%s: $%.2f (%i items)", this.title, this.price, this.count) }}`, Temple avoids `fmt.tprintf` (which allocates on `context.temp_allocator`). Instead, `__temple_write_fmt_escaped` and `__temple_write_fmt_raw` wrap the destination `io.Writer` in a stack-allocated `__Temple_Fmt_Writer` carrying a `[256]byte` stack buffer (`stack_buf`) and invoke `fmt.wprintf(..., flush = false)`. Small formatted outputs accumulate in `stack_buf` and flush in a single pass—running **1.7x faster** than `fmt.tprintf` with **0 allocations** (vs 3 allocations / 109 B per op).

### 5. Precomputed `approx_bytes` & Adaptive Loop Estimation
Every compiled template exposes `approx_bytes: int`:
* Static text nodes add their exact byte length.
* `if`/`elseif`/`else` and `switch`/`case` blocks add the maximum `approx_bytes` across branches.
* Hoisted `{% macro %}` declarations pre-calculate their body size so `{% call %}` sites add the target macro's estimated output size.
* `for` loops use an adaptive multiplier (`8x` for small inline loops; `60x` when the loop body is `>= 128` bytes, typical of table/grid rows).

For the 50-row dashboard benchmark (`15,276 B` actual rendered HTML), `dashboard_tmpl.approx_bytes` is `15,973 B`—allowing `strings.builder_make(0, dashboard_tmpl.approx_bytes)` to render the entire page in **1 allocation** instead of **8 reallocations (`37,155 B` allocated)** with an unbuffered builder.

---

## Compiler Pipeline Optimization Deep Dive (`cli/`)

### 1. Stage 1: Source Pre-Filtering & Copy-on-Write Scope Resolution
* **Fast Source Pre-Filter:** Before invoking `core:odin/parser` on a package directory, `collect_compile_calls` scans raw `.odin` source strings for `"temple"` or `"::"` constant declarations. During AST traversal, top-level procedure literals (`^ast.Proc_Lit`) whose source span does not contain `"compiled"`, `"::"`, or a known `temple` alias are skipped without walking their statement trees.
* **Copy-on-Write Lexical Scopes:** `File_Collect_Ctx` shares package-level constant and procedure-alias maps across procedures and blocks, cloning them (`ensure_owned_proc_aliases`, `ensure_owned_string_consts`) only when a local scope actually declares or shadows a constant or variable.

### 2. Stage 2: Slice Lexer, Unified AST Slab & Fast Expression Classifiers
* **Slice-Scanning Lexer (`447.6 MB/s`, `0 allocs/op`):** `lexer_consume_text_until_tag` and `lexer_consume_tag_expr` advance over raw HTML text and unquoted tag expressions in tight inner loops, slicing directly into the source buffer without per-token heap allocations.
* **Unified Parser & Inheritance Slab Allocators:** `Parser` (`alloc_parser_node`) and `Compile_Context` (`alloc_ctx_node`) bump-allocate AST nodes (`Node_Text`, `Node_Output`, `Node_If`, `Node_For`, `Node_Switch`, `Node_Case`, `Node_Let`, `Node_Block`, `Node_Call`, etc.) from a contiguous byte slab instead of issuing separate heap allocations per AST node.
* **Fast-Path Expression Classifiers:** Before spinning up `core:odin/parser`, the template parser checks lightweight classifiers (`try_fast_classify_output_expr`, `validate_if_condition_expr`, `validate_for_clause_expr`, `validate_case_expr`, `validate_let_assignment_expr`) that validate and classify common selectors (`this.host`), simple binary arithmetic (`idx + 1`), `len(...)`, type casts, single/two-stage pipe chains (`this.host | default("unknown")`, `this.latency_ms | fmt("%.2f ms")`), enum cases (`.Healthy`), and `for row, idx in this.rows` clauses with zero allocations. Complex Odin expressions transparently fall back to `core:odin/parser` using a `[512]byte` stack buffer for synthetic statement wrapping.
* **Compile-Time `fmt` Strength Reduction & Text Coalescing:** During parsing and layout flattening, `try_parse_simple_fmt_literal` detects single-argument `fmt` strings with `%s`, `%i`, `%d`, `%f`, or `%.Nf`. Static prefix and suffix literals are split out (and HTML-escaped at compile time unless piped to `| raw`) and merged with adjacent `Node_Text` nodes so surrounding HTML and format prefixes/suffixes emit as a single `io.write_string` call.
* **Inline Splicing Caches:** `Compile_Context` keeps 8-slot inline arrays (`inline_raw`, `inline_resolved`, `inline_stack`) for raw parsed templates, resolved layouts, and diagnostic trace frames so typical 2- and 3-level layout inheritance chains never allocate hash maps or dynamic trace arrays.

### 3. Stage 3: Zero-Allocation Codegen & Content-Diffed Output
* **Zero-Allocation Transpiler (`1,356.7 MB/s`, `0 allocs/op`):** `transpile` emits 5,491 bytes of formatted Odin code for `dashboard.temple.html` in `3.86 µs` (`3.26 µs` with `emit_loc = false`) with **0 heap or temp allocations**:
  * `write_quoted_fast` quotes clean and common escaped string literals using stack buffers (`[256]byte` / `[512]byte`) instead of `io.write_quoted_string`.
  * `transpile_loc` and `write_fast_uint` format `/* line:col in template */` comments and integer literals into a `[48]byte` stack buffer via `append_uint_digits`.
  * `write_newline` and `write_indent` slice into a constant `NEWLINE_TABS` string to emit `\n` plus up to 16 `\t` indentation levels in a single `io.write_string` call.
  * `Transpiler` tracks up to 8 in-file macros in fixed arrays (`macro_names: [8]string`, `macro_bytes: [8]int`) before falling back to a map.
* **No-Op Write Skipping:** At the end of compilation, `transpile_calls` compares the newly generated Odin body against the existing output file on disk (ignoring the timestamp header) and skips writing to disk when unchanged, avoiding unnecessary file-watcher triggers and downstream Odin rebuilds.
