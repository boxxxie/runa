package benchmarks

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:odin/ast"
import odin_parser "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strings"

import hugi "hugi:."
import runa ".."
import runa_cli "../cli"

Host_State :: enum {
	Healthy,
	Degraded,
	Offline,
}

Host_Row :: struct {
	host:       string,
	region:     string,
	endpoint:   string,
	latency_ms: f64,
	state:      Host_State,
}

Dashboard_Ctx :: struct {
	page_title: string,
	boot_token: string,
	docs_url:   string,
	env:        string,
	rows:       []Host_Row,
}

dashboard_tmpl := compiled("templates/dashboard.runa.html", Dashboard_Ctx)
section_layout_tmpl := compiled("templates/section_layout.runa.html", Dashboard_Ctx)

inline_card_tmpl := compiled_inline(
	`<article class="card"><h2>{{ this.host | default("unknown") }}</h2><span>{{ this.latency_ms | fmt("%.2f ms") }}</span></article>`,
	Host_Row,
)

inline_macro_badge_tmpl := compiled_inline(
	`{%- macro badge(label: string, status_class := "ok") -%}<span class="badge badge--{{ status_class }}">{{ label | default("N/A") }}</span>{%- end -%}{%- call badge(this.host, "ok") -%}`,
	Host_Row,
)

inline_fmt_simple_tmpl := compiled_inline(
	`{{ this.host | fmt("<span class='host'>%s</span>") | raw }} ({{ len(this.host) | fmt("len=%i") }})`,
	Host_Row,
)

inline_embed_badge_tmpl := compiled_inline(
	`{%- embed "templates/badge_component.runa.html"(label = this.host, status_class = "ok") -%}`,
	Host_Row,
)

Default_Chain_Ctx :: struct {
	opt_tag:       Maybe(string),
	empty_region:  string,
	tags:          []string,
	fallback_tags: []string,
}

inline_default_chain_tmpl := compiled_inline(
	`{{ this.opt_tag | default("untagged & global") | url_param }}/{{ this.empty_region | default("us-east-1") }} ({{ this.tags | default(this.fallback_tags) | len }})`,
	Default_Chain_Ctx,
)

@(private = "file")
CLEAN_SHORT :: "Welcome to Runa: zero-overhead compile-time HTML templates for Odin!"
@(private = "file")
XSS_CHUNK :: `<script attr="val" & 'single'>alert("xss" & '1');</script><span>Hello &amp; World</span>`
@(private = "file")
URL_RELATIVE :: "/nodes/view?cluster=prod&id=42"
@(private = "file")
URL_HTTPS :: "https://example.com/search?q=odin&lang=en"
@(private = "file")
URL_DATA_PNG :: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA"
@(private = "file")
URL_BLOCKED_JS :: "   JaVaScRiPt:alert('xss')"
@(private = "file")
URL_PARAM_FAST :: "odin_lang-1.0.0_release.tar.gz"
@(private = "file")
URL_PARAM_QUERY :: "hello world & filter=a+b?c#d"
@(private = "file")
JS_SCRIPT_STR :: `</script><script>alert("xss" & '1')</script>` + "\n\u2028"
@(private = "file")
MAGIC_WORD_STR :: "Zero overhead compile-time <Odin & HTML> templates"

@(private = "file")
Bench_Ctx :: struct {
	render_sb:              ^strings.Builder,
	render_w:               io.Writer,
	clean_64k:              string,
	mixed_64k:              string,
	host_row:               Host_Row,
	default_chain_ctx:      Default_Chain_Ctx,
	dash_ctx:               Dashboard_Ctx,
	template_bytes:         []byte,
	layout_bytes:           []byte,
	section_bytes:          []byte,
	badge_bytes:            []byte,
	leaf_3level_bytes:      []byte,
	embed_host_bytes:       []byte,
	invalid_tmpl_bytes:     []byte,
	complex_ast_bytes:      []byte,
	trace_err_leaf_bytes:   []byte,
	odin_src:               string,
	dash_path:              string,
	layout_path:            string,
	section_path:           string,
	badge_path:             string,
	odin_path:              string,
	cached_parent_templ:    runa_cli.Template,
	cached_section_templ:   runa_cli.Template,
	cached_badge_templ:     runa_cli.Template,
	cached_resolved_dash:   runa_cli.Template,
	cached_trace_err_templ: runa_cli.Template,
	snap_prev:              runa_cli.Workspace_Snapshot,
	snap_curr:              runa_cli.Workspace_Snapshot,
}

@(private = "file")
Str_Case :: struct {
	ctx:  ^Bench_Ctx,
	text: string,
}

@(private = "file")
bench_escape_string :: proc(b: ^hugi.Bencher) {
	sc := (^Str_Case)(b.user_ptr)
	hugi.set_bytes(b, u64(len(sc.text)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(sc.ctx.render_sb)
		n, _ := runa.__runa_write_escaped_string(sc.ctx.render_w, sc.text)
		_ = hugi.black_box(n)
	}
}

@(private = "file")
bench_safe_url :: proc(b: ^hugi.Bencher) {
	sc := (^Str_Case)(b.user_ptr)
	hugi.set_bytes(b, u64(len(sc.text)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(sc.ctx.render_sb)
		n, _ := runa.__runa_write_safe_url(sc.ctx.render_w, sc.text)
		_ = hugi.black_box(n)
	}
}

@(private = "file")
bench_url_param :: proc(b: ^hugi.Bencher) {
	sc := (^Str_Case)(b.user_ptr)
	hugi.set_bytes(b, u64(len(sc.text)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(sc.ctx.render_sb)
		n, _ := runa.__runa_write_url_param(sc.ctx.render_w, sc.text)
		_ = hugi.black_box(n)
	}
}

@(private = "file")
bench_js_string :: proc(b: ^hugi.Bencher) {
	sc := (^Str_Case)(b.user_ptr)
	hugi.set_bytes(b, u64(len(sc.text)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(sc.ctx.render_sb)
		n, _ := runa.__runa_write_js_string(sc.ctx.render_w, sc.text)
		_ = hugi.black_box(n)
	}
}

@(private = "file")
bench_magic_string :: proc(b: ^hugi.Bencher) {
	sc := (^Str_Case)(b.user_ptr)
	hugi.set_bytes(b, u64(len(sc.text)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(sc.ctx.render_sb)
		n, _ := runa.__runa_write_magic_string(sc.ctx.render_w, sc.text)
		_ = hugi.black_box(n)
	}
}

@(private = "file")
bench_direct_type_casts :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		w1, _ := io.write_string(ctx.render_w, "Order: $")
		w2, _ := runa.__runa_write_f64_prec(ctx.render_w, 149.95, 2)
		w3, _ := io.write_string(ctx.render_w, " (")
		w4, _ := runa.__runa_write_int(ctx.render_w, 12)
		w5, _ := io.write_string(ctx.render_w, " items)")
		last_n = w1 + w2 + w3 + w4 + w5
		_ = hugi.black_box(last_n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_direct_large_numbers :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		w1, _ := io.write_string(ctx.render_w, "ts=")
		w2, _ := runa.__runa_write_int(ctx.render_w, 1_730_476_800)
		w3, _ := io.write_string(ctx.render_w, " delta=")
		w4, _ := runa.__runa_write_f64_prec(ctx.render_w, -98765.4321, 4)
		last_n = w1 + w2 + w3 + w4
		_ = hugi.black_box(last_n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_fmt_strength_reduced :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := inline_fmt_simple_tmpl.with(ctx.render_w, ctx.host_row)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_default_chained_pipe :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := inline_default_chain_tmpl.with(ctx.render_w, ctx.default_chain_ctx)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_fmt_streaming :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := runa.__runa_write_fmt_escaped(
			ctx.render_w,
			"%s: $%.2f (%i items)",
			"Order <A&B>",
			149.95,
			12,
		)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_fmt_raw :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := runa.__runa_write_fmt_raw(
			ctx.render_w,
			"%s: $%.2f (%i items)",
			"Order <A&B>",
			149.95,
			12,
		)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_fmt_tprintf :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		formatted := fmt.tprintf("%s: $%.2f (%i items)", "Order <A&B>", 149.95, 12)
		n, _ := runa.__runa_write_escaped_string(ctx.render_w, formatted)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_component_macro :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := inline_macro_badge_tmpl.with(ctx.render_w, ctx.host_row)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_component_embed :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := inline_embed_badge_tmpl.with(ctx.render_w, ctx.host_row)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_inline_card_preallocated :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := inline_card_tmpl.with(ctx.render_w, ctx.host_row)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_inline_card_approx_bytes :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		sb := strings.builder_make(0, inline_card_tmpl.approx_bytes + 32, context.temp_allocator)
		n, _ := inline_card_tmpl.with(strings.to_writer(&sb), ctx.host_row)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_inline_card_unbuffered :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		sb := strings.builder_make(0, 0, context.temp_allocator)
		n, _ := inline_card_tmpl.with(strings.to_writer(&sb), ctx.host_row)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_dashboard_reused_buf :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		n, _ := dashboard_tmpl.with(ctx.render_w, ctx.dash_ctx)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_dashboard_approx_bytes_alloc :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		sb := strings.builder_make(0, dashboard_tmpl.approx_bytes, context.temp_allocator)
		n, _ := dashboard_tmpl.with(strings.to_writer(&sb), ctx.dash_ctx)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_dashboard_sized_alloc :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		sb := strings.builder_make(0, 16 * 1024, context.temp_allocator)
		n, _ := dashboard_tmpl.with(strings.to_writer(&sb), ctx.dash_ctx)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_dashboard_unbuffered_grow :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	for hugi.step(b) {
		sb := strings.builder_make(0, 0, context.temp_allocator)
		n, _ := dashboard_tmpl.with(strings.to_writer(&sb), ctx.dash_ctx)
		free_all(context.temp_allocator)
		last_n = n
		_ = hugi.black_box(n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_cli_stage1_collect :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.odin_src)))
	for hugi.step(b) {
		prev_alloc := context.allocator
		context.allocator = context.temp_allocator

		NO_POS :: tokenizer.Pos{}
		pkg := ast.new(ast.Package, NO_POS, NO_POS)
		pkg.fullpath = "benchmarks"

		p := odin_parser.default_parser()
		file := ast.new(ast.File, NO_POS, NO_POS)
		file.pkg = pkg
		file.src = ctx.odin_src
		file.fullpath = ctx.odin_path
		_ = odin_parser.parse_file(&p, file)

		calls := make([dynamic]runa_cli.Compile_Call, context.temp_allocator)
		seen := make(map[string]string, context.temp_allocator)
		files := [1]^ast.File{file}
		runa_cli.collect_calls_from_parsed_files(
			"benchmarks",
			files[:],
			&calls,
			&seen,
			context.temp_allocator,
		)
		_ = hugi.black_box(len(calls))

		context.allocator = prev_alloc
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_lexer :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.template_bytes)))
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		l: runa_cli.Lexer
		runa_cli.lexer_init(&l, ctx.template_bytes)
		count := 0
		for {
			tok := runa_cli.lexer_next(&l)
			count += 1
			if tok.type == .EOF || tok.type == .Illegal {
				break
			}
		}
		_ = hugi.black_box(count)
	}
}

@(private = "file")
bench_cli_parser :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.template_bytes)))
	for hugi.step(b) {
		p: runa_cli.Parser
		runa_cli.parser_init(&p, ctx.template_bytes, context.temp_allocator)
		t := runa_cli.parse(&p)
		_ = hugi.black_box(len(t.content))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_parse_complex_ast :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.complex_ast_bytes)))
	for hugi.step(b) {
		p: runa_cli.Parser
		runa_cli.parser_init(&p, ctx.complex_ast_bytes, context.temp_allocator)
		t := runa_cli.parse(&p)
		_ = hugi.black_box(len(t.content))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_inheritance_resolve :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.template_bytes) + len(ctx.layout_bytes)))
	for hugi.step(b) {
		p_child: runa_cli.Parser
		runa_cli.parser_init(&p_child, ctx.template_bytes, context.temp_allocator)
		child_t := runa_cli.parse(&p_child)

		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.layout_path,
			runa_cli.Cached_Template{source = ctx.layout_bytes, template = ctx.cached_parent_templ},
		)

		resolved, _ := runa_cli.resolve_template_inheritance(
			&cctx,
			child_t,
			ctx.template_bytes,
			ctx.dash_path,
		)
		_ = hugi.black_box(len(resolved.content))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_3level_inheritance :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.leaf_3level_bytes) + len(ctx.section_bytes) + len(ctx.layout_bytes)))
	for hugi.step(b) {
		p_leaf: runa_cli.Parser
		runa_cli.parser_init(&p_leaf, ctx.leaf_3level_bytes, context.temp_allocator)
		leaf_t := runa_cli.parse(&p_leaf)

		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.layout_path,
			runa_cli.Cached_Template{source = ctx.layout_bytes, template = ctx.cached_parent_templ},
		)
		runa_cli.cache_raw_template(
			&cctx,
			ctx.section_path,
			runa_cli.Cached_Template{source = ctx.section_bytes, template = ctx.cached_section_templ},
		)

		resolved, _ := runa_cli.resolve_template_inheritance(
			&cctx,
			leaf_t,
			ctx.leaf_3level_bytes,
			ctx.dash_path,
		)
		_ = hugi.black_box(len(resolved.content))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_embed_props_transpile :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.embed_host_bytes) + len(ctx.badge_bytes)))
	for hugi.step(b) {
		p_host: runa_cli.Parser
		runa_cli.parser_init(&p_host, ctx.embed_host_bytes, context.temp_allocator)
		host_t := runa_cli.parse(&p_host)

		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.badge_path,
			runa_cli.Cached_Template{source = ctx.badge_bytes, template = ctx.cached_badge_templ},
		)

		embed_state := runa_cli.Embed_Callback_State{
			ctx          = &cctx,
			current_file = ctx.dash_path,
			current_src  = ctx.embed_host_bytes,
		}

		strings.builder_reset(ctx.render_sb)
		runa_cli.transpile(
			ctx.render_w,
			"embed_host.runa.html",
			host_t,
			runa_cli.embed_parser_with_ctx,
			&embed_state,
			context.temp_allocator,
			true,
		)
		_ = hugi.black_box(strings.builder_len(ctx.render_sb^))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_diagnostic_error_path :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.invalid_tmpl_bytes)))
	for hugi.step(b) {
		p: runa_cli.Parser
		runa_cli.parser_init(&p, ctx.invalid_tmpl_bytes, context.temp_allocator)
		t := runa_cli.parse(&p)
		err_len := 0
		if err, has_err := t.err.?; has_err {
			err_len = len(err.msg)
		}
		_ = hugi.black_box(err_len)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_multiframe_diagnostic :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(
		b,
		u64(len(ctx.trace_err_leaf_bytes) + len(ctx.section_bytes) + len(ctx.layout_bytes)),
	)
	for hugi.step(b) {
		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		cctx.diagnostics.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.layout_path,
			runa_cli.Cached_Template{source = ctx.layout_bytes, template = ctx.cached_parent_templ},
		)
		runa_cli.cache_raw_template(
			&cctx,
			ctx.section_path,
			runa_cli.Cached_Template{source = ctx.section_bytes, template = ctx.cached_section_templ},
		)
		runa_cli.cache_raw_template(
			&cctx,
			ctx.dash_path,
			runa_cli.Cached_Template{source = ctx.trace_err_leaf_bytes, template = ctx.cached_trace_err_templ},
		)

		call := runa_cli.Compile_Call{
			identifier = "templates/trace_err.runa.html",
			type = runa_cli.Call_Path{
				relpath  = "templates/trace_err.runa.html",
				fullpath = ctx.dash_path,
			},
			pos = tokenizer.Pos{
				file   = ctx.odin_path,
				line   = 112,
				column = 21,
			},
		}

		_, _ = runa_cli.compile_single_call(&cctx, call)
		trace_len := len(cctx.diagnostics[0].trace) if len(cctx.diagnostics) > 0 else 0
		_ = hugi.black_box(trace_len)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_pure_transpile_loc_on :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		runa_cli.transpile(
			ctx.render_w,
			"dashboard.runa.html",
			ctx.cached_resolved_dash,
			nil,
			nil,
			context.temp_allocator,
			true,
			true,
		)
		last_n = strings.builder_len(ctx.render_sb^)
		_ = hugi.black_box(last_n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_cli_pure_transpile_loc_off :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	last_n := 0
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		strings.builder_reset(ctx.render_sb)
		runa_cli.transpile(
			ctx.render_w,
			"dashboard.runa.html",
			ctx.cached_resolved_dash,
			nil,
			nil,
			context.temp_allocator,
			true,
			false,
		)
		last_n = strings.builder_len(ctx.render_sb^)
		_ = hugi.black_box(last_n)
	}
	hugi.set_bytes(b, u64(last_n))
}

@(private = "file")
bench_cli_transpile :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(b, u64(len(ctx.template_bytes) + len(ctx.layout_bytes)))
	for hugi.step(b) {
		p_child: runa_cli.Parser
		runa_cli.parser_init(&p_child, ctx.template_bytes, context.temp_allocator)
		child_t := runa_cli.parse(&p_child)

		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.layout_path,
			runa_cli.Cached_Template{source = ctx.layout_bytes, template = ctx.cached_parent_templ},
		)

		resolved, _ := runa_cli.resolve_template_inheritance(
			&cctx,
			child_t,
			ctx.template_bytes,
			ctx.dash_path,
		)
		strings.builder_reset(ctx.render_sb)
		runa_cli.transpile(
			ctx.render_w,
			"dashboard.runa.html",
			resolved,
			nil,
			nil,
			context.temp_allocator,
			true,
		)
		_ = hugi.black_box(strings.builder_len(ctx.render_sb^))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_batch_compile_3 :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_bytes(
		b,
		u64(
			len(ctx.template_bytes) +
			len(ctx.section_bytes) +
			len(ctx.leaf_3level_bytes) +
			len(ctx.layout_bytes),
		),
	)
	for hugi.step(b) {
		cctx: runa_cli.Compile_Context
		cctx.allocator = context.temp_allocator
		runa_cli.cache_raw_template(
			&cctx,
			ctx.layout_path,
			runa_cli.Cached_Template{source = ctx.layout_bytes, template = ctx.cached_parent_templ},
		)
		runa_cli.cache_raw_template(
			&cctx,
			ctx.section_path,
			runa_cli.Cached_Template{source = ctx.section_bytes, template = ctx.cached_section_templ},
		)

		strings.builder_reset(ctx.render_sb)

		p1: runa_cli.Parser
		runa_cli.parser_init(&p1, ctx.template_bytes, context.temp_allocator)
		t1 := runa_cli.parse(&p1)
		r1, _ := runa_cli.resolve_template_inheritance(&cctx, t1, ctx.template_bytes, ctx.dash_path)
		runa_cli.transpile(
			ctx.render_w,
			"templates/dashboard.runa.html",
			r1,
			nil,
			nil,
			context.temp_allocator,
			true,
		)

		r2, _ := runa_cli.resolve_template_inheritance(
			&cctx,
			ctx.cached_section_templ,
			ctx.section_bytes,
			ctx.section_path,
		)
		runa_cli.transpile(
			ctx.render_w,
			"templates/section_layout.runa.html",
			r2,
			nil,
			nil,
			context.temp_allocator,
			true,
		)

		p3: runa_cli.Parser
		runa_cli.parser_init(&p3, ctx.leaf_3level_bytes, context.temp_allocator)
		t3 := runa_cli.parse(&p3)
		r3, _ := runa_cli.resolve_template_inheritance(
			&cctx,
			t3,
			ctx.leaf_3level_bytes,
			ctx.dash_path,
		)
		runa_cli.transpile(
			ctx.render_w,
			"templates/leaf.runa.html",
			r3,
			nil,
			nil,
			context.temp_allocator,
			true,
		)

		_ = hugi.black_box(strings.builder_len(ctx.render_sb^))
		free_all(context.temp_allocator)
	}
}

@(private = "file")
bench_cli_watch_snapshot_diff :: proc(b: ^hugi.Bencher) {
	ctx := (^Bench_Ctx)(b.user_ptr)
	hugi.set_items(b, 32)
	hugi.expect_zero_allocs(b)
	for hugi.step(b) {
		changed := runa_cli.has_workspace_snapshot_changed(ctx.snap_prev, ctx.snap_curr)
		is_gen := runa_cli.is_generated_runa_source(
			"/* This file was generated by runa on 2026 - DO NOT EDIT! */\npackage benchmarks\n",
		)
		_ = hugi.black_box((1 if !changed else 0) + (1 if is_gen else 0))
	}
}

main :: proc() {
	setup_arena: runtime.Arena
	_ = runtime.arena_init(&setup_arena, 0, context.allocator)
	defer runtime.arena_destroy(&setup_arena)
	setup_alloc := runtime.arena_allocator(&setup_arena)

	render_sb := strings.builder_make(0, 131072)
	defer strings.builder_destroy(&render_sb)
	render_w := strings.to_writer(&render_sb)

	clean_chunk := "The quick brown fox jumps over the lazy dog 0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ! "
	clean_64k_sb := strings.builder_make(0, 65536)
	defer strings.builder_destroy(&clean_64k_sb)
	for strings.builder_len(clean_64k_sb) < 65536 {
		strings.write_string(&clean_64k_sb, clean_chunk)
	}
	clean_64k := strings.to_string(clean_64k_sb)[:65536]

	mixed_64k_sb := strings.builder_make(0, 65536)
	defer strings.builder_destroy(&mixed_64k_sb)
	for strings.builder_len(mixed_64k_sb) < 65536 {
		strings.write_string(&mixed_64k_sb, clean_chunk)
		strings.write_string(&mixed_64k_sb, XSS_CHUNK)
	}
	mixed_64k := strings.to_string(mixed_64k_sb)[:65536]

	rows := make([]Host_Row, 50)
	defer delete(rows)
	for i in 0 ..< 50 {
		rows[i] = Host_Row{
			host       = "edge-node-01.prod.internal",
			region     = "us-east-1" if i % 2 == 0 else "",
			endpoint   = "https://metrics.example.com/nodes/view",
			latency_ms = 12.34 + f64(i) * 0.75,
			state      = Host_State(i % 3),
		}
	}

	fallback_tags := [2]string{"core", "edge"}
	ctx := Bench_Ctx{
		render_sb = &render_sb,
		render_w  = render_w,
		clean_64k = clean_64k,
		mixed_64k = mixed_64k,
		host_row  = rows[0],
		default_chain_ctx = Default_Chain_Ctx{
			opt_tag       = nil,
			empty_region  = "",
			tags          = nil,
			fallback_tags = fallback_tags[:],
		},
		dash_ctx = Dashboard_Ctx{
			page_title = "Production Fleet <Cluster A & B>",
			boot_token = `tok_99a\b"c'</script>`,
			docs_url   = "https://docs.example.com/fleet?tab=nodes&sort=asc",
			env        = "prod us-east & eu-west=1",
			rows       = rows,
		},
	}

	dash_path := "benchmarks/templates/dashboard.runa.html"
	layout_path := "benchmarks/templates/layout.runa.html"
	section_path := "benchmarks/templates/section_layout.runa.html"
	badge_path := "benchmarks/templates/badge_component.runa.html"
	odin_path := "benchmarks/main.odin"
	if !os.exists(dash_path) {
		dash_path = "templates/dashboard.runa.html"
		layout_path = "templates/layout.runa.html"
		section_path = "templates/section_layout.runa.html"
		badge_path = "templates/badge_component.runa.html"
		odin_path = "main.odin"
	}

	dash_bytes, rerr := os.read_entire_file(dash_path, setup_alloc)
	layout_bytes, lerr := os.read_entire_file(layout_path, setup_alloc)
	section_bytes, serr := os.read_entire_file(section_path, setup_alloc)
	badge_bytes, berr := os.read_entire_file(badge_path, setup_alloc)
	odin_bytes, oerr := os.read_entire_file(odin_path, setup_alloc)
	has_cli_fixtures := rerr == nil && lerr == nil && serr == nil && berr == nil && oerr == nil

	if has_cli_fixtures {
		ctx.template_bytes = dash_bytes
		ctx.layout_bytes = layout_bytes
		ctx.section_bytes = section_bytes
		ctx.badge_bytes = badge_bytes
		ctx.odin_src = string(odin_bytes)
		ctx.dash_path = dash_path
		ctx.layout_path = layout_path
		ctx.section_path = section_path
		ctx.badge_path = badge_path
		ctx.odin_path = odin_path

		leaf_3level_src := `{% extends "section_layout.runa.html" %}{% block title %}{{ super() }} :: Node Detail{% end %}{% block content %}{{ super() }}<article>{{ this.page_title }}</article>{% end %}`
		embed_host_src := `<div>{% embed "badge_component.runa.html"(label = this.host, status_class = "ok") %}</div>`
		invalid_tmpl_src := `<section><h1>{{ this.page_title }}</h1>{% call unknown_macro(this.host, "ok") %}</section>`
		complex_ast_src := `<div class="{{ "active" if this.online else "offline" }}">{{ this.tags[0:2] | default("n/a") }}{% if this.online && (this.latency_ms < 50.0 || this.reqs_per_s > 1000) %}<span>{{ fmt("%s: %.2fms (%i rps)", this.host, this.latency_ms, this.reqs_per_s) }}</span>{% end %}{% let computed = (this.reqs_per_s * 2) + 1 %}</div>`
		trace_err_leaf_src := "{% extends \"section_layout.runa.html\" %}\n{% block content %}\n\t<div>{% embed \"missing_widget.runa.html\" %}</div>\n{% end %}\n"

		ctx.leaf_3level_bytes = transmute([]byte)leaf_3level_src
		ctx.embed_host_bytes = transmute([]byte)embed_host_src
		ctx.invalid_tmpl_bytes = transmute([]byte)invalid_tmpl_src
		ctx.complex_ast_bytes = transmute([]byte)complex_ast_src
		ctx.trace_err_leaf_bytes = transmute([]byte)trace_err_leaf_src

		p_parent: runa_cli.Parser
		runa_cli.parser_init(&p_parent, layout_bytes, setup_alloc)
		ctx.cached_parent_templ = runa_cli.parse(&p_parent)

		p_section: runa_cli.Parser
		runa_cli.parser_init(&p_section, section_bytes, setup_alloc)
		ctx.cached_section_templ = runa_cli.parse(&p_section)

		p_badge: runa_cli.Parser
		runa_cli.parser_init(&p_badge, badge_bytes, setup_alloc)
		ctx.cached_badge_templ = runa_cli.parse(&p_badge)

		p_err: runa_cli.Parser
		runa_cli.parser_init(&p_err, ctx.trace_err_leaf_bytes, setup_alloc)
		ctx.cached_trace_err_templ = runa_cli.parse(&p_err)

		ctx.snap_prev = make(runa_cli.Workspace_Snapshot, 32, setup_alloc)
		ctx.snap_curr = make(runa_cli.Workspace_Snapshot, 32, setup_alloc)
		for i in 0 ..< 32 {
			k := fmt.aprintf(
				"/workspace/views/component_%02d.runa.html",
				i,
				allocator = setup_alloc,
			)
			stamp := runa_cli.File_Stamp{
				mtime_nsec = 1_730_000_000_000 + i64(i) * 1000,
				size       = 1024 + i64(i) * 64,
			}
			ctx.snap_prev[k] = stamp
			ctx.snap_curr[k] = stamp
		}

		p_dash: runa_cli.Parser
		runa_cli.parser_init(&p_dash, dash_bytes, setup_alloc)
		dash_t := runa_cli.parse(&p_dash)
		init_ctx: runa_cli.Compile_Context
		init_ctx.allocator = setup_alloc
		runa_cli.cache_raw_template(
			&init_ctx,
			layout_path,
			runa_cli.Cached_Template{source = layout_bytes, template = ctx.cached_parent_templ},
		)
		ctx.cached_resolved_dash, _ = runa_cli.resolve_template_inheritance(
			&init_ctx,
			dash_t,
			dash_bytes,
			dash_path,
		)
	}

	suite := hugi.suite_create("runa")
	defer hugi.suite_destroy(&suite)

	case_esc_short := Str_Case{ctx = &ctx, text = CLEAN_SHORT}
	case_esc_xss := Str_Case{ctx = &ctx, text = XSS_CHUNK}
	case_esc_64k := Str_Case{ctx = &ctx, text = clean_64k}
	case_esc_mixed := Str_Case{ctx = &ctx, text = mixed_64k}

	g_esc := hugi.group_add(&suite, "html_escape")
	hugi.group_bench(g_esc, "clean_ascii_70b", bench_escape_string, zero_alloc = true, user_ptr = &case_esc_short)
	hugi.group_bench(g_esc, "dense_xss_88b", bench_escape_string, zero_alloc = true, user_ptr = &case_esc_xss)
	hugi.group_bench(g_esc, "clean_64kb", bench_escape_string, zero_alloc = true, user_ptr = &case_esc_64k)
	hugi.group_bench(g_esc, "mixed_xss_64kb", bench_escape_string, zero_alloc = true, user_ptr = &case_esc_mixed)

	case_url_rel := Str_Case{ctx = &ctx, text = URL_RELATIVE}
	case_url_https := Str_Case{ctx = &ctx, text = URL_HTTPS}
	case_url_data := Str_Case{ctx = &ctx, text = URL_DATA_PNG}
	case_url_js := Str_Case{ctx = &ctx, text = URL_BLOCKED_JS}
	case_param_fast := Str_Case{ctx = &ctx, text = URL_PARAM_FAST}
	case_param_query := Str_Case{ctx = &ctx, text = URL_PARAM_QUERY}
	case_js_str := Str_Case{ctx = &ctx, text = JS_SCRIPT_STR}
	case_magic_str := Str_Case{ctx = &ctx, text = MAGIC_WORD_STR}

	g_url := hugi.group_add(&suite, "url_and_js")
	hugi.group_bench(g_url, "safe_url_relative", bench_safe_url, zero_alloc = true, user_ptr = &case_url_rel)
	hugi.group_bench(g_url, "safe_url_https", bench_safe_url, zero_alloc = true, user_ptr = &case_url_https)
	hugi.group_bench(g_url, "safe_url_data_png", bench_safe_url, zero_alloc = true, user_ptr = &case_url_data)
	hugi.group_bench(g_url, "safe_url_blocked_js", bench_safe_url, zero_alloc = true, user_ptr = &case_url_js)
	hugi.group_bench(g_url, "url_param_fast_path", bench_url_param, zero_alloc = true, user_ptr = &case_param_fast)
	hugi.group_bench(g_url, "url_param_encoded_query", bench_url_param, zero_alloc = true, user_ptr = &case_param_query)
	hugi.group_bench(g_url, "js_string_escape", bench_js_string, zero_alloc = true, user_ptr = &case_js_str)
	hugi.group_bench(g_url, "magic_string_8word", bench_magic_string, zero_alloc = true, user_ptr = &case_magic_str)

	g_fmt := hugi.group_add(&suite, "formatting")
	hugi.group_bench(g_fmt, "write_int_and_f64", bench_direct_type_casts, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "write_large_numbers", bench_direct_large_numbers, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "fmt_strength_reduced", bench_fmt_strength_reduced, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "default_chained_pipe", bench_default_chained_pipe, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "fmt_escaped_streaming", bench_fmt_streaming, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "fmt_raw", bench_fmt_raw, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_fmt, "fmt_tprintf_escaped", bench_fmt_tprintf, zero_alloc = false, user_ptr = &ctx)

	g_comp := hugi.group_add(&suite, "components")
	hugi.group_bench(g_comp, "macro_badge", bench_component_macro, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_comp, "embed_badge", bench_component_embed, zero_alloc = true, user_ptr = &ctx)

	g_render := hugi.group_add(&suite, "rendering")
	hugi.group_bench(g_render, "card_reused_buf", bench_inline_card_preallocated, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_render, "card_approx_bytes", bench_inline_card_approx_bytes, user_ptr = &ctx)
	hugi.group_bench(g_render, "card_unbuffered", bench_inline_card_unbuffered, user_ptr = &ctx)
	hugi.group_bench(g_render, "dashboard_50_reused_buf", bench_dashboard_reused_buf, zero_alloc = true, user_ptr = &ctx)
	hugi.group_bench(g_render, "dashboard_50_approx_bytes", bench_dashboard_approx_bytes_alloc, user_ptr = &ctx)
	hugi.group_bench(g_render, "dashboard_50_sized_16kb", bench_dashboard_sized_alloc, user_ptr = &ctx)
	hugi.group_bench(g_render, "dashboard_50_unbuffered", bench_dashboard_unbuffered_grow, user_ptr = &ctx)

	if has_cli_fixtures {
		g_cli := hugi.group_add(&suite, "compiler_cli")
		hugi.group_bench(g_cli, "stage1_ast_collect", bench_cli_stage1_collect, user_ptr = &ctx)
		hugi.group_bench(g_cli, "lexer_tokenize", bench_cli_lexer, zero_alloc = true, user_ptr = &ctx)
		hugi.group_bench(g_cli, "parse_expr_check", bench_cli_parser, user_ptr = &ctx)
		hugi.group_bench(g_cli, "parse_complex_ast", bench_cli_parse_complex_ast, user_ptr = &ctx)
		hugi.group_bench(g_cli, "inheritance_resolve_2level", bench_cli_inheritance_resolve, user_ptr = &ctx)
		hugi.group_bench(g_cli, "inheritance_resolve_3level", bench_cli_3level_inheritance, user_ptr = &ctx)
		hugi.group_bench(g_cli, "embed_props_transpile", bench_cli_embed_props_transpile, user_ptr = &ctx)
		hugi.group_bench(g_cli, "diagnostic_undefined_macro", bench_cli_diagnostic_error_path, user_ptr = &ctx)
		hugi.group_bench(g_cli, "diagnostic_multiframe_trace", bench_cli_multiframe_diagnostic, user_ptr = &ctx)
		hugi.group_bench(g_cli, "pure_transpile_loc_on", bench_cli_pure_transpile_loc_on, zero_alloc = true, user_ptr = &ctx)
		hugi.group_bench(g_cli, "pure_transpile_loc_off", bench_cli_pure_transpile_loc_off, zero_alloc = true, user_ptr = &ctx)
		hugi.group_bench(g_cli, "full_parse_inherit_transpile", bench_cli_transpile, user_ptr = &ctx)
		hugi.group_bench(g_cli, "batch_compile_3_warm_cache", bench_cli_batch_compile_3, user_ptr = &ctx)
		hugi.group_bench(g_cli, "watch_snapshot_diff_32", bench_cli_watch_snapshot_diff, zero_alloc = true, user_ptr = &ctx)
	}

	if !hugi.suite_run(&suite) {
		fmt.eprintln("runa benchmark suite failed")
		os.exit(1)
	}
}
