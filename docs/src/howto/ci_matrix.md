# Plan a CI matrix

A continuous-integration matrix over operating systems, Julia versions, and
build options grows as a product, and GitHub Actions runs at most 256 jobs
from one matrix. Cover every pair of settings instead, and hand the cases to
the workflow as the JSON that [`github_matrix`](@ref) writes.

## 1. Describe the matrix

Each setting is a parameter, and each rule removes a job that cannot run:

```@example ci
using UnitTestDesign

space = TestSpace((
        os      = ["ubuntu-latest", "macos-latest", "windows-latest"],
        julia   = ["1.10", "1.12", "nightly"],
        threads = [1, 4],
        mkl     = [false, true],
    );
    constraints = [@forbid(os == "macos-latest" && mkl)])   # no MKL on Apple silicon

cases = all_pairs(space)
```

Nine jobs hold every pair of settings that some valid job can hold; the full
product is 36. The `excluded:` line counts the one pair the rule forbids.

## 2. Write the matrix

```@example ci
github_matrix(cases)
```

The document is one line, with no trailing newline, so it can go straight
into `$GITHUB_OUTPUT`. `sprint(github_matrix, cases)` returns it as a
`String`.

## 3. Use it in a workflow

Put steps 1 and 2 in a script, here `.github/ci_cases.jl`: the `using`
line, the space, and `github_matrix(all_pairs(space))`. The workflow and a
local check then run the same code. One job computes the matrix and the
next fans out over it:

```yaml
jobs:
  design:
    runs-on: ubuntu-latest
    outputs:
      cases: ${{ steps.gen.outputs.cases }}
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
      - run: julia -e 'using Pkg; Pkg.add("UnitTestDesign")'
      - id: gen
        run: echo "cases=$(julia .github/ci_cases.jl)" >> "$GITHUB_OUTPUT"
  test:
    needs: design
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.design.outputs.cases) }}
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: ${{ matrix.julia }}
      - run: julia --project -e 'using Pkg; Pkg.test()'
        env:
          JULIA_NUM_THREADS: ${{ matrix.threads }}
          USE_MKL: ${{ matrix.mkl }}
```

`fromJSON` turns the document into a matrix whose `include` list is the
cases, and each job reads its values as `matrix.<parameter>`. The
[`github_matrix`](@ref) docstring has the same workflow with the design
written inline in the `run:` step.

## What values are allowed

JSON holds strings, numbers, booleans, and `null`, so a case's values must
map onto those:

| Value | JSON |
|:--|:--|
| `String` | string |
| `Symbol` | string, its name: `:qr` becomes `"qr"` |
| `Bool` | `true` or `false` |
| finite `Integer` or `AbstractFloat` | number |
| `nothing` | `null` |

Anything else is an `ArgumentError` naming the row and the field: `NaN`,
`Inf`, `missing`, an [`Invalid`](@ref) or [`Partition`](@ref) wrapper, a
collection, or another type. Every row is checked before anything is
written. Map such values to supported ones first:

```@example ci
versions = all_values((julia = [v"1.10", v"1.12"], threads = [1, 4]))
try
    github_matrix(versions)
catch err
    showerror(stdout, err)
end
```

```@example ci
github_matrix([merge(row, (julia = string(row.julia),)) for row in versions])
```

Above 256 rows, `github_matrix` still writes every row and warns once, since
GitHub would reject the workflow:

```@example ci
wide = all_pairs((a = 1:17, b = 1:17))      # 289 cases
using Logging # hide
with_logger(ConsoleLogger(stdout; meta_formatter = (level, _...) -> (:yellow, "Warning:", ""))) do # hide
github_matrix(devnull, wide)
end # hide
```

Split the cases across several matrices, or use a smaller design.

## Pitfall: version numbers written as numbers

A Julia version written as a number is a `Float64`, and `1.10 == 1.1`:

```@example ci
github_matrix(all_values((julia = [1.10, 1.12],)))
```

The job would ask for Julia 1.1. Write versions as strings, as in the space
above, so the job receives the exact text.
