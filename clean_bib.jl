println("Please enter .aux file:")
file_name = readline()
f = open(file_name, "r")
aux_file = readlines(f)

function get_citation(line)
    regex = r"\\citation\{([^}]+)\}"
    matches = match(regex, line)
    if !isnothing(matches)
        return matches[1]
    end
    return nothing
end

used_citations = filter(x -> !isnothing(x), get_citation.(aux_file))

println("Please enter .bib file:")
file_name = readline()
f = open(file_name, "r")
bib_file = readlines(f)

new_bib = [""]
current_citation = []
add_current = false

for line ∈ bib_file
    if startswith(line, "@")
        matches = match(r"@(\w+)\{([^,]+),", line)
        if !isnothing(matches)
            if add_current
                append!(new_bib, current_citation)
            end
            global current_citation = []
            global add_current = (matches[2] ∈ used_citations)
        else
            println("Suspicious line: $(line)")
        end
    end
    push!(current_citation, line)
end

if add_current
    append!(new_bib, current_citation)
end

println("Name for new bib:")

file_name = readline()
f = open(file_name, "w")

for line ∈ new_bib
    println(f, line)
end

close(f)
