# Getting cases out: `github_matrix` (plan Phase 6 step 4; contract §13.1,
# §14.1). Rows are already Tables.jl rows; this is the one exporter the
# package keeps, and it writes JSON through JSON.jl rather than by hand.
#
# Every row is read and checked before anything reaches `io`, so a rejected
# value never leaves half a document behind.

import JSON

"GitHub Actions runs at most this many jobs from one matrix."
const _GITHUB_MATRIX_LIMIT = 256

"""
    github_matrix(cases; io = stdout)
    github_matrix(io::IO, cases)

Use when a GitHub Actions workflow should run one job per test case: write
the cases as the JSON document `{"include": [...]}`, one object per case,
for a workflow to read with `fromJSON`.

`cases` is a [`TestCases`](@ref) or a vector of rows. Each object's keys are
the parameter names; a positional result's parameters are `p1`, `p2`, …, and
so are a `Tuple` row's. A `NamedTuple` row supplies its own names. The
document is one line with no trailing newline; `sprint(github_matrix, cases)`
returns it as a `String`. The function returns `nothing`.

Values are written as JSON can hold them:

| Value | JSON |
|:--|:--|
| `String` (any valid UTF-8 `AbstractString`) | string |
| `Symbol` | string, its name: `:qr` becomes `"qr"` |
| `Bool` | `true` or `false` |
| finite `Integer` or `AbstractFloat` | number: `1.0e-6` reads back as a `Float64` |
| `nothing` | `null` |

Anything else is an `ArgumentError` naming the row and the field: `NaN`
and `Inf`, `missing`, an [`Invalid`](@ref) or [`Partition`](@ref) wrapper, a
vector or other collection, a `Char`, and any other type. Map such values
to supported ones first, for example with
`[merge(row, (tol = string(row.tol),)) for row in cases]`. Every row is
checked before anything is written, so after an error `io` holds nothing
from this call.

GitHub Actions runs at most 256 jobs from one matrix; above that,
`github_matrix` still writes every row and warns once.

A workflow computes the matrix in one job and fans out in the next:

```yaml
jobs:
  design:
    runs-on: ubuntu-latest
    outputs:
      cases: \${{ steps.gen.outputs.cases }}
    steps:
      - uses: julia-actions/setup-julia@v2
      - run: julia -e 'using Pkg; Pkg.add("UnitTestDesign")'
      - id: gen
        run: |
          echo "cases=\$(julia -e 'using UnitTestDesign; github_matrix(all_pairs((os = ["ubuntu-latest", "macos-latest"], solver = [:lu, :qr], threads = [1, 4])))')" >> "\$GITHUB_OUTPUT"
  test:
    needs: design
    strategy:
      fail-fast: false
      matrix: \${{ fromJSON(needs.design.outputs.cases) }}
    runs-on: \${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
      - run: julia --project -e 'using Pkg; Pkg.test()'
        env:
          SOLVER: \${{ matrix.solver }}
          JULIA_NUM_THREADS: \${{ matrix.threads }}
```

`fromJSON` turns the document into a matrix whose `include` list is the
cases, and each job reads its values as `matrix.<parameter>`. GitHub
formats numbers itself when it substitutes them; write a value as a string
when the job needs its exact text.

```jldoctest; setup = :(using UnitTestDesign)
julia> cases = all_pairs((os = ["ubuntu-latest", "macos-latest"], solver = [:lu, :qr], threads = [1, 4]));

julia> github_matrix(cases)
{"include":[{"os":"ubuntu-latest","solver":"lu","threads":1},{"os":"ubuntu-latest","solver":"qr","threads":4},{"os":"macos-latest","solver":"lu","threads":4},{"os":"macos-latest","solver":"qr","threads":1}]}
```
"""
github_matrix(cases; io::IO = stdout) = github_matrix(io, cases)

function github_matrix(io::IO, cases)
    rows = _matrix_rows(cases)
    entries = NamedTuple[_matrix_entry(row, k) for (k, row) in enumerate(rows)]
    length(entries) > _GITHUB_MATRIX_LIMIT && @warn(
        "github_matrix: $(length(entries)) jobs exceed GitHub Actions' limit of " *
        "$_GITHUB_MATRIX_LIMIT jobs per matrix, so the workflow will be rejected. Split the cases " *
        "across several matrices, or use fewer cases.")
    text = JSON.json((include = entries,))
    print(io, text)
    return nothing
end

"""
    _matrix_rows(cases) -> AbstractVector

The rows to write: a `TestCases`'s rows, or any collection of rows read once
with `collect`. A single row is an `ArgumentError` saying to wrap it.
"""
function _matrix_rows(cases)
    cases isa TestCases && return cases.cases
    cases isa Union{NamedTuple, Tuple} && throw(ArgumentError(
        "github_matrix takes a collection of rows; wrap a single row in a vector: " *
        "github_matrix([$(_fit(repr(cases), 60))])"))
    rows = applicable(iterate, cases) && !(cases isa AbstractString) ? collect(cases) : nothing
    rows isa AbstractVector || throw(ArgumentError(
        "github_matrix takes a TestCases or a vector of rows (NamedTuples or tuples); " *
        "got $(_fit(repr(cases), 60))"))
    return rows
end

"""
    _matrix_entry(row, k) -> NamedTuple

Row `k` with each value checked and converted for JSON: a `NamedTuple` keeps
its names, a `Tuple` is named `p1`, `p2`, …. An unsupported value is an
`ArgumentError` naming the row and the field.
"""
function _matrix_entry(row, k::Integer)
    if row isa NamedTuple
        names = keys(row)
    elseif row isa Tuple
        names = ntuple(j -> Symbol(:p, j), length(row))
    else
        throw(ArgumentError(
            "github_matrix: row $k, $(_fit(repr(row), 60)) ($(typeof(row))), is not a row; a row " *
            "is a NamedTuple, or a Tuple whose fields are written as p1, p2, …"))
    end
    return NamedTuple{names}(ntuple(j -> _matrix_value(row[j], k, names[j]), length(row)))
end

"""
    _matrix_value(x, k, name)

`x` as JSON.jl should write it: a `Symbol` as its name, any other text as a
`String`, and a `Bool`, a finite number or `nothing` as itself. Anything else
is an `ArgumentError` naming row `k` and field `name`, with the reason.
"""
_matrix_value(x::Nothing, k, name) = x
_matrix_value(x::Bool, k, name) = x
_matrix_value(x::Symbol, k, name) = _matrix_value(String(x), k, name)
function _matrix_value(x::AbstractString, k, name)
    isvalid(x) || _matrix_error(x, k, name, "is not valid UTF-8, which JSON text must be")
    return String(x)
end
_matrix_value(x::Union{Base.BitInteger, BigInt}, k, name) = x
_matrix_value(x::Integer, k, name) = BigInt(x)
function _matrix_value(x::AbstractFloat, k, name)
    isfinite(x) || _matrix_error(x, k, name, "is not a finite number, and JSON has no value for it")
    return x isa Union{Float16, Float32, Float64, BigFloat} ? x : Float64(x)
end
_matrix_value(x::Missing, k, name) =
    _matrix_error(x, k, name, "has no JSON value; write nothing for null")
_matrix_value(x::Invalid, k, name) =
    _matrix_error(x, k, name, "is an Invalid wrapper, which marks a negative case, not data")
_matrix_value(x::Partition, k, name) =
    _matrix_error(x, k, name, "is a Partition wrapper; realize the case, or write the partition's name")
function _matrix_value(x, k, name)
    collection = x isa Union{AbstractArray, Tuple, NamedTuple, AbstractDict, AbstractSet}
    reason = collection ? "is a $(typeof(x)), a collection, but a matrix field holds one value" :
                          "is a $(typeof(x)), which github_matrix does not write"
    _matrix_error(x, k, name, reason)
end

function _matrix_error(x, k, name, reason)
    throw(ArgumentError(
        "github_matrix: row $k, field `$name`: $(_fit(repr(x; context = :limit => true), 60)) $reason. " *
        "Map it to a supported type first: a String, a Symbol, a Bool, a finite Integer or " *
        "AbstractFloat, or nothing."))
end
