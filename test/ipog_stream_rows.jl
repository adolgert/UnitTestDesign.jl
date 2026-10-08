# IPOG()'s total rows on the random stream of test_ipog_core.jl's
# random-problem item (test/random_problems.jl; the stream `IPOG_STREAM_SEED`,
# drawn from its start at each strength), which the item pins, so that a
# change that keeps every design valid but makes them larger, or smaller, is
# seen. Julia 1.10's `randperm` and `shuffle` differ from 1.13's, so the
# problems differ between versions: `IPOG_STREAM_ROWS` holds the totals by a
# digest of the problems drawn, one entry for each version's stream, and the
# item leaves a stream with no entry unpinned, as a broken test, so that it
# shows. To write the entries again after a change to IPOG()'s rows (or to
# the generator), on Julia 1.13 and on Julia 1.10, from the repository root:
#
#     julia --project=test -e 'module C; for f in ("checker", "random_problems", "fixtures", "fixture_model");
#                                  include("test/$f.jl"); end; end
#                              include("test/ipog_stream_rows.jl"); println(ipog_stream_entry(C.random_problem, C.test_space))'
#
# and put the line it prints in `IPOG_STREAM_ROWS` in place of that version's.

using UnitTestDesign: IPOG, Request, generate
using Random: Xoshiro

"The stream's seed, and how many problems at each strength the pin counts: the item always draws at least these."
const IPOG_STREAM_SEED = 0x2026_1005_0004
const IPOG_STREAM_COUNT = 40

"IPOG()'s total rows on the first `IPOG_STREAM_COUNT` problems at strengths 2 and 3, by the stream's `stream_digest`."
const IPOG_STREAM_ROWS = Dict{UInt64, @NamedTuple{t2::Int, t3::Int}}(
    0xd83b994882192ba5 => (t2 = 578, t3 = 1888),   # Julia 1.13
    0x5cb517686cdba845 => (t2 = 536, t3 = 1582),   # Julia 1.10
)

"FNV-1a, 64 bits, of the problems as they print (`RandomProblem`'s `show`), one per line: the same on every Julia version."
function stream_digest(problems)
    h = 0xcbf29ce484222325
    for problem in problems, b in codeunits(repr(problem) * "\n")
        h = (h ⊻ UInt64(b)) * 0x00000100000001b3
    end
    return h
end

"""
    ipog_stream(random_problem, test_space; seed = IPOG_STREAM_SEED) -> (digest, totals)

The first `IPOG_STREAM_COUNT` problems of the stream at strengths 2 and 3,
each strength drawn from the stream's start (`Xoshiro(seed)`), with their
`stream_digest` and IPOG()'s total rows at each strength, `(t2 = …, t3 = …)`.
"""
function ipog_stream(random_problem, test_space; seed = IPOG_STREAM_SEED)
    drawn = Any[]
    totals = Dict(2 => 0, 3 => 0)
    for strength in (2, 3)
        rng = Xoshiro(seed)
        for _ in 1:IPOG_STREAM_COUNT
            problem = random_problem(rng; strength)
            push!(drawn, problem)
            totals[strength] += size(generate(IPOG(), Request(test_space(problem.space); strength)).matrix, 2)
        end
    end
    return stream_digest(drawn), (t2 = totals[2], t3 = totals[3])
end

"`IPOG_STREAM_ROWS`'s entry for this Julia version's stream, as a line of code."
function ipog_stream_entry(random_problem, test_space)
    digest, totals = ipog_stream(random_problem, test_space)
    return "    0x$(string(digest; base = 16, pad = 16)) => (t2 = $(totals.t2), t3 = $(totals.t3)),   # Julia " *
           "$(VERSION.major).$(VERSION.minor)"
end
