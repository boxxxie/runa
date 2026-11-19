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
> **Suite:** `temple` · **Commit:** `fdfabeed9db3` · **Benchmarks:** 42 (26 zero-alloc) · **Samples/bench:** 50 (1 run)

### `html_escape` — HTML Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `clean_ascii_70b` | 50 | **43.95 ns** | 44.70 ns | ±0.12 ns | 22,753,746 | 1,519.0 MB/s | 1.0% | 0 |
| `dense_xss_88b` | 50 | **381.86 ns** | 402.78 ns | ±20.52 ns | 2,618,765 | 219.8 MB/s | 21.7% | 0 |
| `clean_64kb` | 50 | **26.74 µs** | 27.17 µs | ±41.11 ns | 37,401 | 2,337.6 MB/s | 0.5% | 0 |
| `mixed_xss_64kb` | 50 | **118.19 µs** | 119.60 µs | ±144.23 ns | 8,461 | 528.8 MB/s | 0.4% | 0 |

### `url_and_js` — URL Sanitization & JS / Magic Escaping

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `safe_url_relative` | 50 | **45.51 ns** | 50.39 ns | ±0.48 ns | 21,973,751 | 628.7 MB/s | 3.6% | 0 |
| `safe_url_https` | 50 | **58.12 ns** | 101.73 ns | ±3.82 ns | 17,206,082 | 672.8 MB/s | 21.5% | 0 |
| `safe_url_data_png` | 50 | **49.26 ns** | 51.30 ns | ±0.39 ns | 20,301,894 | 968.1 MB/s | 2.8% | 0 |
| `safe_url_blocked_js` | 50 | **25.58 ns** | 25.87 ns | ±0.06 ns | 39,089,163 | 969.2 MB/s | 0.9% | 0 |
| `url_param_fast_path` | 50 | **25.68 ns** | 29.79 ns | ±0.53 ns | 38,947,752 | 1,114.3 MB/s | 7.1% | 0 |
| `url_param_encoded_query` | 50 | **65.16 ns** | 119.19 ns | ±5.25 ns | 15,346,167 | 409.8 MB/s | 25.4% | 0 |
| `js_string_escape` | 50 | **142.71 ns** | 172.80 ns | ±4.40 ns | 7,007,180 | 320.8 MB/s | 10.5% | 0 |
| `magic_string_8word` | 50 | **174.78 ns** | 196.06 ns | ±6.55 ns | 5,721,555 | 272.8 MB/s | 12.7% | 0 |

### `formatting` — Numeric Writers, Formatters & Pipes

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `write_int_and_f64` | 50 | **60.89 ns** | 65.61 ns | ±1.07 ns | 16,422,229 | 391.5 MB/s | 6.1% | 0 |
| `write_large_numbers` | 50 | **67.21 ns** | 73.94 ns | ±1.08 ns | 14,879,692 | 439.9 MB/s | 5.5% | 0 |
| `fmt_strength_reduced` | 50 | **57.26 ns** | 74.51 ns | ±2.33 ns | 17,463,623 | 1,015.9 MB/s | 13.5% | 0 |
| `default_chained_pipe` | 50 | **103.27 ns** | 115.36 ns | ±2.04 ns | 9,683,315 | 341.7 MB/s | 6.8% | 0 |
| `fmt_escaped_streaming` | 50 | **462.53 ns** | 526.15 ns | ±10.87 ns | 2,162,041 | 84.5 MB/s | 8.1% | 0 |
| `fmt_raw` | 50 | **391.75 ns** | 443.98 ns | ±10.74 ns | 2,552,638 | 75.5 MB/s | 9.4% | 0 |
| `fmt_tprintf_escaped` | 50 | **548.64 ns** | 691.73 ns | ±19.58 ns | 1,822,678 | 71.3 MB/s | 12.1% | 3 (68 B) |

### `components` — Macros & Embedded Components

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `macro_badge` | 50 | **73.44 ns** | 80.68 ns | ±0.97 ns | 13,616,096 | 818.1 MB/s | 4.6% | 0 |
| `embed_badge` | 50 | **74.16 ns** | 78.94 ns | ±1.39 ns | 13,484,103 | 823.0 MB/s | 6.5% | 0 |

### `rendering` — End-to-End Template Rendering

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `card_reused_buf` | 50 | **78.37 ns** | 127.58 ns | ±4.34 ns | 12,760,397 | 1,070.9 MB/s | 18.1% | 0 |
| `card_approx_bytes` | 50 | **100.15 ns** | 109.60 ns | ±2.13 ns | 9,984,737 | 838.0 MB/s | 7.3% | 1 (109 B) |
| `card_unbuffered` | 50 | **141.40 ns** | 151.89 ns | ±2.94 ns | 7,072,243 | 593.5 MB/s | 7.2% | 3 (176 B) |
| `dashboard_50_reused_buf` | 50 | **16.17 µs** | 17.44 µs | ±586.01 ns | 61,844 | 901.0 MB/s | 12.4% | 0 |
| `dashboard_50_approx_bytes` | 50 | **16.71 µs** | 20.02 µs | ±370.34 ns | 59,832 | 871.7 MB/s | 7.6% | 1 (15.6 KB) |
| `dashboard_50_sized_16kb` | 50 | **16.82 µs** | 19.79 µs | ±360.64 ns | 59,463 | 866.3 MB/s | 7.4% | 1 (16.0 KB) |
| `dashboard_50_unbuffered` | 50 | **16.51 µs** | 17.43 µs | ±371.67 ns | 60,554 | 882.2 MB/s | 7.8% | 8 (18.3 KB) |

### `compiler_cli` — AOT Compiler CLI Pipeline

| Benchmark | Samples | Median | P95 | ±CI95 | Ops/s | Throughput | CV% | Allocs/op |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `stage1_ast_collect` | 50 | **993.33 µs** | 1.05 ms | ±15.06 µs | 1,007 | 33.5 MB/s | 5.3% | 7,687 (1.10 MB) |
| `lexer_tokenize` | 50 | **4.05 µs** | 4.21 µs | ±18.04 ns | 246,872 | 285.6 MB/s | 1.6% | 0 |
| `parse_expr_check` | 50 | **10.86 µs** | 10.91 µs | ±28.42 ns | 92,074 | 106.5 MB/s | 0.9% | 13 (6.9 KB) |
| `parse_complex_ast` | 50 | **10.30 µs** | 10.34 µs | ±42.99 ns | 97,079 | 29.6 MB/s | 1.5% | 67 (12.9 KB) |
| `inheritance_resolve_2level` | 50 | **14.61 µs** | 14.65 µs | ±12.69 ns | 68,456 | 122.3 MB/s | 0.3% | 32 (11.2 KB) |
| `inheritance_resolve_3level` | 50 | **4.80 µs** | 4.82 µs | ±3.29 ns | 208,471 | 213.1 MB/s | 0.2% | 37 (7.9 KB) |
| `embed_props_transpile` | 50 | **3.25 µs** | 3.39 µs | ±15.76 ns | 307,800 | 54.0 MB/s | 1.7% | 5 (984 B) |
| `diagnostic_undefined_macro` | 50 | **1.77 µs** | 1.96 µs | ±20.09 ns | 564,153 | 48.4 MB/s | 3.9% | 7 (1,013 B) |
| `diagnostic_multiframe_trace` | 50 | **11.39 µs** | 18.30 µs | ±707.67 ns | 87,796 | 85.5 MB/s | 19.5% | 38 (8.3 KB) |
| `pure_transpile_loc_on` | 50 | **6.00 µs** | 6.18 µs | ±23.17 ns | 166,641 | 872.6 MB/s | 1.4% | 0 |
| `pure_transpile_loc_off` | 50 | **5.13 µs** | 5.51 µs | ±48.62 ns | 194,881 | 820.0 MB/s | 3.3% | 0 |
| `full_parse_inherit_transpile` | 50 | **21.32 µs** | 27.45 µs | ±567.08 ns | 46,909 | 83.8 MB/s | 9.0% | 32 (11.2 KB) |
| `batch_compile_3_warm_cache` | 50 | **34.53 µs** | 61.01 µs | ±3.21 µs | 28,961 | 63.1 MB/s | 27.6% | 89 (21.3 KB) |
| `watch_snapshot_diff_32` | 50 | **1.68 µs** | 2.34 µs | ±71.62 ns | 595,712 | — | 14.0% | 0 |
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
