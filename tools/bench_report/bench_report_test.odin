package bench_report

import "core:strings"
import "core:testing"

@(test)
test_formatters_and_markdown_sanitization :: proc(t: ^testing.T) {
	s1 := format_commas_u64(22_753_746, context.allocator)
	defer delete(s1)
	testing.expect_value(t, s1, "22,753,746")

	s0 := format_commas_u64(0, context.allocator)
	defer delete(s0)
	testing.expect_value(t, s0, "0")

	d_ns := format_duration_ns(43.948, context.allocator)
	defer delete(d_ns)
	testing.expect_value(t, d_ns, "43.95 ns")

	d_us := format_duration_ns(26_737.28, context.allocator)
	defer delete(d_us)
	testing.expect_value(t, d_us, "26.74 µs")

	d_ms := format_duration_ns(1_047_450.9, context.allocator)
	defer delete(d_ms)
	testing.expect_value(t, d_ms, "1.05 ms")

	ci := format_ci95_ns(0.124, context.allocator)
	defer delete(ci)
	testing.expect_value(t, ci, "±0.12 ns")

	tp := format_throughput_mbs(2337.56, context.allocator)
	defer delete(tp)
	testing.expect_value(t, tp, "2,337.6 MB/s")

	sanitized := sanitize_markdown_cell(`a | b <tag> & "q"`, context.allocator)
	defer delete(sanitized)
	testing.expect_value(t, sanitized, `a \| b <tag> & "q"`)
}

@(test)
test_aot_templates_preserve_markdown_and_zero_leaks :: proc(t: ^testing.T) {
	records := []Hugi_Record {
		{
			commit = "abc123def456",
			suite_name = "temple",
			group_name = "compiler_cli",
			name = `fmt("<&>") | pipe`,
			full_name = "compiler_cli::watch_snapshot_diff_32",
			rank = 2,
			run_count = 2,
			samples = 100,
			p50_ns = 1678.66,
			p95_ns = 2338.50,
			ci95_ns = 71.62,
			cv_pct = 14.02,
			ops_per_sec = 595_711.97,
			mb_per_sec = 0.0,
		},
		{
			commit = "abc123def456",
			suite_name = "temple",
			group_name = "formatting",
			name = "fmt_strength_reduced",
			full_name = "formatting::fmt_strength_reduced",
			rank = 1,
			run_count = 2,
			samples = 100,
			p50_ns = 57.26,
			p95_ns = 74.51,
			ci95_ns = 2.33,
			cv_pct = 13.48,
			ops_per_sec = 17_463_622.88,
			mb_per_sec = 1015.93,
			temp_allocs_per_op = 3,
			temp_bytes_per_op = 68,
		},
	}

	suite_view := build_suite_report_view(records, context.temp_allocator)
	suite_md, suite_ok := render_suite_report(suite_view, context.allocator)
	testing.expect(t, suite_ok, "suite_report_tmpl should render cleanly")
	defer delete(suite_md)

	testing.expect(
		t,
		strings.contains(suite_md, "`fmt(\"<&>\") \\| pipe` | 100 (2 runs) | **1.68 µs**"),
		"raw Markdown must preserve quotes/angles/ampersands without HTML escaping and escape pipes",
	)
	testing.expect(
		t,
		!strings.contains(suite_md, "&quot;") &&
		!strings.contains(suite_md, "&lt;") &&
		!strings.contains(suite_md, "&amp;"),
		"suite_report output must not contain HTML entities",
	)
	testing.expect(
		t,
		strings.contains(suite_md, "| 595,712 | — | 14.0% | 0 |"),
		"zero mb_per_sec must render em-dash",
	)
	testing.expect(
		t,
		strings.contains(suite_md, "| 17,463,623 | 1,015.9 MB/s | 13.5% | 3 (68 B) |"),
		"temp allocs should be included in Allocs/op",
	)

	// Canonical group ordering puts `formatting` before `compiler_cli`
	fmt_idx := strings.index(suite_md, "### `formatting`")
	cli_idx := strings.index(suite_md, "### `compiler_cli`")
	testing.expect(t, fmt_idx >= 0 && cli_idx > fmt_idx, "formatting must precede compiler_cli")

	// Verify no blank lines inside Markdown tables
	testing.expect(
		t,
		!strings.contains(suite_md, "---: |\n\n|"),
		"no blank line after table header",
	)
	testing.expect(t, !strings.contains(suite_md, " |\n\n| `"), "no blank line between table rows")

	headline_view := build_headline_table_view(records, context.temp_allocator)
	headline_md, headline_ok := render_headline_table(headline_view, context.allocator)
	testing.expect(t, headline_ok, "headline_table_tmpl should render cleanly")
	defer delete(headline_md)

	testing.expect(
		t,
		strings.contains(headline_md, "`fmt(\"%s\" / \"%i\") (compile-time strength reduced)`"),
		"headline label must preserve double quotes without &quot;",
	)

	free_all(context.temp_allocator)
}

@(test)
test_replace_benchmark_markers_idempotent :: proc(t: ^testing.T) {
	doc := "Intro\n<!-- BEGIN_BENCHMARK_TABLE -->\nold\n<!-- END_BENCHMARK_TABLE -->\nOutro\n"
	updated, changed, err := replace_benchmark_markers(doc, "new table\n", context.allocator)
	testing.expect_value(t, err, "")
	testing.expect(t, changed, "first replace should report changed")
	defer delete(updated)

	expected := "Intro\n<!-- BEGIN_BENCHMARK_TABLE -->\nnew table\n<!-- END_BENCHMARK_TABLE -->\nOutro\n"
	testing.expect_value(t, updated, expected)

	updated2, changed2, err2 := replace_benchmark_markers(
		updated,
		"new table\n",
		context.allocator,
	)
	testing.expect_value(t, err2, "")
	testing.expect(t, !changed2, "second replace should report unchanged")
	testing.expect_value(t, updated2, "")
}
