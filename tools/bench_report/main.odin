package bench_report

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

DEFAULT_HUGI_BIN :: "/home/pauli/.local/bin/hugi"
DEFAULT_DB_PATH :: "benchmarks/history.hugidb"
DEFAULT_SUITE_README :: "benchmarks/README.md"
DEFAULT_ROOT_README :: "README.md"

BEGIN_BENCHMARK_MARKER :: "<!-- BEGIN_BENCHMARK_TABLE -->"
END_BENCHMARK_MARKER :: "<!-- END_BENCHMARK_TABLE -->"

Hugi_Record :: struct {
	commit:             string,
	lang:               string,
	suite_name:         string,
	group_name:         string,
	name:               string,
	full_name:          string,
	run_id:             string,
	timestamp_unix:     i64,
	rank:               int,
	run_count:          int,
	ops_per_sample:     int,
	samples:            int,
	min_ns:             f64,
	p25_ns:             f64,
	p50_ns:             f64,
	p75_ns:             f64,
	p95_ns:             f64,
	p99_ns:             f64,
	max_ns:             f64,
	mean_ns:            f64,
	std_dev_ns:         f64,
	ci95_ns:            f64,
	cv_pct:             f64,
	iqr_ns:             f64,
	mad_ns:             f64,
	ops_per_sec:        f64,
	mb_per_sec:         f64,
	bytes_per_op:       u64,
	footprint_bytes:    u64,
	allocs_per_op:      f64,
	alloc_bytes_per_op: f64,
	temp_allocs_per_op: f64,
	temp_bytes_per_op:  f64,
	peak_heap_bytes:    u64,
}

Suite_Row_View :: struct {
	name:           string,
	samples:        int,
	run_count:      int,
	median:         string,
	p95:            string,
	ci95:           string,
	ops_per_sec:    string,
	throughput:     string,
	has_throughput: bool,
	cv_pct:         string,
	allocs:         string,
}

Suite_Group_View :: struct {
	name:  string,
	title: string,
	rows:  []Suite_Row_View,
}

Suite_Report_View :: struct {
	suite_name:       string,
	commit:           string,
	total_benchmarks: int,
	zero_alloc_count: int,
	samples_summary:  string,
	groups:           []Suite_Group_View,
}

Headline_Row_View :: struct {
	label:          string,
	median:         string,
	p95:            string,
	throughput:     string,
	has_throughput: bool,
	ops_per_sec:    string,
	allocs:         string,
}

Headline_Table_View :: struct {
	commit:          string,
	samples_summary: string,
	rows:            []Headline_Row_View,
}

Headline_Spec :: struct {
	full_name: string,
	label:     string,
}

CANONICAL_GROUPS :: [6]string {
	"html_escape",
	"url_and_js",
	"formatting",
	"components",
	"rendering",
	"compiler_cli",
}

HEADLINE_SPECS :: [10]Headline_Spec {
	{full_name = "html_escape::clean_64kb", label = "html_escape (clean 64KB doc)"},
	{full_name = "html_escape::mixed_xss_64kb", label = "html_escape (mixed XSS 64KB doc)"},
	{full_name = "url_and_js::safe_url_https", label = "safe_url (valid https URL)"},
	{
		full_name = "formatting::write_int_and_f64",
		label = "write_int + write_f64_prec (direct fast writers)",
	},
	{
		full_name = "formatting::fmt_strength_reduced",
		label = `fmt("%s" / "%i") (compile-time strength reduced)`,
	},
	{full_name = "rendering::card_reused_buf", label = "compiled_inline (card, reused buf)"},
	{
		full_name = "rendering::dashboard_50_reused_buf",
		label = "compiled (50-row dashboard, 15.3 KB HTML, reused buf)",
	},
	{
		full_name = "compiler_cli::lexer_tokenize",
		label = "cli: lexer tokenize (dashboard.temple.html)",
	},
	{
		full_name = "compiler_cli::pure_transpile_loc_on",
		label = "cli: pure transpile codegen (5.5 KB Odin code)",
	},
	{
		full_name = "compiler_cli::full_parse_inherit_transpile",
		label = "cli: full parse + inheritance + transpile",
	},
}

suite_report_tmpl := compiled("templates/suite_report.temple.twig", Suite_Report_View)
headline_table_tmpl := compiled("templates/headline_table.temple.twig", Headline_Table_View)

@(require_results)
sanitize_markdown_cell :: proc(s: string, allocator := context.allocator) -> string {
	needs_escape := false
	for i in 0 ..< len(s) {
		switch s[i] {
		case '|', '\r', '\n', '\t':
			needs_escape = true
		}
		if needs_escape {
			break
		}
	}
	if !needs_escape {
		return strings.clone(s, allocator)
	}

	sb := strings.builder_make(0, len(s) + 8, allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case '|':
			strings.write_string(&sb, `\|`)
		case '\r', '\n', '\t':
			strings.write_byte(&sb, ' ')
		case:
			strings.write_byte(&sb, c)
		}
	}
	return strings.to_string(sb)
}

@(require_results)
format_commas_u64 :: proc(val: u64, allocator := context.allocator) -> string {
	buf: [32]byte
	pos := len(buf)
	v := val
	digits := 0
	if v == 0 {
		pos -= 1
		buf[pos] = '0'
	} else {
		for v > 0 {
			if digits > 0 && digits % 3 == 0 {
				pos -= 1
				buf[pos] = ','
			}
			pos -= 1
			buf[pos] = byte('0' + (v % 10))
			v /= 10
			digits += 1
		}
	}
	return strings.clone(string(buf[pos:]), allocator)
}

@(require_results)
format_duration_ns :: proc(ns: f64, allocator := context.allocator) -> string {
	clamped := ns if ns > 0 else 0
	if clamped >= 1_000_000_000.0 {
		return fmt.aprintf("%.2f s", clamped / 1_000_000_000.0, allocator = allocator)
	}
	if clamped >= 1_000_000.0 {
		return fmt.aprintf("%.2f ms", clamped / 1_000_000.0, allocator = allocator)
	}
	if clamped >= 1_000.0 {
		return fmt.aprintf("%.2f µs", clamped / 1_000.0, allocator = allocator)
	}
	return fmt.aprintf("%.2f ns", clamped, allocator = allocator)
}

@(require_results)
format_ci95_ns :: proc(ci95_ns: f64, allocator := context.allocator) -> string {
	dur := format_duration_ns(ci95_ns, allocator)
	defer delete(dur, allocator)
	return fmt.aprintf("±%s", dur, allocator = allocator)
}

@(require_results)
format_ops_per_sec :: proc(ops_per_sec: f64, allocator := context.allocator) -> string {
	if ops_per_sec <= 0 {
		return strings.clone("0", allocator)
	}
	rounded := u64(math.round(ops_per_sec))
	return format_commas_u64(rounded, allocator)
}

@(require_results)
format_throughput_mbs :: proc(mb_per_sec: f64, allocator := context.allocator) -> string {
	tenths := u64(math.round(mb_per_sec * 10.0))
	whole := tenths / 10
	frac := tenths % 10
	whole_str := format_commas_u64(whole, allocator)
	defer delete(whole_str, allocator)
	return fmt.aprintf("%s.%d MB/s", whole_str, frac, allocator = allocator)
}

@(require_results)
format_cv_pct :: proc(cv_pct: f64, allocator := context.allocator) -> string {
	clamped := cv_pct if cv_pct > 0 else 0
	return fmt.aprintf("%.1f%%", clamped, allocator = allocator)
}

@(require_results)
format_alloc_bytes :: proc(bytes: f64, allocator := context.allocator) -> string {
	if bytes < 1024.0 {
		b_str := format_commas_u64(u64(math.round(bytes)), allocator)
		defer delete(b_str, allocator)
		return fmt.aprintf("%s B", b_str, allocator = allocator)
	}
	if bytes < 1024.0 * 1024.0 {
		return fmt.aprintf("%.1f KB", bytes / 1024.0, allocator = allocator)
	}
	return fmt.aprintf("%.2f MB", bytes / (1024.0 * 1024.0), allocator = allocator)
}

@(require_results)
format_allocs_summary :: proc(
	rec: Hugi_Record,
	allocator := context.allocator,
) -> (
	text: string,
	is_zero: bool,
) {
	total_allocs := rec.allocs_per_op + rec.temp_allocs_per_op
	total_bytes := rec.alloc_bytes_per_op + rec.temp_bytes_per_op
	if total_allocs < 0.005 && total_bytes < 0.5 {
		return strings.clone("0", allocator), true
	}

	rounded_allocs := math.round(total_allocs)
	count_str: string
	if math.abs(total_allocs - rounded_allocs) < 0.05 {
		count_str = format_commas_u64(u64(rounded_allocs), allocator)
	} else {
		count_str = fmt.aprintf("%.1f", total_allocs, allocator = allocator)
	}
	defer delete(count_str, allocator)

	if total_bytes < 0.5 {
		return strings.clone(count_str, allocator), false
	}
	bytes_str := format_alloc_bytes(total_bytes, allocator)
	defer delete(bytes_str, allocator)
	return fmt.aprintf("%s (%s)", count_str, bytes_str, allocator = allocator), false
}

@(require_results)
group_title_for :: proc(name: string) -> string {
	switch name {
	case "html_escape":
		return "HTML Escaping"
	case "url_and_js":
		return "URL Sanitization & JS / Magic Escaping"
	case "formatting":
		return "Numeric Writers, Formatters & Pipes"
	case "components":
		return "Macros & Embedded Components"
	case "rendering":
		return "End-to-End Template Rendering"
	case "compiler_cli":
		return "AOT Compiler CLI Pipeline"
	}
	return name
}

@(require_results)
pick_suite_metadata :: proc(
	records: []Hugi_Record,
	allocator := context.allocator,
) -> (
	suite_name: string,
	commit: string,
	samples_summary: string,
) {
	best_ts: i64 = -1
	raw_suite := "temple"
	raw_commit := "unknown"
	min_samples := max(int)
	max_samples := 0
	min_runs := max(int)
	max_runs := 0

	for rec in records {
		if rec.timestamp_unix >= best_ts && len(rec.commit) > 0 {
			best_ts = rec.timestamp_unix
			raw_commit = rec.commit
			if len(rec.suite_name) > 0 {
				raw_suite = rec.suite_name
			}
		} else if len(raw_commit) == 0 && len(rec.commit) > 0 {
			raw_commit = rec.commit
		}
		if rec.samples < min_samples {
			min_samples = rec.samples
		}
		if rec.samples > max_samples {
			max_samples = rec.samples
		}
		runs := rec.run_count if rec.run_count > 0 else 1
		if runs < min_runs {
			min_runs = runs
		}
		if runs > max_runs {
			max_runs = runs
		}
	}

	suite_name = sanitize_markdown_cell(raw_suite, allocator)
	commit = sanitize_markdown_cell(raw_commit, allocator)

	if len(records) == 0 {
		samples_summary = strings.clone("0", allocator)
		return
	}

	if min_samples == max_samples && min_runs == max_runs {
		if min_runs > 1 {
			samples_summary = fmt.aprintf(
				"%d (%d runs)",
				min_samples,
				min_runs,
				allocator = allocator,
			)
		} else {
			samples_summary = fmt.aprintf("%d (1 run)", min_samples, allocator = allocator)
		}
	} else if min_samples == max_samples {
		samples_summary = fmt.aprintf(
			"%d (%d–%d runs)",
			min_samples,
			min_runs,
			max_runs,
			allocator = allocator,
		)
	} else {
		samples_summary = fmt.aprintf("%d–%d", min_samples, max_samples, allocator = allocator)
	}
	return
}

@(require_results)
build_suite_report_view :: proc(
	records: []Hugi_Record,
	allocator := context.allocator,
) -> Suite_Report_View {
	suite_name, commit, samples_summary := pick_suite_metadata(records, allocator)

	grouped := make(map[string][dynamic]Hugi_Record, context.temp_allocator)
	extra_groups := make([dynamic]string, context.temp_allocator)

	for rec in records {
		gname := rec.group_name if len(rec.group_name) > 0 else "default"
		if gname not_in grouped {
			grouped[gname] = make([dynamic]Hugi_Record, context.temp_allocator)
			is_canonical := false
			for cg in CANONICAL_GROUPS {
				if cg == gname {
					is_canonical = true
					break
				}
			}
			if !is_canonical {
				append(&extra_groups, gname)
			}
		}
		append(&grouped[gname], rec)
	}

	ordered_groups := make([dynamic]string, 0, len(grouped), context.temp_allocator)
	for cg in CANONICAL_GROUPS {
		if cg in grouped {
			append(&ordered_groups, cg)
		}
	}
	for eg in extra_groups {
		append(&ordered_groups, eg)
	}

	group_views := make([]Suite_Group_View, len(ordered_groups), allocator)
	zero_alloc_count := 0

	for gname, gidx in ordered_groups {
		group_recs := grouped[gname][:]
		slice.stable_sort_by(group_recs, proc(a, b: Hugi_Record) -> bool {
			return a.rank < b.rank
		})

		rows := make([]Suite_Row_View, len(group_recs), allocator)
		for rec, ridx in group_recs {
			allocs_text, is_zero := format_allocs_summary(rec, allocator)
			if is_zero {
				zero_alloc_count += 1
			}
			has_tp := rec.mb_per_sec > 0
			tp_text := format_throughput_mbs(rec.mb_per_sec, allocator) if has_tp else ""

			rows[ridx] = Suite_Row_View {
				name           = sanitize_markdown_cell(rec.name, allocator),
				samples        = rec.samples,
				run_count      = rec.run_count if rec.run_count > 0 else 1,
				median         = format_duration_ns(rec.p50_ns, allocator),
				p95            = format_duration_ns(rec.p95_ns, allocator),
				ci95           = format_ci95_ns(rec.ci95_ns, allocator),
				ops_per_sec    = format_ops_per_sec(rec.ops_per_sec, allocator),
				throughput     = tp_text,
				has_throughput = has_tp,
				cv_pct         = format_cv_pct(rec.cv_pct, allocator),
				allocs         = allocs_text,
			}
		}

		group_views[gidx] = Suite_Group_View {
			name  = sanitize_markdown_cell(gname, allocator),
			title = sanitize_markdown_cell(group_title_for(gname), allocator),
			rows  = rows,
		}
	}

	return Suite_Report_View {
		suite_name = suite_name,
		commit = commit,
		total_benchmarks = len(records),
		zero_alloc_count = zero_alloc_count,
		samples_summary = samples_summary,
		groups = group_views,
	}
}

@(require_results)
build_headline_table_view :: proc(
	records: []Hugi_Record,
	allocator := context.allocator,
) -> Headline_Table_View {
	_, commit, _ := pick_suite_metadata(records, allocator)

	by_full_name := make(map[string]Hugi_Record, len(records), context.temp_allocator)
	for rec in records {
		if len(rec.full_name) > 0 {
			by_full_name[rec.full_name] = rec
		}
	}

	rows_dyn := make([dynamic]Headline_Row_View, 0, len(HEADLINE_SPECS), allocator)
	min_samples := max(int)
	max_samples := 0

	for spec in HEADLINE_SPECS {
		rec, found := by_full_name[spec.full_name]
		if !found {
			continue
		}
		if rec.samples < min_samples {
			min_samples = rec.samples
		}
		if rec.samples > max_samples {
			max_samples = rec.samples
		}

		allocs_text, _ := format_allocs_summary(rec, allocator)
		has_tp := rec.mb_per_sec > 0
		tp_text := format_throughput_mbs(rec.mb_per_sec, allocator) if has_tp else ""

		append(
			&rows_dyn,
			Headline_Row_View {
				label = sanitize_markdown_cell(spec.label, allocator),
				median = format_duration_ns(rec.p50_ns, allocator),
				p95 = format_duration_ns(rec.p95_ns, allocator),
				throughput = tp_text,
				has_throughput = has_tp,
				ops_per_sec = format_ops_per_sec(rec.ops_per_sec, allocator),
				allocs = allocs_text,
			},
		)
	}

	samples_summary: string
	if len(rows_dyn) == 0 {
		samples_summary = strings.clone("0 samples/benchmark", allocator)
	} else if min_samples == max_samples {
		samples_summary = fmt.aprintf("%d samples/benchmark", min_samples, allocator = allocator)
	} else {
		samples_summary = fmt.aprintf(
			"%d–%d samples/benchmark",
			min_samples,
			max_samples,
			allocator = allocator,
		)
	}

	return Headline_Table_View {
		commit = commit,
		samples_summary = samples_summary,
		rows = rows_dyn[:],
	}
}

@(require_results)
render_suite_report :: proc(
	view: Suite_Report_View,
	allocator := context.allocator,
) -> (
	rendered: string,
	ok: bool,
) {
	sb := strings.builder_make(0, suite_report_tmpl.approx_bytes, allocator)
	_, werr := suite_report_tmpl.with(strings.to_writer(&sb), view)
	if werr != nil {
		strings.builder_destroy(&sb)
		return "", false
	}
	return strings.to_string(sb), true
}

@(require_results)
render_headline_table :: proc(
	view: Headline_Table_View,
	allocator := context.allocator,
) -> (
	rendered: string,
	ok: bool,
) {
	sb := strings.builder_make(0, headline_table_tmpl.approx_bytes, allocator)
	_, werr := headline_table_tmpl.with(strings.to_writer(&sb), view)
	if werr != nil {
		strings.builder_destroy(&sb)
		return "", false
	}
	return strings.to_string(sb), true
}

@(require_results)
replace_benchmark_markers :: proc(
	content: string,
	rendered: string,
	allocator := context.allocator,
) -> (
	updated: string,
	changed: bool,
	err_msg: string,
) {
	begin_idx := strings.index(content, BEGIN_BENCHMARK_MARKER)
	if begin_idx == -1 {
		return "", false, "missing <!-- BEGIN_BENCHMARK_TABLE --> marker"
	}

	after_begin := begin_idx + len(BEGIN_BENCHMARK_MARKER)
	rel_end_idx := strings.index(content[after_begin:], END_BENCHMARK_MARKER)
	if rel_end_idx == -1 {
		return "", false, "missing <!-- END_BENCHMARK_TABLE --> marker"
	}
	end_idx := after_begin + rel_end_idx

	body := strings.trim(rendered, "\r\n")
	sb := strings.builder_make(0, len(content) + len(body) + 8, allocator)
	strings.write_string(&sb, content[:after_begin])
	strings.write_byte(&sb, '\n')
	strings.write_string(&sb, body)
	strings.write_byte(&sb, '\n')
	strings.write_string(&sb, content[end_idx:])

	result := strings.to_string(sb)
	if result == content {
		strings.builder_destroy(&sb)
		return "", false, ""
	}
	return result, true, ""
}

@(require_results)
update_markdown_file :: proc(
	path: string,
	rendered: string,
	allocator := context.allocator,
) -> (
	changed: bool,
	ok: bool,
) {
	raw_bytes, rerr := os.read_entire_file(path, allocator)
	if rerr != nil {
		fmt.eprintf("bench_report: failed to read %q: %v\n", path, rerr)
		return false, false
	}
	defer delete(raw_bytes, allocator)

	updated, did_change, err_msg := replace_benchmark_markers(
		string(raw_bytes),
		rendered,
		allocator,
	)
	if len(err_msg) > 0 {
		fmt.eprintf("bench_report: %q: %s\n", path, err_msg)
		return false, false
	}
	if !did_change {
		return false, true
	}
	defer delete(updated, allocator)

	werr := os.write_entire_file(path, transmute([]byte)updated)
	if werr != nil {
		fmt.eprintf("bench_report: failed to write %q: %v\n", path, werr)
		return false, false
	}
	return true, true
}

@(require_results)
exec_hugi_export_json :: proc(
	db_path: string,
	allocator := context.allocator,
) -> (
	json_bytes: []byte,
	ok: bool,
) {
	hugi_bin := DEFAULT_HUGI_BIN if os.exists(DEFAULT_HUGI_BIN) else "hugi"
	args := [8]string{hugi_bin, "export", "--db", db_path, "--format", "json", "--out", "-"}

	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = args[:]},
		allocator,
	)
	if exec_err != nil && hugi_bin != "hugi" {
		delete(stdout, allocator)
		delete(stderr, allocator)
		args[0] = "hugi"
		state, stdout, stderr, exec_err = os.process_exec(
			os.Process_Desc{command = args[:]},
			allocator,
		)
	}
	defer delete(stderr, allocator)

	if exec_err != nil {
		delete(stdout, allocator)
		fmt.eprintf("bench_report: failed to execute %q: %v\n", args[0], exec_err)
		return nil, false
	}
	if !state.success {
		err_text := strings.trim_space(string(stderr))
		delete(stdout, allocator)
		if len(err_text) > 0 {
			fmt.eprintf(
				"bench_report: hugi export exited with %d: %s\n",
				state.exit_code,
				err_text,
			)
		} else {
			fmt.eprintf("bench_report: hugi export exited with %d\n", state.exit_code)
		}
		return nil, false
	}
	return stdout, true
}

main :: proc() {
	if !os.exists(DEFAULT_DB_PATH) {
		fmt.eprintf("bench_report: missing benchmark database %q\n", DEFAULT_DB_PATH)
		os.exit(1)
	}

	json_bytes, exec_ok := exec_hugi_export_json(DEFAULT_DB_PATH, context.allocator)
	if !exec_ok {
		os.exit(1)
	}
	defer delete(json_bytes, context.allocator)

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	arena_alloc := mem.dynamic_arena_allocator(&arena)

	records: []Hugi_Record
	uerr := json.unmarshal(json_bytes, &records, allocator = arena_alloc)
	if uerr != nil {
		fmt.eprintf("bench_report: failed to parse hugi JSON export: %v\n", uerr)
		os.exit(1)
	}
	if len(records) == 0 {
		fmt.eprintln("bench_report: hugi JSON export returned 0 benchmark records")
		os.exit(1)
	}

	suite_view := build_suite_report_view(records, arena_alloc)
	headline_view := build_headline_table_view(records, arena_alloc)
	free_all(context.temp_allocator)

	suite_md, suite_render_ok := render_suite_report(suite_view, context.allocator)
	if !suite_render_ok {
		fmt.eprintln("bench_report: failed to render suite_report.temple.twig")
		os.exit(1)
	}
	defer delete(suite_md, context.allocator)

	headline_md, headline_render_ok := render_headline_table(headline_view, context.allocator)
	if !headline_render_ok {
		fmt.eprintln("bench_report: failed to render headline_table.temple.twig")
		os.exit(1)
	}
	defer delete(headline_md, context.allocator)

	suite_changed, suite_ok := update_markdown_file(
		DEFAULT_SUITE_README,
		suite_md,
		context.allocator,
	)
	if !suite_ok {
		os.exit(1)
	}

	root_changed, root_ok := update_markdown_file(
		DEFAULT_ROOT_README,
		headline_md,
		context.allocator,
	)
	if !root_ok {
		os.exit(1)
	}

	fmt.printf(
		"bench_report: rendered %d benchmarks (%d groups, commit %s) -> %s (%s), %s (%s)\n",
		suite_view.total_benchmarks,
		len(suite_view.groups),
		suite_view.commit,
		DEFAULT_SUITE_README,
		"updated" if suite_changed else "unchanged",
		DEFAULT_ROOT_README,
		"updated" if root_changed else "unchanged",
	)
}
