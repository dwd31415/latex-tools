module LaTeXTools

export process_document, remove_comments, inline_inputs, clean_bibliography

const INPUT_COMMAND = r"\\(input|include)\s*\{([^}]+)\}"
const FIGURE_COMMAND = r"(\\includegraphics\*?(?:\s*\[[^\]]*\])?\s*\{)([^}]+)(\})"
const BIB_RESOURCE = r"\\addbibresource\s*\{([^}]+)\}"
const BIB_COMMAND = r"\\bibliography\s*\{([^}]+)\}"
const CITATION_COMMAND = r"\\(?:cite|citeauthor|citeyear|parencite|textcite|autocite)(?:\w*)\*?\s*(?:\[[^\]]*\]\s*)*\{([^}]+)\}"
const NOCITE_COMMAND = r"\\nocite\s*\{([^}]+)\}"

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

"""Inline recursive \\input and \\include files relative to the including file."""
function inline_inputs(text::AbstractString, source_path::AbstractString)
    return _inline(text, abspath(source_path), String[])
end

function _inline(text, source_path, stack; figures=nothing, figure_names=nothing)
    source_dir = dirname(source_path)
    processed = isnothing(figures) ? text : replace(text, FIGURE_COMMAND => m -> begin
        match_data = match(FIGURE_COMMAND, m)
        requested = match_data.captures[2]
        figure = _resolve_figure(requested, source_dir)
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
        _inline(child, included, [stack; included]; figures, figure_names)
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
    expanded = remove_comments(_inline(source, input_path, String[]; figures, figure_names))
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

end
