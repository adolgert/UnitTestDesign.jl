var documenterSearchIndex = {"docs":
[{"location":"features/#Features","page":"Features","title":"Features","text":"","category":"section"},{"location":"features/#Coverage-levels","page":"Features","title":"Coverage levels","text":"","category":"section"},{"location":"features/","page":"Features","title":"Features","text":"all_values: Every value is used at least once.\nall_pairs: Every pair of values is used at least once.\nall_triples: Every triple of values is used at least once.\nall_tuples: Generate test sets with arbitrary coverage level.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"Increase coverage for a subset of the parameters by adding a dictionary that lists the indices of sets of parameters to cover.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"test_set = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];\n    wayness = Dict(3 => [[1, 3, 4]])\n    )","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"The dictionary keys are the higher coverage levels, so \"3\" means all triples. The dictionary values are lists of sets of parameters which, together, should be covered at the given level.","category":"page"},{"location":"features/#Multiple-generators","page":"Features","title":"Multiple generators","text":"","category":"section"},{"location":"features/","page":"Features","title":"Features","text":"IPOG: The in-parameter-order generator is fast and gives the same result every time.\nGND: This greedy, non-deterministic generator searches for shorter answers and can be slow.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"They are both called greedy generators.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"test_set = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];\n    generator = IPOG()\n    )","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"For the greedy, non-deterministic generator, you can set the random number generator to make it repeatable, or set the number of candidate test cases it generates each time it looks for a test case. A higher M will make it run longer and possibly find a smaller test set.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"rng = Random.MersenneTwister(979024)\ntest_set = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];\n    generator = GND(rng = rng, M = 100)\n    )","category":"page"},{"location":"features/#Exclude-forbidden-combinations-of-parameters","page":"Features","title":"Exclude forbidden combinations of parameters","text":"","category":"section"},{"location":"features/","page":"Features","title":"Features","text":"If, for instance, this function can't be called with \"high\" and :optim, then pass a filter function. This filter returns true for any combination that should be forbidden.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"disallow(n, level, value, kind) = level == \"high\" && kind == :optim\ntest_set = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];\n    filter = disallow\n    )","category":"page"},{"location":"features/#Seed-test-cases","page":"Features","title":"Seed test cases","text":"","category":"section"},{"location":"features/","page":"Features","title":"Features","text":"If there are particular tests that must be run, these already include some of the tuples that should be covered. You can pass the must-run test cases, and they will be included among the test cases.","category":"page"},{"location":"features/","page":"Features","title":"Features","text":"must_test = [[1, \"mid\", 3.7, :relax], [1, \"mid\", 4.9, :relax]]\ntest_cases = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim];\n    seeds = must_test\n    )","category":"page"},{"location":"contributing/#Contributing","page":"Contributing","title":"Contributing","text":"","category":"section"},{"location":"contributing/#Examples-of-contributions","page":"Contributing","title":"Examples of contributions","text":"","category":"section"},{"location":"contributing/","page":"Contributing","title":"Contributing","text":"Adding an algorithm for test case generation.\nTelling me which package already has an algorithm to use.\nImproving the documentation or testing builds.\nSuggesting a better API.","category":"page"},{"location":"contributing/","page":"Contributing","title":"Contributing","text":"The Github site has an Issues page, and my email is listed.","category":"page"},{"location":"contributing/#Branch-process","page":"Contributing","title":"Branch process","text":"","category":"section"},{"location":"contributing/","page":"Contributing","title":"Contributing","text":"The main branch is for development.\nReleases go to release.","category":"page"},{"location":"contributing/#Conduct","page":"Contributing","title":"Conduct","text":"","category":"section"},{"location":"contributing/","page":"Contributing","title":"Contributing","text":"Let's follow the contributor covenant.","category":"page"},{"location":"reference/","page":"Reference","title":"Reference","text":"CurrentModule = UnitTestDesign","category":"page"},{"location":"reference/#Reference","page":"Reference","title":"Reference","text":"","category":"section"},{"location":"reference/","page":"Reference","title":"Reference","text":"Modules = [UnitTestDesign]\nprivate = false","category":"page"},{"location":"reference/#UnitTestDesign.UnitTestDesign","page":"Reference","title":"UnitTestDesign.UnitTestDesign","text":"Generates test cases, which are sets of arguments to use for testing functions.\n\n\n\n\n\n","category":"module"},{"location":"reference/#UnitTestDesign.GND","page":"Reference","title":"UnitTestDesign.GND","text":"Greedy Non-deterministic (GND).\n\nThis algorithm searches for test cases. It will generate tuples of any order. It generates a different set every time it is invoked.\n\nArguments\n\nrng::Random.AbstractRNG: This option is a random number generator. Set this if you want to generate the same test cases twice in a row.\nM::Int: The number of times it should create a candidate test case each time it creates a candidate. The default is 50. Raising this number could improve test cases and slow generation.\n\nExtended\n\nThis algorithm starts with the seeded test cases and then adds test cases, one at a time. It chooses those parameters that are least used, so far, and then chooses values of those parameters that are least covered by previous tuples. At each step, there is some probability of choosing among nearly-equal next values.\n\nIt's not complicated, but it can be slow because every next choice checks against all possible tuples. For large numbers of parameters or large numbers of possible values of each parameter, this generator can be slow, so test it for fewer values first and gradually increase the number of parameters or parameter values.\n\n\n\n\n\n","category":"type"},{"location":"reference/#UnitTestDesign.IPOG","page":"Reference","title":"UnitTestDesign.IPOG","text":"In-parameter-order General (IPOG).\n\nThis algorithm generates test cases quickly. It will generate tuples of any order. It always generates the same set of test cases for the same set of input values.\n\nLei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence. 2008. “IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial Testing.” Software Testing, Verification & Reliability 18 (3): 125–48.\n\n\n\n\n\n","category":"type"},{"location":"reference/#UnitTestDesign.MatrixCoverage","page":"Reference","title":"UnitTestDesign.MatrixCoverage","text":"Represents covered tuples using a two-dimensional matrix. Each column is another tuple to cover. Each row is a parameter. A zero means this parameter is not part of the tuple. The initial matrix represents all tuples to cover. The remain integer is the number of tuples left to cover. As tuples are covered, they are swapped to the end of the uncovered tuples, and the remain value is decremented.\n\nThe arity is an integer array, the same length as the number of parameters. Each member of the array is the number of possible values each parameter can take.\n\nThis representation should be slow for lookup of tuples and take lots of memory, but it is a clear representation with which to understand the interface to the data structure.\n\n\n\n\n\n","category":"type"},{"location":"reference/#Base.eltype-Tuple{UnitTestDesign.MatrixCoverage}","page":"Reference","title":"Base.eltype","text":"The element type of the MatrixCoverage class is determined by the element type of the arity because an element large enough to hold the arity is what defines the minimum possible element type.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.add_coverage!-Tuple{UnitTestDesign.MatrixCoverage,Any}","page":"Reference","title":"UnitTestDesign.add_coverage!","text":"add_coverage!(allc, entry)\n\nThe coverage matrix, allc, has row_cnt entries that are considered uncovered, and the rest have been covered already. This adds a new entry, which is a complete set of parameter choices. For every parameter that's covered, this moves those to the end. It returns a new row_cnt which is the number of initial uncovered rows.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_combinations-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.all_combinations","text":"all_combinations(arity, n_way)\n\nThis represents possible coverage as a matrix, one column per parameter, zero if not used. arity is a list of the number of values for each parameter, and n_way is the order of the combinations, most commonly 2-way.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_combinations_matrix-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.all_combinations_matrix","text":"allcombinationsmatrix(arity, n_way)\n\nCreate matrix coverage that includes all n-way combinations of parameters which can take arity values, where arity is a vector of integers to represent the number of possible values for each parameter, in order.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_pairs-Tuple","page":"Reference","title":"UnitTestDesign.all_pairs","text":"all_pairs(parameters...; kwargs...)\n\nEnsure that the returned test cases include every pair of parameters at least once.\n\nExamples\n\nall_pairs([1, 2, 3], [\"a\", \"b\", \"c\"], [true, false])\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_triples-Tuple","page":"Reference","title":"UnitTestDesign.all_triples","text":"all_triples(parameters...; kwargs...)\n\nEnsure that the returned test cases include every combination of three parameters at least once.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_tuples-Tuple","page":"Reference","title":"UnitTestDesign.all_tuples","text":"all_tuples(parameters...; n_way, engine, disallow, seeds, wayness, Counter)\n\nGiven a tuple of parameters, generate all test cases that cover all n_way combinations of those parameters.\n\nArguments\n\nengine=IPOG(): The engine is IPOG() or GND().\ndisallow=nothing: The disallow function is a function of the parameters that returns true when that combination should be forbidden.\nseeds=[]: is a list of test cases that must be included among those\n\ngenerated.\n\nwayness is a dictionary that specifies subsets of parameters for which to increase the n_way combinations. For instance, if the combinations are two-way, and you want the third-sixth parameters to be three-way covered, use, wayness = Dict(3 => [[3, 4, 5, 6]]).\nCounter=IntThe Counter is an integer type to use for\n\nthe computation. It must be large enough to hold the integer number of the parameters.\n\nExamples\n\nall_tuples([1, 2, 3], [\"a\", \"b\", \"c\"], [true, false]; n_way = 2)\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.all_values-Tuple","page":"Reference","title":"UnitTestDesign.all_values","text":"all_values(parameters...; kwargs...)\n\nEnsure that the test cases include every value of every parameter at least once.\n\nSee also: all_tuples\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.argmin_rand-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.argmin_rand","text":"argmin_rand(rng, v)\n\nGiven a vector, find the index of the smallest value. If more than one value is the smallest, then randomly choose among the smallest values.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.case_compatible_with_tuple-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.case_compatible_with_tuple","text":"Example matches.       crossed      incomplete cover case  [0 1 0 2]    [1 0 0 3]  [1 1 0 2] tuple [1 0 3 0]    [1 1 0 3]  [1 0 0 2]\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.case_covers_tuple-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.case_covers_tuple","text":"Example matches. case  [1 1 0 2] tuple [1 0 0 2]\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.case_partial_cover-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.case_partial_cover","text":"Example matches.       incomplete cover case  [1 0 0 3]  [1 1 0 2] tuple [1 1 0 3]  [1 0 0 2]\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.choose_last_parameter!","page":"Reference","title":"UnitTestDesign.choose_last_parameter!","text":"choose_last_parameter!(taller, arity, n_way)\n\nGiven a test set where the first k-1 parameters are chosen and the last parameter has not been chosen, this fills in the last parameters for each test case.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.cover_remaining_by_creating_cases","page":"Reference","title":"UnitTestDesign.cover_remaining_by_creating_cases","text":"If not all tuples are covered by a test set, this creates new test cases to cover all remaining tuples.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.coverage_by_parameter-Tuple{UnitTestDesign.MatrixCoverage}","page":"Reference","title":"UnitTestDesign.coverage_by_parameter","text":"coverage_by_parameter(allc::MatrixCoverage)\n\nGiven a coverage matrix, return how many times each parameter participates in an uncovered tuple. The return value is a vector of integers, where each value is the number of times that parameter appears in any uncovered tuple.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.coverage_by_value-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.coverage_by_value","text":"coverage_by_value(allc, param_idx)\n\nGiven a particular parameter, look at that column of the coverage matrix and return a histogram of how many times each value appears in that column. We want to know which parameter has the most tuples to cover so that we can address it first.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.fill_consistent_matches","page":"Reference","title":"UnitTestDesign.fill_consistent_matches","text":"fill_consistent_matches(mc::MatrixCoverage, entry)\n\nGiven an entry that's partially decided, fill in every covering tuple that matches the existing values, in any order.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.fill_missing_test_set_values!","page":"Reference","title":"UnitTestDesign.fill_missing_test_set_values!","text":"The given test cases have missing values, which are zeros. This fills in missing values anywhere they cover tuples.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.fill_remaining_missing_values!-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.fill_remaining_missing_values!","text":"As a finishing step on a set of test cases, this fills in missing values which aren't needed to cover the tuples but can increase coverage of higher tuples.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.first_match_for_parameter-Tuple{UnitTestDesign.MatrixCoverage,Any}","page":"Reference","title":"UnitTestDesign.first_match_for_parameter","text":"first_match_for_parameter(mc::MatrixCoverage, param_idx)\n\nFind the first uncovered tuple for a particular parameter value.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.insert_tuple_into_tests","page":"Reference","title":"UnitTestDesign.insert_tuple_into_tests","text":"Loop over remaining tuples instead of looping over each test. For each tuple, loop over tests where that tuple could go. If that fails, add the tuple at the end as its own test.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.ipog-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.ipog","text":"ipog(arity, n_way)\n\nThe arity is an integer array of the number of possible values each parameter can take. The n_way is whether each parameter must appear once in the test suite, or whether each pair of parameters must appear together, or whether each triple must appear together. The wayness can be set as high as the length of the arity.\n\nThis uses the in-parameter-order-general algorithm. It will always return the same set of values. It takes less time and memory than most other approaches.\n\nThis function represents a test set as a two-dimensional array of the same integer type as the input arity. Each value of the array is either an integer number, from 1 to the arity of that parameter, or it is 0 for what the paper calls a don't-care value.\n\nLei, Yu, Raghu Kacker, D. Richard Kuhn, Vadim Okun, and James Lawrence.\n\n“IPOG/IPOG-D: Efficient Test Generation for Multi-Way Combinatorial\n\nTesting.” Software Testing, Verification & Reliability 18 (3): 125–48.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.match_score-Tuple{UnitTestDesign.MatrixCoverage,Any}","page":"Reference","title":"UnitTestDesign.match_score","text":"match_score(allc, entry)\n\nIf we were to add this entry to the trials, how many uncovered n-tuples would it now cover? allc is the matrix of n-tuples. row_cnt is the first set of rows, representing uncovered tuples. n_way is the length of each tuple. Entry is a set of putative parameter values. Returns an integer number of newly-covered tuples.\n\nThis is a place to look into alternative algorithms. We could weight the match score by increasing the score for greater wayness.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.matches_from_missing","page":"Reference","title":"UnitTestDesign.matches_from_missing","text":"Given an entry in the test set that has missing values, which are zeros, find any matches that could be created by setting those missing values. Return a new version of the entry.\n\n\n\n\n\n","category":"function"},{"location":"reference/#UnitTestDesign.most_matches_existing-Tuple{UnitTestDesign.MatrixCoverage,Any,Any}","page":"Reference","title":"UnitTestDesign.most_matches_existing","text":"most_matches_existing(mc::MatrixCoverage, existing, param_idx)\n\nThe existing vector is a partial test case. Each nonzero entry in this test case is considered as decided. This function then determines, for the next parameter, chosen by paramidx, which value of paramidx, between 1 and its arity, would cover the most tuples. It returns a histogram of how many uncovered tuples could be covered, given the existing choices and a particular value of this parameter.\n\nThis returns all tuples that the existing case could exactly cover if it didn't have missing values. That means the existing vector either has the same number of entries as the tuple or it has fewer entries than the tuple.\n\nA value of the param_idx parameter matches with a tuple if its existing choices match at least some part of the tuple and don't disagree with any part of the tuple.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.multi_way_coverage-Tuple{Any,Any,Any}","page":"Reference","title":"UnitTestDesign.multi_way_coverage","text":"Builds a coverage set where subsets of variables have different wayness.\n\nThe all-pairs algorithm is 2-way. All-triples is 3-way. This function takes a base_wayness, which would be 2 or 3 for those examples. Then it takes a dictionary that specifies higher wayness for subsets of parameters.\n\nThe wayness is a dictionary from an integer, the wayness, to a set of lists of indices that should have that wayness together. The base_wayness is the n_way for the rest of the variables. It should be less than the other sets of waynesses.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.next_multiplicative!-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.next_multiplicative!","text":"next_multiplicative!(values, arity)\n\nGiven a set of values for parameters, this returns the next possible value. When it reaches the end, it cycles back to the start. The first value is all ones. The last value equals the arity.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.one_parameter_combinations-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.one_parameter_combinations","text":"one_parameter_combinations(arity, n_way)\n\nGenerates all combinations that are nonzero for the last parameter. This is for in-parameter-order generation, where we need only those tuples that end with this column being nonzero.\n\nThe construction method is to leave out the given parameter and construct all n_way - 1 tuples. Then copy and paste that once for each possible value of the given parameter.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.one_parameter_combinations_matrix-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.one_parameter_combinations_matrix","text":"one_parameter_combinations(arity, n_way)\n\nGenerates all combinations that are nonzero for the last parameter. This is for in-parameter-order generation, where we need only those tuples that end with this column being nonzero.\n\nThe construction method is to leave out the given parameter and construct all n_way - 1 tuples. Then copy and paste that once for each possible value of the given parameter.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.parameter_cnt-Tuple{UnitTestDesign.MatrixCoverage}","page":"Reference","title":"UnitTestDesign.parameter_cnt","text":"The number of parameters for this design.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.remaining_uncovered-Tuple{UnitTestDesign.MatrixCoverage}","page":"Reference","title":"UnitTestDesign.remaining_uncovered","text":"How many tuples have not been covered yet.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.remove_combinations!-Tuple{UnitTestDesign.MatrixCoverage,Any}","page":"Reference","title":"UnitTestDesign.remove_combinations!","text":"remove_combinations!(mc::MatrixCoverage, disallow)\n\nRemove all tuples that are disallowed by the disallow function. Input to the function is a vector of parameter indexes. The output to the function is whether they are disallowed, as a boolean. This reduces the size of total tuples in the coverage matrix. It doesn't move them to covered tuples. It deletes them.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.total_combinations-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.total_combinations","text":"total_combinations(arity, n_way)\n\nGiven an array of the number of values for each parameter and the level of coverage, return the number of n-tuples required for complete coverage.\n\n\n\n\n\n","category":"method"},{"location":"reference/#UnitTestDesign.tuples_in_trials-Tuple{Any,Any}","page":"Reference","title":"UnitTestDesign.tuples_in_trials","text":"tuples_in_trials(trials, n_way)\n\nFind the number of distinct tuples in a set of trials. This uses a different method to count and store those tuples, as a check on other methods. It returns a dictionary where each key is the index of non-zero parameters and the value is the set of all ways those values appear.\n\n\n\n\n\n","category":"method"},{"location":"man/usage/#Usage-in-context","page":"Usage","title":"Usage in context","text":"","category":"section"},{"location":"man/usage/#Test-generation","page":"Usage","title":"Test generation","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"We use test case generation tools, like this library, when tests take too long to run. It can be worthwhile to generate smaller test suites by running slower test case generators (such as GND). The development process is:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"Generate test cases.\nSave test cases to a file, a testing artifact, or copied to the unit test as data.\nLoad the test cases for unit testing.","category":"page"},{"location":"man/usage/#Partition-testing","page":"Usage","title":"Partition testing","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"We've pretended, so far, that every function takes parameters that are selected from discrete, finite choices. Functions arguments can be floating-point values, integers from infinite sets, vectors of values, or trees of trees of values. Partition testing whittles down the nearly-infinite possible values into subsets which are likely to find the same faults in the function-under-test.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"If a function integrates a value from a to b, then we could partition the possible a and b test values into those that are both negative, both positive, one negative and one positive. We could make a separate case for when they are very nearly equal or equal. That would make five partitions for these two variables. For each of those five partitions, we guess that it would be enough to choose some example value for testing.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"test_set = all_pairs(\n    [:neg, :pos, :split, :near, :far], [0.1, 0.01, 0.001], [:RungeKutta, :Midpoint]\n    )\nab = Dict(:neg => (-3, -2), :pos => (2, 3), :split => (-2, 3),\n    :near => (4.999, 5), :far => (0, 1e7)\n)\nfor test_case in test_set\n    a, b = ab[test_case[1]]\n    result = custom_integrate(a, b, test_case[2:end]...)\n    @test result == compare_with_symbolic_integration(a, b)\nend","category":"page"},{"location":"man/usage/#Random-testing","page":"Usage","title":"Random testing","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"Random testing side-steps the work, and fallibility, of partition testing by choosing input values randomly from their domain. If a can be any number between 0 and infinity, then let a random number generator pick it.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"Random testing isn't blind to understanding what can go wrong in a function. It's no reason to forget to test edge cases. There is a procedure for constructing random tests that are biased towards finding edge cases.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"Identify the whole domain of each parameter and the set of parameters.\nAssign weights to bias selection on that domain.\nSample from the parameters, given the weights.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"For instance, if a parameter were a string, you wouldn't generate from all random strings. You'd sample first for a string length, with assurance that lengths 0 and 1 are included. Then you'd draw values in the string.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"The test case generation in this library can help bias random testing. For instance, you could assign one partition to edge cases near a=0, one partition to general cases for 0.1 < a < 1000, and one partition to high cases, 1e7 < a < Inf. Let the test case generator say which of the low, mid, or high cases to choose, and then randomly choose values within each test case.","category":"page"},{"location":"man/usage/#Test-selection","page":"Usage","title":"Test selection","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"We can generate a lot of tests. How do we know they are a good set of tests? I'd like to make lots of tests and then keep only those that are sufficiently different from the others that they would find different failures. I don't see any of these tools currently in Julia.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"One measure is line coverage of code. We use all-pairs in order to to generate tests that cover every path through the code. An if-then in the code makes its decision based on variables which, in some way, depend on input parameters. If we include every combination of parameters, we will tend to cover more of the decisions of the if-thens.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"A better measure is mutation analysis. This technique introduces errors into the code, on the fly. Then it runs unit tests against that code in order to ask which unit tests find the same failures. If two unit tests consistently find the same failures, then delete one of them and keep the other.","category":"page"},{"location":"#UnitTestDesign","page":"Home","title":"UnitTestDesign","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"A Julia package to generate test cases for unit tests. This provides all-pairs and higher-order algorithms.","category":"page"},{"location":"#Install","page":"Home","title":"Install","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"pkg> add https://github.com/adolgert/UnitTestDesign.jl","category":"page"},{"location":"#Description","page":"Home","title":"Description","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"If we have a function-under-test that takes four arguments, each of which can have three possible values, then there are 81 possible combinations of inputs. The all_pairs function selects 10 inputs that contain every pair parameter values at least once.","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using UnitTestDesign\njulia> test_cases = all_pairs([1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim])\n10-element Array{Array{Any,1},1}:\n [1, \"low\", 1.0, :greedy]\n [1, \"mid\", 3.7, :relax]\n [1, \"high\", 4.9, :optim]\n [2, \"low\", 3.7, :optim]\n [2, \"mid\", 1.0, :greedy]\n [2, \"high\", 1.0, :relax]\n [3, \"low\", 4.9, :relax]\n [3, \"mid\", 1.0, :optim]\n [3, \"high\", 3.7, :greedy]\n [2, \"mid\", 4.9, :greedy]","category":"page"},{"location":"","page":"Home","title":"Home","text":"Each item in this array is a set of parameters for unit testing the function. This test set is an example of all-pairs because we can pick any two parameters (second and fourth), pick any of the values for those parameters (\"mid\" and :relax), and find them in one of the test cases (the 2nd one).","category":"page"},{"location":"","page":"Home","title":"Home","text":"Use a test set for unit testing:","category":"page"},{"location":"","page":"Home","title":"Home","text":"test_set = all_pairs(\n    [1, 2, 3], [\"low\", \"mid\" ,\"high\"], [1.0, 3.7, 4.9], [:greedy, :relax, :optim]\n    )\nfor test_case in test_set\n    test_result = function_under_test(test_case...)\n    @test test_result == known_result(test_case)\nend","category":"page"},{"location":"","page":"Home","title":"Home","text":"This package doesn't help write the code that knows what the correct test result should be.","category":"page"},{"location":"man/greedy/#Greedy-Fractional-Factorial-Parameter-Generators","page":"Greedy Fractional Factorial Parameter Generators","title":"Greedy Fractional Factorial Parameter Generators","text":"","category":"section"},{"location":"man/greedy/","page":"Greedy Fractional Factorial Parameter Generators","title":"Greedy Fractional Factorial Parameter Generators","text":"This creates a fractional factorial test design for the parameters. Out of all possible combinations of parameters, this chooses a subset that contains every possible pair of inputs, or every possible triple, or even every possible value of each parameter.","category":"page"},{"location":"man/greedy/","page":"Greedy Fractional Factorial Parameter Generators","title":"Greedy Fractional Factorial Parameter Generators","text":"The method constructs a list of every tuple that must be tested. Then it uses weighted random number generation to construct a complete set of parameters that includes as many of those tuples as possible.","category":"page"}]
}
