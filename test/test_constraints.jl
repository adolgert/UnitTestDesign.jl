using Test
using TestItemRunner

# Rules and their tabulation (src/constraints.jl): plan Phase 2 steps 3–5 and
# 8. Test names cite the contract clauses (docs/src/dev/contract.md).

@testitem "constraints: every rule form gives the same table (§12.1–§12.5, §12.9)" begin
    using UnitTestDesign: forbids
    domains = (mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6])
    table(rule) = only(TestSpace(domains; constraints = [rule]).tables)

    # Fast mode has no solver: (fast, lu) and (fast, qr) are forbidden.
    forms = [
        @require(mode == :exact || solver == :none),
        @forbid(mode == :fast && solver != :none),
        require(:mode, :solver) do m, s
            m == :exact || s == :none
        end,
        forbid(:mode, :solver) do m, s
            m == :fast && s != :none
        end,
        forbid((m, s) -> m == :fast && s != :none, :mode, :solver),
    ]
    for rule in forms
        @test rule isa Constraint
        @test rule.scope == (:mode, :solver)
        t = table(rule)
        @test t.scope == [1, 2]
        @test t.forbidden == Set([(1, 2), (1, 3)])
    end
    # Two patterns forbid the same pairs between them.
    s = TestSpace(domains; constraints = [forbid((mode = :fast, solver = :lu)),
                                          forbid((mode = :fast, solver = :qr))])
    @test union((t.forbidden for t in s.tables)...) == Set([(1, 2), (1, 3)])
    # A whole-case rule forbids the same rows, lazily (§12.9, §12.20).
    whole = table(forbid(case -> case.mode == :fast && case.solver != :none))
    @test whole.scope == [1, 2, 3] && whole.forbidden === nothing
    for row in Iterators.product(1:2, 1:3, 1:2)
        @test forbids(whole, collect(row)) == ((row[1], row[2]) in [(1, 2), (1, 3)])
    end
    whole_require = table(require(case -> case.mode == :exact || case.solver == :none))
    @test all(forbids(whole_require, collect(r)) == forbids(whole, collect(r))
              for r in Iterators.product(1:2, 1:3, 1:2))

    # Exact mode needs a tight tolerance: only (exact, 1e-3) is forbidden.
    forms = [
        forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance"),
        forbid((tol = 1e-3, mode = :exact)),
        @forbid(mode == :exact && tol == 1e-3),
        @require(mode == :fast || tol != 1e-3),
        forbid(:mode, :tol) do m, t
            m == :exact && t == 1e-3
        end,
    ]
    for rule in forms
        t = table(rule)
        key = Tuple(t.scope) == (1, 3) ? (2, 1) : (1, 2)
        @test sort(t.scope) == [1, 3]
        @test t.forbidden == Set([key])
    end
end


@testitem "constraints: Astra's A == B, B == C (§1.2, §12.6)" begin
    space = TestSpace((A = [1, 2], B = [1, 2], C = [1, 2]);
        constraints = [@require(A == B), @require(B == C)])
    @test [t.scope for t in space.tables] == [[1, 2], [2, 3]]
    @test [t.forbidden for t in space.tables] == [Set([(1, 2), (2, 1)]), Set([(1, 2), (2, 1)])]
    same = TestSpace((A = [1, 2], B = [1, 2], C = [1, 2]);
        constraints = [forbid((a, b) -> a != b, :A, :B), forbid((b, c) -> b != c, :B, :C)])
    @test [t.forbidden for t in same.tables] == [t.forbidden for t in space.tables]
end


@testitem "constraints: `!=` forbids exactly two pairs, not 0.4's over-forbid (§1.6, §12.14)" begin
    using UnitTestDesign: assigned, forbids
    # In 0.4, a disallow function saw `nothing` for unassigned parameters, so
    # `solver != :none` held for a missing solver and fast mode was forbidden
    # outright. A tabulated rule is consulted only with its whole scope assigned.
    space = TestSpace((mode = [:fast, :exact], solver = [:none, :lu, :qr], tol = [1e-3, 1e-6]);
        constraints = [@forbid(mode == :fast && solver != :none)])
    t = only(space.tables)
    @test length(t.forbidden) == 2
    @test t.forbidden == Set([(1, 2), (1, 3)])
    @test !assigned(t, [1, 0, 0])
    @test assigned(t, [1, 1, 0])
    @test !forbids(t, [1, 1, 0])
    @test forbids(t, [1, 2, 0])
    # Of the 12 rows, 8 remain.
    @test count(r -> !forbids(t, collect(r)), Iterators.product(1:2, 1:3, 1:2)) == 8
end


@testitem "constraints: `\$` interpolation in macros (§12.6)" begin
    threshold = 3
    rule = @forbid(n < $threshold)
    threshold = 100  # the value was captured when the rule was built
    @test rule.scope == (:n,)
    @test rule.label == "@forbid(n < \$threshold)"
    space = TestSpace((n = 1:5,); constraints = [rule])
    @test only(space.tables).forbidden == Set([(1,), (2,)])

    lo = 2
    rule = @require(n > $(lo + 1) || m == :any)
    @test rule.scope == (:n, :m)
    space = TestSpace((n = 1:5, m = [:any, :some]); constraints = [rule])
    @test only(space.tables).forbidden == Set([(1, 2), (2, 2), (3, 2)])

    # An interpolated function in call position.
    isbig = x -> x > 3
    rule = @forbid($isbig(n))
    @test rule.scope == (:n,)
    @test only(TestSpace((n = 1:5,); constraints = [rule]).tables).forbidden == Set([(4,), (5,)])

    # An interpolated global that is not called, such as Inf.
    rule = @forbid(x == $Inf)
    @test rule.scope == (:x,)
    @test only(TestSpace((x = [1.0, Inf],); constraints = [rule]).tables).forbidden == Set([(2,)])
end


@testitem "constraints: which identifiers a macro reads as names (§12.6, §12.7)" begin
    # Call position, dotted names, literals, nothing, missing, true, false.
    rule = @forbid(isodd(n) && m === nothing && Base.isless(k, 2) && s == "x" &&
                   q == :sym && flag == true && w === missing && z == 1e-3)
    @test rule.scope == (:n, :m, :k, :s, :q, :flag, :w, :z)
    # First appearance, without repeats.
    @test (@forbid(b == 1 && a == 2 && b == a)).scope == (:b, :a)
    # A comparison chain's operators are not names.
    @test (@forbid(a < b <= c)).scope == (:a, :b, :c)
    # Broadcast calls, and operators passed as values.
    @test (@forbid(any(x .> y))).scope == (:x, :y)
    @test (@forbid(sum(map(+, x, y)) > 3)).scope == (:x, :y)
    # Names bound by a lambda or a generator are not parameters.
    @test (@forbid(any(v -> v > n, vals))).scope == (:n, :vals)
    @test (@forbid(sum(x for x in xs if x > lo) > hi)).scope == (:xs, :lo, :hi)
    @test (@forbid(a[end] == 1)).scope == (:a,)
    # A dotted name is the caller's, never a parameter.
    @test (@forbid(x == Base.pi)).scope == (:x,)
    # A free identifier that is not called is a name, even a global: write $Inf.
    @test (@forbid(x < Inf)).scope == (:x, :Inf)

    # The generated predicates evaluate as written.
    space = TestSpace((vals = [[1, 2], [5]], n = [1, 3]); constraints = [@forbid(any(v -> v > n, vals))])
    @test only(space.tables).forbidden == Set([(1, 1), (1, 2), (2, 2)])
    space = TestSpace((xs = [[1, 2, 3], [2]], lo = [0, 1], hi = [2, 4]);
        constraints = [@forbid(sum(x for x in xs if x > lo) > hi)])
    # sums: xs1 lo0 -> 6, xs1 lo1 -> 5, xs2 lo0 -> 2, xs2 lo1 -> 2
    @test only(space.tables).forbidden == Set([(1, 1, 1), (1, 2, 1), (1, 1, 2), (1, 2, 2)])
    # A parameter named like a function called in the same rule still calls the function.
    space = TestSpace((v = [[1, 2], [1, 2, 3]], size = [2, 3]);
        constraints = [@forbid(size(v) == (2,) && size == 3)])
    @test only(space.tables).forbidden == Set([(1, 2)])
    @test only(space.constraints).scope == (:v, :size)

    # A rule must read a parameter; malformed macro calls are errors.
    @test_throws ArgumentError @forbid(1 == 2)
    @test_throws Exception @macroexpand @forbid(a == 1, b == 2)
    @test_throws Exception @macroexpand @forbid(a = 1)
    @test_throws Exception @macroexpand @forbid(a == 1; colour = "red")
end


@testitem "constraints: macro binding forms follow Julia's scoping (§12.6)" begin
    # Each macro rule gives the table of the explicit listed-names rule, with
    # the same scope, in order of first appearance. Regressions from the
    # Phase 2 review: `(x -> x > n)(1)` read no parameter, and a `let` name
    # was taken for a parameter.
    domains = (n = 0:3, m = 0:3, k = [1, 4], vs = [[1, 2], [3], [0, 5]], xs = [[1], [2, 3]], ys = [[0], [2]])
    t = 2
    cases = [
        # (x -> x > n)(1): only x is local; n is the parameter.
        (@forbid((x -> x > n)(1)), (:n,), forbid(n -> 1 > n, :n)),
        # A let-bound name is local; its right side reads the parameter.
        (@forbid(let x = n; x > 1 end), (:n,), forbid(n -> n > 1, :n)),
        # Right sides see the enclosing scope and earlier bindings: `n = n + 1`
        # reads the parameter, and `y = n * m` the new local n.
        (@forbid(let n = n + 1, y = n * m; y > k end), (:n, :m, :k),
            forbid((n, m, k) -> (n + 1) * m > k, :n, :m, :k)),
        # A generator over a literal.
        (@forbid(any(v > n for v in (1, 2))), (:n,), forbid(n -> any(v > n for v in (1, 2)), :n)),
        # A comprehension with a filter: vs outside, v local in the body and filter.
        (@forbid(sum([v * m for v in vs if v > n]) > k), (:m, :vs, :n, :k),
            forbid((m, vs, n, k) -> sum([v * m for v in vs if v > n]) > k, :m, :vs, :n, :k)),
        # A product `x in xs, y in ys`.
        (@forbid(any(sum(x) + sum(y) > n for x in (xs, ys), y in (ys,))), (:n, :xs, :ys),
            forbid((n, xs, ys) -> any(sum(x) + sum(y) > n for x in (xs, ys), y in (ys,)), :n, :xs, :ys)),
        # Nested levels: the inner iterator sees the outer variable.
        (@forbid(sum(b for v in vs if v > n for b in v:k if b > m; init = 0) > 5), (:vs, :n, :k, :m),
            forbid((vs, n, k, m) -> sum(b for v in vs if v > n for b in v:k if b > m; init = 0) > 5, :vs, :n, :k, :m)),
        # A nested lambda shadowing a parameter: the inner n is local, the outer n the parameter.
        (@forbid((n -> n)(m) > n), (:m, :n), forbid((m, n) -> m > n, :m, :n)),
        # `$t` inside a lambda is the caller's t, captured when the rule is built.
        (@forbid(any(v -> v > $t && v > n, vs)), (:n, :vs), forbid((n, vs) -> any(v -> v > 2 && v > n, vs), :n, :vs)),
        # An anonymous `function` is read like `->`.
        (@forbid(any(function (v) v > n end, vs)), (:n, :vs), forbid((n, vs) -> any(v -> v > n, vs), :n, :vs)),
        # A do block's argument is local.
        (@forbid(any(vs) do v; v > n end), (:vs, :n), forbid((vs, n) -> any(v -> v > n, vs), :vs, :n)),
        # Default values of arguments and keywords read parameters; the arguments stay local.
        (@forbid(((x, y = n; z = m) -> x + y + z)(1) > 3), (:n, :m), forbid((n, m) -> 1 + n + m > 3, :n, :m)),
        (@forbid(((x; w = m) -> x + w)(n) > 3), (:m, :n), forbid((m, n) -> n + m > 3, :m, :n)),
        # Named-tuple fields are names, not parameters; `(; m)` means `(; m = m)`,
        # and a field of a computed value reads the value's parameters.
        (@forbid((; a = n, m).m > k), (:n, :m, :k), forbid((n, m, k) -> m > k, :n, :m, :k)),
    ]
    t = 100  # `$t` was captured when its rule was built
    for (rule, scope, explicit) in cases
        @test rule.scope == scope
        @test explicit.scope == scope
        d = NamedTuple{scope}(Tuple(domains[s] for s in scope))
        a = only(TestSpace(d; constraints = [rule]).tables)
        b = only(TestSpace(d; constraints = [explicit]).tables)
        @test a.scope == b.scope
        @test a.forbidden == b.forbidden
        # Every case has both allowed and forbidden combinations, so agreement means something.
        @test 0 < length(a.forbidden) < prod(length(domains[s]) for s in scope)
    end
    # A shadowed name reads the local value inside and the parameter outside.
    rule = @forbid((n -> n)(m) > n)
    @test rule.predicate(3, 1) && !rule.predicate(1, 3)
    # A nonstandard string literal is a value, not a macro to reject.
    @test (@forbid(occursin(r"a+", s))).scope == (:s,)
    # $Inf stays explicit: a free global that is not called is a name (§12.6).
    @test (@forbid(let y = x; y < Inf end)).scope == (:x, :Inf)
end


@testitem "constraints: unsupported macro forms point to the function form (§12.6)" begin
    function expansion_error(ex)
        try
            macroexpand(@__MODULE__, ex)
            return "no error"
        catch e
            return e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e))"
        end
    end
    rejected = [
        (:(@forbid(begin y = n; y > 1 end)), "the assignment `y = n`"),
        (:(@forbid(x -> (y = x; y > n))), "the assignment `y = x`"),
        (:(@forbid(n += 1)), "the assignment `n += 1`"),
        (:(@forbid(any(for v in vs; end))), "a `for` loop"),
        (:(@require(while n > 1 end)), "a `while` loop"),
        (:(@forbid(try n > 1 catch; false end)), "a `try` block"),
        (:(@forbid(n == :(a + b))), "the quoted expression `:(a + b)`"),
        (:(@forbid(n == quote a end)), "the quoted expression"),
        (:(@forbid(begin global g = n; g end)), "the `global` declaration"),
        (:(@forbid(begin local g = n; g end)), "the `local` declaration"),
        (:(@forbid(@show(n) > 1)), "the macro call `@show`"),
        (:(@forbid(any(function g(x) x > n end, vs))), "the function definition"),
        (:(@forbid(let f(x) = x + n; f(1) > 2 end)), "the function definition"),
    ]
    for (ex, what) in rejected
        msg = expansion_error(ex)
        @test occursin(what, msg)
        polarity = ex.args[1] === Symbol("@require") ? "require" : "forbid"
        @test occursin("use the function form $(polarity)(f, names...)", msg)
        @test occursin("§12.6", msg)
    end
    # The message quotes the rule without file and line comments.
    @test startswith(expansion_error(:(@forbid(@show(n) > 1))), "@forbid(@show(n) > 1) contains")
    # The function form expresses the rejected rules.
    rule = forbid(:n) do n
        y = n
        y > 1
    end
    @test only(TestSpace((n = 0:3,); constraints = [rule]).tables).forbidden == Set([(3,), (4,)])
end


@testitem "constraints: a subtype operator in a macro rule suggests the call form (§12.6)" begin
    function expansion_error(source)
        try
            macroexpand(@__MODULE__, Meta.parse(source))
            return "no error"
        catch e
            return e isa ArgumentError ? e.msg : "not an ArgumentError: $(typeof(e))"
        end
    end
    # The whole rule, a name beside `$x`: the message spells out both forms.
    @test expansion_error("@forbid(T <: \$AbstractFloat)") ==
        "@forbid(T <: \$AbstractFloat) contains `T <: \$AbstractFloat`, and `<:` is not " *
        "supported inside @forbid/@require: Julia parses it as syntax, not as a function " *
        "call (contract §12.6). Write it as the call `(<:)(T, \$AbstractFloat)`, which the " *
        "macro reads, or use the function form forbid(f, names...), here " *
        "forbid((T,) -> T <: AbstractFloat, :T)."
    msg = expansion_error("@require(\$Int <: T)")
    @test occursin("`<:` is not supported", msg) && occursin("`(<:)(\$Int, T)`", msg)
    @test occursin("require((T,) -> Int <: T, :T)", msg)
    # Part of a larger rule, or two bare names: the call form and the general form.
    for (source, call) in [("@forbid(T <: \$AbstractFloat && n > 3)", "(<:)(T, \$AbstractFloat)"),
                           ("@require(T >: Int)", "(>:)(T, Int)"),
                           ("@forbid(eltype(v) <: \$Integer)", "(<:)(eltype(v), \$Integer)")]
        text = expansion_error(source)
        polarity = startswith(source, "@require") ? "require" : "forbid"
        @test startswith(text, "$source contains")
        @test occursin("is not supported inside @forbid/@require", text)
        @test occursin("Write it as the call `$call`", text)
        @test endswith(text, "use the function form $(polarity)(f, names...).")
        @test !occursin("bind names", text)
    end
    # The call form the message suggests is read by the macro, and so is a
    # subtype chain, which parses as a comparison.
    rule = @forbid((<:)(T, $AbstractFloat) && n > 1)
    @test rule.scope == (:T, :n)
    space = TestSpace((T = [Int, Float64], n = [1, 2]); constraints = [rule])
    @test !isallowed(space, (T = Float64, n = 2)) && isallowed(space, (T = Int, n = 2))
    @test (@forbid($Union{} <: T <: $Real)).scope == (:T,)
end


@testitem "constraints: labels, reasons and polarity (§12.2, §12.3)" begin
    using UnitTestDesign: rule_label
    a = @forbid(mode == :fast && solver != :none)
    @test a.label == "@forbid(mode == :fast && solver != :none)"
    @test a.polarity == :forbid && a.source == :macro
    b = @require(mode == :exact || solver == :none; reason = "fast mode has no solver")
    @test b.label == "fast mode has no solver: @require(mode == :exact || solver == :none)"
    @test b.polarity == :require
    why = "fast mode has no solver"
    c = @require(mode == :exact || solver == :none, reason = why)
    @test c.label == b.label
    d = @forbid mode == :fast reason = "no fast"
    @test d.label == "no fast: @forbid(mode == :fast)"
    e = forbid((mode = :exact, tol = 1e-3); reason = "exact mode needs a tight tolerance")
    @test e.label == "exact mode needs a tight tolerance" && e.source == :pattern
    f = require(:mode, :solver) do m, s
        m == :exact || s == :none
    end
    @test f.label == "" && f.polarity == :require && f.source == :names
    g = forbid(case -> case.mode == :fast)
    @test g.scope == () && g.source == :whole_case

    # show is the label, or polarity and scope for a rule with neither.
    @test sprint(show, a) == "@forbid(mode == :fast && solver != :none)"
    @test sprint(show, e) == "exact mode needs a tight tolerance"
    @test sprint(show, f) == "require rule on (mode, solver)"
    @test sprint(show, g) == "forbid rule on the whole case"
    @test sprint(show, forbid((tol = 1e-3,))) == "forbid rule on (tol)"

    # In a space, an unlabeled rule is named by position and scope.
    space = TestSpace((mode = [:fast, :exact], solver = [:none, :lu], tol = [1e-3, 1e-6]);
        constraints = [a, f, g, e])
    @test rule_label(space, 1) == a.label
    @test rule_label(space, 2) == "rule 2 on (mode, solver)"
    @test rule_label(space, 3) == "rule 3 on the whole case"
    @test rule_label(space, 4) == "exact mode needs a tight tolerance"
    @test_throws ArgumentError forbid(m -> true, :mode; reason = :why)
end


@testitem "constraints: forms reject malformed arguments (§5.8, §12.4, §12.5)" begin
    message(g) = try g(); "" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError" end
    # Pattern values are domain values, matched by identity (§12.4, §2.11).
    domains = (n = [1, 2], size = [Partition(:tiny, Returns(1e-9)), 100])
    @test occursin("`n = 1.0`", message(() -> TestSpace(domains; constraints = [forbid((n = 1.0,))])))
    msg = message(() -> TestSpace(domains; constraints = [forbid((n = 3,); reason = "no three")]))
    @test occursin("rule 1 (no three)", msg) && occursin("[1, 2]", msg)
    # A partition by wrapper or by name.
    s = TestSpace(domains; constraints = [forbid((size = :tiny, n = 2)),
                                          forbid((size = Partition(:tiny, identity), n = 1))])
    @test [t.forbidden for t in s.tables] == [Set([(1, 2)]), Set([(1, 1)])]
    @test only(TestSpace(domains; constraints = [forbid((size = 100,))]).tables).forbidden == Set([(2,)])
    # A pattern cannot name an Invalid value (§5.8), and is not empty.
    @test occursin("§5.8", message(() -> forbid((n = Invalid(0),))))
    @test occursin("at least one", message(() -> forbid(NamedTuple())))
    # There is no require pattern form (§12.4).
    @test occursin("no pattern form", message(() -> require((n = 1,))))
    # Listed names are distinct (§12.5); a predicate comes first.
    @test occursin("lists `n` twice", message(() -> forbid((a, b) -> true, :n, :n)))
    @test occursin("no predicate", message(() -> forbid(:mode, :solver)))
    @test occursin("no predicate", message(() -> require((a = 1,), :b)))
end


@testitem "constraints: an unknown name lists the parameters and suggests `\$name` (§12.8, §12.13)" begin
    limit = 3
    err = try
        TestSpace((n = 1:5, m = [:a, :b]); constraints = [@forbid(m == :a), @forbid(n > limit)])
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("rule 2 (@forbid(n > limit))", err.msg)
    @test occursin("names `limit`, which is not a parameter", err.msg)
    @test occursin("The parameters are n, m.", err.msg)
    @test occursin("If `limit` is a variable, write `\$limit` to use its value.", err.msg)
    # The function forms name the parameter and list the names, without the macro hint.
    err = try
        TestSpace((n = 1:5, m = [:a, :b]); constraints = [forbid((n, k) -> n > k, :n, :k)])
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("rule 1 on (n, k) names `k`", err.msg) && occursin("n, m", err.msg)
    @test !occursin("\$k", err.msg)
    err = try
        TestSpace((n = 1:5,); constraints = [forbid((colour = :red,))])
    catch e
        e
    end
    @test err isa ArgumentError && occursin("`colour`", err.msg)
end


@testitem "constraints: a predicate must return a Bool (§12.15)" begin
    message(g) = try g(); "" catch e; e isa ArgumentError ? e.msg : "not an ArgumentError" end
    rule = forbid(:n; reason = "big n") do n
        n > 2 ? missing : false
    end
    msg = message(() -> TestSpace((n = 1:3,); constraints = [rule]))
    @test occursin("rule 1 (big n) returned missing", msg)
    @test occursin("(n = 3,)", msg)
    # A require rule reports the value itself: never !nothing or !1 == -2.
    rule = require(:n) do n
        n == 2 ? nothing : true
    end
    @test occursin("returned nothing", message(() -> TestSpace((n = 1:3,); constraints = [rule])))
    rule = require(:n) do n
        1
    end
    @test occursin("returned 1,", message(() -> TestSpace((n = 1:3,); constraints = [rule])))
    rule = @forbid(n + 1)
    @test occursin("rule 1 (@forbid(n + 1)) returned 2", message(() -> TestSpace((n = 1:3,); constraints = [rule])))
    # A lazy rule reports when it is consulted.
    space = TestSpace((n = 1:3, m = 1:2); constraints = [forbid(case -> case.n)])
    @test occursin("rule 1 on the whole case returned 1",
                   message(() -> UnitTestDesign.forbids(only(space.tables), [1, 1])))
end


@testitem "constraints: a predicate's exception becomes a ConstraintError (§12.16)" begin
    rule = forbid(:n, :d; reason = "ratio too big") do n, d
        n ÷ d > 2
    end
    err = try
        TestSpace((n = [7, 8], d = [0, 1]); constraints = [rule])
    catch e
        e
    end
    @test err isa ConstraintError
    @test err.rule == "rule 1 (ratio too big)"
    @test err.arguments === (n = 7, d = 0)
    @test err.exception isa DivideError
    shown = sprint(showerror, err)
    @test occursin("rule 1 (ratio too big) threw an exception for (n = 7, d = 0)", shown)
    @test occursin("DivideError", shown)

    # A predicate's own ArgumentError is wrapped too, and a macro rule is named by its text.
    check(n) = n == 2 ? throw(ArgumentError("two")) : false
    rule = @forbid(check(n))
    err = try TestSpace((n = 1:3,); constraints = [rule]) catch e; e end
    @test err isa ConstraintError && err.exception isa ArgumentError
    @test err.rule == "rule 1 (@forbid(check(n)))" && err.arguments === (n = 2,)

    # A lazy rule throws when consulted, and memoizes nothing for that row.
    calls = Ref(0)
    space = TestSpace((a = 1:2, b = 1:2); constraints = [forbid(function (case)
        calls[] += 1
        case.a == 2 ? error("no") : false
    end)])
    table = only(space.tables)
    @test !UnitTestDesign.forbids(table, [1, 2])
    err = try UnitTestDesign.forbids(table, [2, 1]) catch e; e end
    @test err isa ConstraintError && err.arguments === (a = 2, b = 1)
    @test err.rule == "rule 1 on the whole case"
    @test_throws ConstraintError UnitTestDesign.forbids(table, [2, 1])
    @test calls[] == 3

    # Through the public calls, the exception surfaces from whichever call
    # evaluated the rule. explain searches for a completion of a = 2.
    err = try explain(space, (a = 2,)) catch e; e end
    @test err isa ConstraintError && err.rule == "rule 1 on the whole case" && err.arguments.a == 2
    # These rows avoid a = 2, so reading them does not throw; the search for
    # a missing pair with a = 2 does.
    rows = [(a = 1, b = 1), (a = 1, b = 2)]
    @test all(row -> isallowed(space, row), rows)
    err = try coverage(rows, space) catch e; e end
    @test err isa ConstraintError && err.rule == "rule 1 on the whole case" && err.arguments.a == 2
end


@testitem "constraints: tabulation_limit makes a rule lazy, with one warning (§12.19)" begin
    using UnitTestDesign: forbids
    domains = (a = 1:3, b = 1:2, c = [:x, :y])
    rules() = [@forbid(a == 2 && c == :y), @forbid(a + b > 4), forbid((b = 1, c = :x))]
    eager = TestSpace(domains; constraints = rules())
    @test all(t -> t.lazy === nothing, eager.tables)
    # Rules 1 and 2 have 6 combinations each, above 4; rule 3 has 4.
    lazy = @test_logs((:warn, r"rule 1 \(@forbid\(a == 2 && c == :y\)\) reads a, c, whose 6 combinations"),
                      (:warn, r"rule 2 .*exceed tabulation_limit = 4.*narrower rules"),
                      TestSpace(domains; constraints = rules(), tabulation_limit = 4))
    @test lazy.tabulation_limit == 4
    @test lazy.tables[1].forbidden === nothing && lazy.tables[1].lazy !== nothing
    @test lazy.tables[2].forbidden === nothing
    @test lazy.tables[3].forbidden == Set([(1, 1)])
    # The lazy tables give the tabulated answers.
    for (e, l) in zip(eager.tables, lazy.tables)
        @test e.scope == l.scope
        for row in Iterators.product(1:3, 1:2, 1:2)
            @test forbids(e, collect(row)) == forbids(l, collect(row))
        end
    end
    # A lazy rule is evaluated at most once per combination within one
    # operation, whose Feasibility holds the memo; the table itself keeps
    # none, so the space retains nothing (§12.19).
    calls = Ref(0)
    counted = forbid(:a, :b) do a, b
        calls[] += 1
        a == b
    end
    s = @test_logs (:warn,) TestSpace(domains; constraints = [counted], tabulation_limit = 5)
    @test calls[] == 0
    t = only(s.tables)
    f = UnitTestDesign.Feasibility(s.ordinary, s.tables)
    for _ in 1:3, row in Iterators.product(1:3, 1:2, 1:2)
        @test forbids(f, 1, collect(row)) == forbids(t, collect(row))
    end
    @test calls[] == 6 + 3 * 12
    @test UnitTestDesign.memo_size(f) == 6
    calls[] = 0
    g = UnitTestDesign.Feasibility(s.ordinary, s.tables)
    forbids(g, 1, [1, 1, 1])
    @test calls[] == 1
    # The product counts ordinary values only, so Invalid values do not push a rule over.
    s = @test_logs TestSpace((a = [1, 2, Invalid(0)], b = [1, 2]);
                             constraints = [@forbid(a == b)], tabulation_limit = 4)
    @test only(s.tables).forbidden == Set([(1, 1), (2, 2)])
end


@testitem "constraints: whole-case rules are lazy and receive a NamedTuple (§12.9, §12.20, §4.5)" begin
    using UnitTestDesign: forbids
    seen = []
    rule = forbid(; reason = "no tiny fast") do case
        push!(seen, case)
        case.size == :tiny && case.mode == :fast
    end
    # Never tabulated and never a warning, even above tabulation_limit.
    space = @test_logs TestSpace((size = [Partition(:tiny, Returns(1e-9)), 100, Invalid(-1)],
                                  mode = [:fast, :exact]); constraints = [rule], tabulation_limit = 1)
    @test isempty(seen)
    t = only(space.tables)
    @test t.scope == [1, 2]
    @test t.forbidden === nothing && t.lazy !== nothing
    @test forbids(t, [1, 1])
    @test !forbids(t, [2, 1])
    @test !forbids(t, [1, 2])
    @test length(seen) == 3
    @test seen[1] isa NamedTuple
    @test seen[1] === (size = :tiny, mode = :fast)  # the partition's name (§4.5)
    @test seen[2] === (size = 100, mode = :fast)
    # Unmemoized on the table; memoized per row within an operation.
    forbids(t, [1, 1])
    @test length(seen) == 4
    f = UnitTestDesign.Feasibility([[1, 2], [1, 2]], space.tables)
    @test forbids(f, 1, [1, 1]) && forbids(f, 1, [1, 1])
    @test length(seen) == 5
    # Never consulted at an invalid value: the table refuses (§5.8).
    err = try forbids(t, [3, 1]) catch e; e end
    @test err isa ArgumentError && occursin("Invalid(-1)", err.msg)
    @test length(seen) == 5
    # A negative row at `size` does not consult it (§5.6).
    @test isempty(UnitTestDesign.active_tables(space, 1))
end


@testitem "constraints: predicates see partition names, never Invalid (§4.5, §5.8, §12.14)" begin
    seen = []
    rule = forbid(:size, :n) do size, n
        push!(seen, (size, n))
        size == :tiny && n == 1
    end
    space = TestSpace((size = [Partition(:tiny, Returns(1e-9)), 100, Invalid(0)],
                       n = [1, Invalid(1), 2]); constraints = [rule])
    @test seen == [(:tiny, 1), (100, 1), (:tiny, 2), (100, 2)]
    @test !any(x -> x isa Invalid, Iterators.flatten(seen))
    @test only(space.tables).forbidden == Set([(1, 1)])
    # A lazy table at an invalid index is an internal error, never a verdict.
    lazy = @test_logs (:warn,) TestSpace((size = [Partition(:tiny, Returns(1e-9)), 100, Invalid(0)],
                      n = [1, Invalid(1), 2]); constraints = [rule], tabulation_limit = 1)
    @test_throws ArgumentError UnitTestDesign.forbids(only(lazy.tables), [3, 1])
    @test_throws ArgumentError UnitTestDesign.forbids(only(lazy.tables), [1, 2])
    # Predicates compare however they are written: n == 1 matches 1 and 1.0,
    # while a pattern matches by identity (§12.23, §12.4).
    domains = (n = Any[1, 1.0, 2],)
    @test only(TestSpace(domains; constraints = [@forbid(n == 1)]).tables).forbidden == Set([(1,), (2,)])
    @test only(TestSpace(domains; constraints = [forbid((n = 1,))]).tables).forbidden == Set([(1,)])
    @test only(TestSpace(domains; constraints = [forbid((n = 1.0,))]).tables).forbidden == Set([(2,)])
end


@testitem "constraints: tabulation order is fixed (§12.17, §12.18, §9.1)" begin
    calls = []
    rule = forbid(:b, :a) do b, a
        push!(calls, (b, a))
        a == 2 && b == :y
    end
    domains = (a = [1, 2, Invalid(9), 3], b = [:x, :y], c = [0])
    s1 = TestSpace(domains; constraints = [rule, @forbid(c == 0 && a == 3)])
    # Once per combination of ordinary values, Iterators.product order over the
    # scope in scope order: the first scope parameter varies fastest.
    @test calls == [(:x, 1), (:y, 1), (:x, 2), (:y, 2), (:x, 3), (:y, 3)]
    @test s1.tables[1].scope == [2, 1]
    @test s1.tables[1].forbidden == Set([(2, 2)])
    empty!(calls)
    s2 = TestSpace(domains; constraints = [rule, @forbid(c == 0 && a == 3)])
    @test calls == [(:x, 1), (:y, 1), (:x, 2), (:y, 2), (:x, 3), (:y, 3)]
    @test [t.scope for t in s1.tables] == [t.scope for t in s2.tables]
    @test [t.forbidden for t in s1.tables] == [t.forbidden for t in s2.tables]
    @test collect(s1.tables[2].forbidden) == collect(s2.tables[2].forbidden)
    # Rules are tabulated in the order given.
    order = Symbol[]
    TestSpace((a = [1],); constraints = [forbid(a -> (push!(order, :first); false), :a),
                                         forbid(a -> (push!(order, :second); false), :a)])
    @test order == [:first, :second]
end


@testitem "constraints: tables agree with the oracle on random problems" setup=[Checker] begin
    using Random
    using UnitTestDesign: forbids
    rng = Xoshiro(0x2026_0927_0000_0001)
    for trial in 1:40
        problem = random_problem(rng; strength = 2)
        rules = [forbid(r.predicate, problem.names[r.scope]...) for r in problem.rules]
        space = TestSpace(Pair.(problem.names, problem.domains)...; constraints = rules)
        agree = true
        for (r, t) in zip(problem.rules, space.tables)
            brute = Set(key for key in Iterators.product((eachindex(problem.domains[p]) for p in r.scope)...)
                        if r.predicate((problem.domains[p][key[j]] for (j, p) in enumerate(r.scope))...))
            agree &= t.scope == r.scope && t.forbidden == brute
        end
        @test agree
        valid = count(Iterators.product((eachindex(d) for d in problem.domains)...)) do key
            !any(t -> forbids(t, collect(key)), space.tables)
        end
        @test valid == length(valid_rows(problem.space))
    end
end
