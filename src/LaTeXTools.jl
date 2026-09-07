module LaTeXTools

export process_document, remove_comments, inline_inputs, clean_bibliography,
       collect_dependencies, autobuild

const INPUT_COMMAND = r"\\(input|include)\s*\{([^}]+)\}"
const FIGURE_COMMAND = r"(\\includegraphics\*?(?:\s*\[[^\]]*\])?\s*\{)([^}]+)(\})"
const BIB_RESOURCE = r"\\addbibresource\s*\{([^}]+)\}"
const BIB_COMMAND = r"\\bibliography\s*\{([^}]+)\}"
const CITATION_COMMAND = r"\\(?:cite|citeauthor|citeyear|parencite|textcite|autocite)(?:\w*)\*?\s*(?:\[[^\]]*\]\s*)*\{([^}]+)\}"
const NOCITE_COMMAND = r"\\nocite\s*\{([^}]+)\}"
const ANSI_RED = "\e[31m"
const ANSI_YELLOW = "\e[33m"
const ANSI_GREEN = "\e[32m"
const ANSI_RESET = "\e[0m"
const ANSI_CLEAR = "\e[2J\e[H"

"""Remove LaTeX comments while preserving escaped percent signs."""
function remove_comments(text::AbstractString)
    return join(map(split(text, '\n'; keepempty=true)) do line
        escaped = false
        cut = nothing
        for (index, character) in pairs(line)
            if character == '%' && !escaped
                cut = first(index)
                break
            end
            escaped = character == '\\' && !escaped
            if character != '\\'
                escaped = false
            end
        end
        isnothing(cut) ? line : line[begin:prevind(line, cut)] * "% "
    end, '\n')
end

function _resolve_tex(path, base)
    candidate = isabspath(path) ? path : joinpath(base, path)
    isfile(candidate) && return candidate
    endswith(candidate, ".tex") || (candidate *= ".tex")
    return candidate
end

function _resolve_figure(path, base)
    candidate = isabspath(path) ? path : joinpath(base, path)
    isfile(candidate) && return candidate
    for extension in (".pdf", ".png", ".jpg", ".jpeg", ".eps")
        isfile(candidate * extension) && return candidate * extension
    end
    return candidate
end

function _resolve_bib(path, base)
    candidate = isabspath(path) ? path : joinpath(base, path)
    isfile(candidate) && return candidate
    endswith(candidate, ".bib") || (candidate *= ".bib")
    return candidate
end

function _collect_dependencies(text, source_path, dependencies, visited)
    source_path in visited && return
    push!(visited, source_path)
    push!(dependencies, source_path)
    source_dir = dirname(source_path)
    for match in eachmatch(INPUT_COMMAND, text)
        included = _resolve_tex(match.captures[2], source_dir)
        isfile(included) || error("Included TeX file not found: $(match.captures[2]) (from $(source_path))")
        _collect_dependencies(read(included, String), included, dependencies, visited)
    end
    for pattern in (BIB_RESOURCE, BIB_COMMAND)
        for match in eachmatch(pattern, text)
            for requested in split(match.captures[1], ',')
                bib = _resolve_bib(strip(requested), source_dir)
                isfile(bib) || error("Bibliography file not found: $(strip(requested)) (from $(source_path))")
                push!(dependencies, bib)
            end
        end
    end
end

"""Collect a main document and all recursively included TeX and bibliography files."""
function collect_dependencies(input::AbstractString)
    dependencies = Set{String}()
    _collect_dependencies(read(abspath(input), String), abspath(input), dependencies, Set{String}())
    return dependencies
end

"""Inline recursive \\input and \\include files relative to the including file."""
function inline_inputs(text::AbstractString, source_path::AbstractString)
    return _inline(text, abspath(source_path), String[])
end

function _inline(text, source_path, stack; figures=nothing, figure_names=nothing,
                 figure_base=dirname(source_path))
    source_dir = dirname(source_path)
    processed = isnothing(figures) ? text : replace(text, FIGURE_COMMAND => m -> begin
        match_data = match(FIGURE_COMMAND, m)
        requested = match_data.captures[2]
        figure = _resolve_figure(requested, figure_base)
        isfile(figure) || error("Included figure not found: $(requested) (from $(source_path))")
        name = get!(figures, figure) do
            figure_name = basename(figure)
            if haskey(figure_names, figure_name) && figure_names[figure_name] != figure
                error("Included figures have the same filename: $(figure_name)")
            end
            figure_names[figure_name] = figure
            figure_name
        end
        match_data.captures[1] * name * match_data.captures[3]
    end)
    return replace(processed, INPUT_COMMAND => m -> begin
        requested = match(INPUT_COMMAND, m).captures[2]
        included = _resolve_tex(requested, source_dir)
        isfile(included) || error("Included TeX file not found: $(requested) (from $(source_path))")
        included in stack && error("Cyclic TeX include detected: $(join([stack; included], " -> "))")
        child = remove_comments(read(included, String))
        _inline(child, included, [stack; included]; figures, figure_names, figure_base)
    end)
end

function _citations(text)
    keys = Set{String}()
    for match in eachmatch(CITATION_COMMAND, text)
        union!(keys, strip.(split(match.captures[1], ',')))
    end
    any("*" ∈ strip.(split(match.captures[1], ',')) for match in eachmatch(NOCITE_COMMAND, text)) &&
        return nothing
    for match in eachmatch(NOCITE_COMMAND, text)
        union!(keys, strip.(split(match.captures[1], ',')))
    end
    return keys
end

"""Keep only BibTeX entries cited by the LaTeX source."""
function clean_bibliography(bib_text::AbstractString, cited_keys)
    lines = split(bib_text, '\n'; keepempty=true)
    output = String[]
    index = 1
    while index <= length(lines)
        line = lines[index]
        entry = match(r"^\s*@\w+\s*\{\s*([^,\s]+)\s*,", line)
        if isnothing(entry)
            push!(output, line)
            index += 1
            continue
        end
        start = index
        depth = count(==('{'), line) - count(==('}'), line)
        index += 1
        while index <= length(lines) && depth > 0
            depth += count(==('{'), lines[index]) - count(==('}'), lines[index])
            index += 1
        end
        entry_key = entry.captures[1]
        cited_keys === nothing || entry_key in cited_keys ? append!(output, lines[start:index-1]) : nothing
    end
    return join(output, '\n')
end

"""Process a main document and optionally write cleaned bibliography and figure files."""
function process_document(input::AbstractString; output::AbstractString,
                          bibliography=nothing, bibliography_output=nothing,
                          output_folder=nothing)
    input_path = abspath(input)
    folder = isnothing(output_folder) ? nothing : abspath(output_folder)
    isnothing(folder) || mkpath(folder)
    tex_output = isnothing(folder) ? output : joinpath(folder, basename(output))
    source = remove_comments(read(input_path, String))
    figures = isnothing(folder) ? nothing : Dict{String,String}()
    figure_names = isnothing(folder) ? nothing : Dict{String,String}()
    expanded = remove_comments(_inline(source, input_path, String[]; figures, figure_names,
                                        figure_base=dirname(input_path)))
    write(tex_output, expanded)
    for (figure, name) in something(figures, Dict{String,String}())
        destination = joinpath(folder, name)
        figure == destination || cp(figure, destination; force=true)
    end

    if !isnothing(bibliography)
        bib_path = abspath(bibliography)
        bib_out = isnothing(bibliography_output) ? bib_path * ".cleaned.bib" : bibliography_output
        isnothing(folder) || (bib_out = joinpath(folder, basename(bib_out)))
        write(bib_out, clean_bibliography(read(bib_path, String), _citations(expanded)))
        return (tex=tex_output, bib=bib_out)
    end
    return (tex=tex_output, bib=nothing)
end

function _print_build_output(output; source_name=nothing)
    lines = split(output, '\n'; keepempty=true)
    context_lines = 0
    for line in lines
        isempty(strip(line)) && continue
        occursin(r"(?i)transcript written on", line) && continue
        is_error = occursin(r"(?i)(^|\s)!|error|fatal|couldn't|cannot|not found", line)
        is_warning = occursin(r"(?i)warning", line)
        location = match(r"^\s*l\.(\d+)\s*(.*)$", line)
        is_location = !isnothing(location) || occursin(r"(?::|^)\S+:\d+:", strip(line))
        if is_error || is_warning || is_location || context_lines > 0
            color = is_error || is_location ? ANSI_RED : ANSI_YELLOW
            println(color, line, ANSI_RESET)
        end
        context_lines = is_location ? 1 : max(context_lines - 1, 0)
    end
end

function _run_build_command(command, label; source_name=nothing)
    print(ANSI_CLEAR)
    flush(stdout)
    println(ANSI_GREEN, label, ANSI_RESET)
    output = IOBuffer()
    success = true
    try
        run(pipeline(command, stdout=output, stderr=output))
    catch error
        error isa ProcessFailedException || rethrow()
        success = false
    end
    text = String(take!(output))
    _print_build_output(text; source_name)
    success && println(ANSI_GREEN, "$(label) completed", ANSI_RESET)
    return success
end

function _build(input_path, build_directory, bibliography)
    pdflatex = Cmd(["pdflatex", "-interaction=nonstopmode", "-halt-on-error",
                    "-file-line-error", "-output-directory=$(build_directory)",
                    basename(input_path)])
    pdflatex = setenv(pdflatex, dir=dirname(input_path))
    _run_build_command(pdflatex, "Building $(basename(input_path))";
                       source_name=basename(input_path)) || return false
    if bibliography
        document_name, _ = splitext(basename(input_path))
        bibtex = Cmd(["bibtex", document_name])
        _run_build_command(setenv(bibtex, dir=build_directory), "Running bibtex";
                           source_name=basename(input_path)) || return false
        _run_build_command(pdflatex, "Rebuilding $(basename(input_path))";
                           source_name=basename(input_path)) || return false
    end
    return true
end

"""Build a document and rebuild it whenever its TeX or bibliography dependencies change."""
function autobuild(input::AbstractString, build_directory::AbstractString; interval=1.0)
    input_path = abspath(input)
    build_directory = abspath(build_directory)
    mkpath(build_directory)
    dependencies = collect_dependencies(input_path)
    bibliography = any(endswith(path, ".bib") for path in dependencies)
    _build(input_path, build_directory, bibliography) ||
        error("Initial LaTeX build failed")
    snapshots = Dict(path => stat(path).mtime for path in dependencies)
    println(ANSI_GREEN, "Watching $(length(dependencies)) file(s) for changes", ANSI_RESET)
    while true
        sleep(interval)
        current_dependencies = collect_dependencies(input_path)
        changed = current_dependencies != Set(keys(snapshots)) ||
                  any(!isfile(path) || stat(path).mtime != get(snapshots, path, nothing)
                      for path in current_dependencies)
        if changed
            dependencies = current_dependencies
            bibliography = any(endswith(path, ".bib") for path in dependencies)
            _build(input_path, build_directory, bibliography) ||
                println(ANSI_RED, "LaTeX build failed; continuing to watch", ANSI_RESET)
            snapshots = Dict(path => stat(path).mtime for path in dependencies)
        end
    end
end

end
