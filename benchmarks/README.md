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
> **Suite:** `temple` · **Commit:** `b9417f73ddab` · **Benchmarks:** 42 (26 zero-alloc) · **Samples/bench:** 50 (1 run)

### `html_escape` — HTML Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `clean_ascii_70b` | 50 | **40.33 ns** | 41.10 ns | ±0.58 ns | 24,793,861 | 1,655.2 MB/s | 5.0% | 0 |
| `dense_xss_88b` | 50 | **145.24 ns** | 149.50 ns | ±0.70 ns | 6,885,247 | 577.8 MB/s | 1.7% | 0 |
| `clean_64kb` | 50 | **29.90 µs** | 30.44 µs | ±108.04 ns | 33,443 | 2,090.2 MB/s | 1.3% | 0 |
| `mixed_xss_64kb` | 50 | **71.57 µs** | 82.12 µs | ±1.30 µs | 13,971 | 873.2 MB/s | 6.4% | 0 |

### `url_and_js` — URL Sanitization & JS / Magic Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `safe_url_relative` | 50 | **33.84 ns** | 34.80 ns | ±0.49 ns | 29,547,822 | 845.4 MB/s | 5.0% | 0 |
| `safe_url_https` | 50 | **40.32 ns** | 42.34 ns | ±0.79 ns | 24,801,887 | 969.8 MB/s | 6.8% | 0 |
| `safe_url_data_png` | 50 | **38.85 ns** | 40.94 ns | ±1.29 ns | 25,741,998 | 1,227.5 MB/s | 11.5% | 0 |
| `safe_url_blocked_js` | 50 | **15.04 ns** | 16.78 ns | ±0.51 ns | 66,503,441 | 1,649.0 MB/s | 11.5% | 0 |
| `url_param_fast_path` | 50 | **15.86 ns** | 23.71 ns | ±0.81 ns | 63,064,474 | 1,804.3 MB/s | 17.0% | 0 |
| `url_param_encoded_query` | 50 | **35.93 ns** | 41.95 ns | ±0.90 ns | 27,834,770 | 743.3 MB/s | 8.6% | 0 |
| `js_string_escape` | 50 | **81.93 ns** | 98.43 ns | ±1.91 ns | 12,205,615 | 558.7 MB/s | 8.1% | 0 |
| `magic_string_8word` | 50 | **107.93 ns** | 119.44 ns | ±2.99 ns | 9,265,376 | 441.8 MB/s | 9.5% | 0 |

### `formatting` — Numeric Writers, Formatters & Pipes

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `write_int_and_f64` | 50 | **37.51 ns** | 40.99 ns | ±0.90 ns | 26,661,122 | 635.7 MB/s | 8.3% | 0 |
| `write_large_numbers` | 50 | **41.33 ns** | 53.48 ns | ±1.64 ns | 24,193,914 | 715.3 MB/s | 13.4% | 0 |
| `fmt_strength_reduced` | 50 | **36.03 ns** | 41.51 ns | ±0.97 ns | 27,757,343 | 1,614.8 MB/s | 9.2% | 0 |
| `default_chained_pipe` | 50 | **63.21 ns** | 93.74 ns | ±3.46 ns | 15,819,679 | 558.2 MB/s | 18.3% | 0 |
| `fmt_escaped_streaming` | 50 | **273.70 ns** | 278.68 ns | ±0.85 ns | 3,653,632 | 142.9 MB/s | 1.1% | 0 |
| `fmt_raw` | 50 | **229.68 ns** | 233.38 ns | ±0.60 ns | 4,353,886 | 128.7 MB/s | 0.9% | 0 |
| `fmt_tprintf_escaped` | 50 | **322.36 ns** | 328.64 ns | ±0.79 ns | 3,102,119 | 121.3 MB/s | 0.9% | 3 (68 B) |

### `components` — Macros & Embedded Components

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `macro_badge` | 50 | **51.00 ns** | 61.17 ns | ±1.59 ns | 19,609,010 | 1,178.1 MB/s | 10.8% | 0 |
| `embed_badge` | 50 | **50.01 ns** | 50.46 ns | ±0.13 ns | 19,997,732 | 1,220.6 MB/s | 0.9% | 0 |

### `rendering` — End-to-End Template Rendering

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `card_reused_buf` | 50 | **50.86 ns** | 51.51 ns | ±0.15 ns | 19,663,114 | 1,650.2 MB/s | 1.1% | 0 |
| `card_approx_bytes` | 50 | **64.65 ns** | 66.41 ns | ±0.29 ns | 15,467,614 | 1,298.1 MB/s | 1.6% | 1 (109 B) |
| `card_unbuffered` | 50 | **88.83 ns** | 90.55 ns | ±0.25 ns | 11,257,808 | 944.8 MB/s | 1.0% | 3 (176 B) |
| `dashboard_50_reused_buf` | 50 | **10.23 µs** | 10.38 µs | ±23.77 ns | 97,742 | 1,423.9 MB/s | 0.8% | 0 |
| `dashboard_50_approx_bytes` | 50 | **10.38 µs** | 10.49 µs | ±25.67 ns | 96,359 | 1,403.8 MB/s | 0.9% | 1 (15.6 KB) |
| `dashboard_50_sized_16kb` | 50 | **10.36 µs** | 10.52 µs | ±28.08 ns | 96,558 | 1,406.7 MB/s | 1.0% | 1 (16.0 KB) |
| `dashboard_50_unbuffered` | 50 | **10.45 µs** | 10.62 µs | ±27.41 ns | 95,685 | 1,394.0 MB/s | 0.9% | 8 (18.3 KB) |

### `compiler_cli` — AOT Compiler CLI Pipeline

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `stage1_ast_collect` | 50 | **583.07 µs** | 599.73 µs | ±2.23 µs | 1,715 | 57.1 MB/s | 1.3% | 7,687 (1.10 MB) |
| `lexer_tokenize` | 50 | **2.34 µs** | 2.38 µs | ±5.98 ns | 426,731 | 493.6 MB/s | 0.9% | 0 |
| `parse_expr_check` | 50 | **6.21 µs** | 6.33 µs | ±19.18 ns | 161,070 | 186.3 MB/s | 1.1% | 13 (6.9 KB) |
| `parse_complex_ast` | 50 | **6.18 µs** | 6.28 µs | ±15.41 ns | 161,798 | 49.4 MB/s | 0.9% | 67 (12.9 KB) |
| `inheritance_resolve_2level` | 50 | **8.35 µs** | 8.53 µs | ±25.85 ns | 119,726 | 214.0 MB/s | 1.1% | 32 (11.2 KB) |
| `inheritance_resolve_3level` | 50 | **2.90 µs** | 2.96 µs | ±7.68 ns | 344,254 | 351.9 MB/s | 0.9% | 37 (7.9 KB) |
| `embed_props_transpile` | 50 | **1.98 µs** | 2.00 µs | ±6.12 ns | 504,972 | 88.6 MB/s | 1.1% | 5 (984 B) |
| `diagnostic_undefined_macro` | 50 | **1.04 µs** | 1.06 µs | ±2.61 ns | 961,449 | 82.5 MB/s | 0.9% | 7 (1,013 B) |
| `diagnostic_multiframe_trace` | 50 | **6.54 µs** | 6.59 µs | ±20.53 ns | 152,978 | 149.0 MB/s | 1.1% | 38 (8.3 KB) |
| `pure_transpile_loc_on` | 50 | **3.72 µs** | 3.75 µs | ±6.79 ns | 268,663 | 1,406.9 MB/s | 0.6% | 0 |
| `pure_transpile_loc_off` | 50 | **3.20 µs** | 3.22 µs | ±3.23 ns | 312,551 | 1,315.1 MB/s | 0.4% | 0 |
| `full_parse_inherit_transpile` | 50 | **12.46 µs** | 12.54 µs | ±14.20 ns | 80,249 | 143.4 MB/s | 0.4% | 32 (11.2 KB) |
| `batch_compile_3_warm_cache` | 50 | **20.23 µs** | 20.51 µs | ±47.19 ns | 49,430 | 107.7 MB/s | 0.8% | 89 (21.3 KB) |
| `watch_snapshot_diff_32` | 50 | **933.92 ns** | 938.32 ns | ±1.82 ns | 1,070,753 | — | 0.7% | 0 |
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
