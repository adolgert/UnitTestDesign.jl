# Needed: using Z3

# --- Runtime Helper Functions (defined in your module) ---

# Helper to translate a comparison on a value to a Z3 constraint on its index
function translate_value_comparison_to_index_constraint(
    ctx::Z3.Context,
    z3_index_var::Z3.ExprAllocated, # Z3 variable for the index of this list
    actual_list::Union{Tuple, AbstractVector}, # The concrete list of values
    comparison_op::Symbol, # e.g., :<, :(==)
    value_operand # The literal value in the comparison (e.g., 7 in b == 7)
)::Z3.ExprAllocated
    allowed_indices = Int[]
    for (i, list_val) in enumerate(actual_list)
        match = false
        if comparison_op == :(<) match = list_val < value_operand
        elseif comparison_op == :(>) match = list_val > value_operand
        elseif comparison_op == :(<=) match = list_val <= value_operand
        elseif comparison_op == :(>=) match = list_val >= value_operand
        elseif comparison_op == :(==) match = list_val == value_operand
        elseif comparison_op == :(!=) match = list_val != value_operand
        else error("Unsupported comparison operator: $comparison_op")
        end
        if match
            push!(allowed_indices, i)
        end
    end

    if isempty(allowed_indices)
        return Z3.mk_false(ctx)
    elseif length(allowed_indices) == length(actual_list)
         # Optimization: if all indices are allowed for this specific comparison,
         # it doesn't add a constraint from this particular sub-expression.
         # However, it's safer to list them all if this is part of a larger OR/AND.
         # For simplicity here, let's build the OR clause always unless it's truly unconstrained.
         # If it's truly unconstrained by *this* sub-expression, it should effectively be true.
         # But if allowed_indices cover all, it means this part of condition is always true for any index.
         # The Z3.mk_or with all indices will simplify correctly.
    end
    
    or_clauses = [Z3.mk_eq(ctx, z3_index_var, Z3.mk_int(ctx, idx)) for idx in allowed_indices]
    if isempty(or_clauses) # Should be covered by mk_false, but as a fallback
        return Z3.mk_false(ctx)
    end
    return Z3.mk_or(ctx, or_clauses) # mk_or simplifies if only one clause
end

# Recursive function to translate user's logic AST to Z3 expression on indices
function user_logic_ast_to_z3(
    ctx::Z3.Context,
    expr_ast, # The AST node of the user's logic (e.g., from QuoteNode)
    arg_name_to_info::Dict{Symbol, NamedTuple{(:z3_idx_var, :list_idx), Tuple{Z3.ExprAllocated, Int}}},
    actual_input_lists::Tuple
)::Z3.ExprAllocated
    if expr_ast isa Expr
        head = expr_ast.head
        args = expr_ast.args

        if head == :call
            op = args[1]
            # Expecting: variable_name < literal, variable_name == literal, etc.
            if length(args) == 3 && op in [:(<), :(>), :(<=), :(>=), :(==), :(!=)]
                var_name_node = args[2]
                literal_value_node = args[3]

                if !(var_name_node isa Symbol && haskey(arg_name_to_info, var_name_node))
                    error("Expected an argument variable (e.g., a, b) as the left operand of a comparison. Got: $var_name_node")
                end
                # Ensure literal_value_node is actually a literal, not another variable for this simplified example
                if literal_value_node isa Symbol && haskey(arg_name_to_info, literal_value_node)
                    error("Comparisons between two argument variables not directly supported in this simplified example. Compare variables to literals. Got: $literal_value_node")
                end
                # The literal_value_node is the actual value, not an AST node here because it's from the user's direct code.
                literal_value = literal_value_node


                var_info = arg_name_to_info[var_name_node]
                current_list = actual_input_lists[var_info.list_idx]

                return translate_value_comparison_to_index_constraint(
                    ctx, var_info.z3_idx_var, current_list, op, literal_value
                )
            else
                error("Unsupported function call in disallow logic: $expr_ast. Only binary comparisons (e.g., arg < literal) are supported.")
            end
        elseif head == :(&&)
            if isempty(args) return Z3.mk_true(ctx) end
            return Z3.mk_and(ctx, [user_logic_ast_to_z3(ctx, arg, arg_name_to_info, actual_input_lists) for arg in args])
        elseif head == :(||)
            if isempty(args) return Z3.mk_false(ctx) end
            return Z3.mk_or(ctx, [user_logic_ast_to_z3(ctx, arg, arg_name_to_info, actual_input_lists) for arg in args])
        elseif head == :block # Result of a block is its last expression
            if isempty(args) return Z3.mk_true(ctx) end # Empty block is true
            # Process assignments to set up arg_name_to_info if that's the convention
            # For now, assume last expression is the condition.
            return user_logic_ast_to_z3(ctx, args[end], arg_name_to_info, actual_input_lists)
        # Add :if for if-then-else later if needed: Z3.mk_ite
        else
            error("Unsupported expression type in disallow logic: $head in $expr_ast")
        end
    elseif expr_ast isa Bool # e.g., the block is just `true` or `false`
        return expr_ast ? Z3.mk_true(ctx) : Z3.mk_false(ctx)
    elseif expr_ast isa Symbol && haskey(arg_name_to_info, expr_ast) # e.g. `if c ...` where c is boolean
        # This means `c == true`
        var_info = arg_name_to_info[expr_ast]
        current_list = actual_input_lists[var_info.list_idx]
        # Check if the list is boolean. If not, error.
        if !(eltype(current_list) <: Bool)
            error("Direct use of variable '$expr_ast' as a condition is only allowed if its list contains Booleans.")
        end
        return translate_value_comparison_to_index_constraint(
            ctx, var_info.z3_idx_var, current_list, :(==), true
        )
    else
        error("Unsupported AST node in disallow logic: $expr_ast of type $(typeof(expr_ast))")
    end
end


# --- The Macro ---
macro disallow_solver(input_lists_expr, disallow_block_expr)
    # input_lists_expr is like :(((1,2,3), (7,8), (true,false)))
    # disallow_block_expr is like :(begin ... end)

    # We need to parse argument names from the disallow_block_expr.
    # Convention: first line is `arg1, arg2, ... = __SOME_DUMMY__`
    user_arg_names = Symbol[]
    actual_logic_expr = disallow_block_expr # Default if no destructuring

    if Meta.isexpr(disallow_block_expr, :block) && !isempty(disallow_block_expr.args)
        first_stmt = disallow_block_expr.args[1]
        if Meta.isexpr(first_stmt, :(=)) && Meta.isexpr(first_stmt.args[1], :tuple)
            user_arg_names = [arg for arg in first_stmt.args[1].args if arg isa Symbol]
            if length(disallow_block_expr.args) > 1
                actual_logic_expr = Expr(:block, disallow_block_expr.args[2:end]...)
            else # Only assignment, effectively no condition
                actual_logic_expr = true # No specific disallow condition
            end
        else # No destructuring assignment, block is the logic
            actual_logic_expr = disallow_block_expr
        end
    end

    # Quote the actual logic part to pass its AST to the runtime function
    quoted_actual_logic_expr = QuoteNode(actual_logic_expr)

    # The macro generates an expression. When this expression is evaluated,
    # it will execute the code inside the `let` block.
    return esc(quote
        let evaluated_input_lists = $input_lists_expr # Evaluate the user's list expression

            if !($user_arg_names isa Vector{Symbol}) # Should be caught by macro logic above
                 error("Internal error: user_arg_names not parsed correctly.")
            end

            num_actual_lists = length(evaluated_input_lists)
            if !isempty($user_arg_names) && length($user_arg_names) != num_actual_lists
                error("Number of user-defined argument names ($($user_arg_names)) does not match number of input lists ($num_actual_lists).")
            end
            
            # Use provided arg names or generate defaults if none were parsed
            arg_symbols_for_processing = if !isempty($user_arg_names)
                $user_arg_names
            else
                # If no args parsed, and logic directly uses _1, _2 (not handled yet)
                # This branch needs more robust handling if user_arg_names is empty.
                # For now, assume if user_arg_names is empty, the logic is simple like `true` or uses no args.
                # Or, we could enforce that user_arg_names *must* be provided via the destructuring.
                if $quoted_actual_logic_expr != true && $quoted_actual_logic_expr != false # if not a simple boolean
                    # A simple heuristic: if the logic is not just true/false, and no args were parsed,
                    # we might need a default way to refer to lists, or error.
                    # For now, let's error if complex logic is provided without arg names.
                    # A more advanced macro could try to find all symbols in quoted_actual_logic_expr
                    # and assume they are the arguments in order.
                    error("Disallow logic provided without explicit argument destructuring (e.g., a,b,c = _). Please define argument names.")
                end
                Symbol[] # No specific arg names to map
            end


            ctx = Z3.Context()
            
            # Map from user's argument symbol to its Z3 index variable and list position
            # e.g. :a => (z3_idx_var_for_a, 1st_list_idx)
            arg_map = Dict{Symbol, NamedTuple{(:z3_idx_var, :list_idx), Tuple{Z3.ExprAllocated, Int}}}()
            
            symbolic_indices_vars = Z3.ExprVector(ctx) # Vector of Z3 index variables
            index_range_constraints_list = Z3.ExprAllocated[]

            for (i, arg_sym) in enumerate(arg_symbols_for_processing)
                list_len = length(evaluated_input_lists[i])
                if list_len == 0
                    # If a list is empty, no combination is possible involving it.
                    # The disallow condition effectively becomes "always true" (disallow everything)
                    # because no valid index exists.
                    # Or, full_factorial should handle empty lists by producing no iterations.
                    # For Z3, an index for an empty list is unsatisfiable.
                    push!(index_range_constraints_list, Z3.mk_false(ctx)) # No valid index
                    # We still need a placeholder z3_idx_var for arg_map structure, though it won't be used.
                    # This case needs careful thought. If any list is empty, the product is empty.
                    # Let's assume full_factorial handles this. If it proceeds, an empty list constraint
                    # will make the whole thing UNSAT for the disallow (meaning allowed, but no items).
                    # Or SAT for disallow (meaning disallowed).
                    # If list_len is 0, 1 <= idx <= 0 is false.
                end

                idx_var_name = string(arg_sym, "_idx")
                z3_idx_var = Z3.mk_fresh_int_const(ctx, idx_var_name)
                Z3.push!(symbolic_indices_vars, z3_idx_var)
                
                arg_map[arg_sym] = (z3_idx_var = z3_idx_var, list_idx = i)

                # Add constraint: 1 <= z3_idx_var <= length(list)
                if list_len > 0
                    push!(index_range_constraints_list, Z3.mk_le(ctx, Z3.mk_int(ctx, 1), z3_idx_var))
                    push!(index_range_constraints_list, Z3.mk_le(ctx, z3_idx_var, Z3.mk_int(ctx, list_len)))
                else # list_len == 0
                     # This makes any specific index choice impossible, so this path should be UNSAT
                     # for the positive condition of picking an index.
                     # If this is part of the disallow condition, it means this part of disallow is always true.
                    push!(index_range_constraints_list, Z3.mk_false(ctx)) # No valid index exists
                end

            end

            # Translate the user's actual logic AST using the runtime helper
            user_disallow_condition_z3 = Main.user_logic_ast_to_z3( # Assuming helpers are in Main
                ctx,
                $quoted_actual_logic_expr, # The AST of the user's logic block
                arg_map,
                evaluated_input_lists
            )

            # Combine user's condition with index range constraints
            all_constraints = [user_disallow_condition_z3; index_range_constraints_list...]
            final_combined_z3_expr = Z3.mk_and(ctx, all_constraints)

            # Return the setup needed by full_factorial
            (
                z3_context=ctx,
                symbolic_index_variables=symbolic_indices_vars, # Z3.ExprVector
                combined_disallow_expr=final_combined_z3_expr,
                # Pass evaluated_input_lists too, as full_factorial needs them for yielding values
                original_input_lists=evaluated_input_lists
            )
        end # end let
    end) # end esc(quote(...))
end


# --- Example full_factorial using the Z3 setup ---
function full_factorial_with_z3(z3_setup)
    ctx = z3_setup.z3_context
    symbolic_indices = z3_setup.symbolic_index_variables
    disallow_expr_template = z3_setup.combined_disallow_expr
    input_lists = z3_setup.original_input_lists

    # If any list is empty, the Cartesian product is empty.
    if any(isempty, input_lists)
        println("One or more input lists are empty. No combinations to generate.")
        return []
    end

    solver = Z3.Solver(ctx)
    Z3.add(solver, disallow_expr_template) # Add the main symbolic disallow rule

    results = []
    
    # Generate iterators for indices: (1:length(l) for l in input_lists)
    index_iterators = Iterators.product((1:length(l) for l in input_lists)...)

    for concrete_idx_tuple in index_iterators
        Z3.push!(solver) # Create a new scope for this specific combination

        # Assert concrete values for symbolic indices for this iteration
        for (i, concrete_idx) in enumerate(concrete_idx_tuple)
            Z3.add(solver, Z3.mk_eq(ctx, symbolic_indices[i], Z3.mk_int(ctx, concrete_idx)))
        end

        check_result = Z3.check(solver)

        if check_result == Z3.SATISFIABLE
            # This means the `disallow_expr_template` (which includes user logic + ranges)
            # is TRUE for this combination of indices. So, it's disallowed.
            # println("Disallowed by Z3: indices $concrete_idx_tuple")
        elseif check_result == Z3.UNSATISFIABLE
            # This means the `disallow_expr_template` is FALSE. So, it's allowed.
            actual_values = Tuple(input_lists[i][concrete_idx_tuple[i]] for i in 1:length(input_lists))
            # println("Allowed by Z3: $actual_values (indices $concrete_idx_tuple)")
            push!(results, actual_values)
        else
            println("Z3 returned UNKNOWN for indices $concrete_idx_tuple")
        end

        Z3.pop!(solver) # Restore solver state
    end
    return results
end

# --- Example Usage ---
# To make this runnable, Z3.jl needs to be installed and imported.
# The helper functions `user_logic_ast_to_z3` and `translate_value_comparison_to_index_constraint`
# are assumed to be in the same scope (e.g., Main, or your module).

# z3_params = @disallow_solver(
#     ((1, 2, 3), (7, 8), (true, false)),
#     begin
#         a, b, c = _ # Dummy for destructuring
#         (b == 7 && c == false) || a > 2
#     end
# )
#
# allowed_combinations = full_factorial_with_z3(z3_params)
# println("\nFinal Allowed Combinations:")
# for combo in allowed_combinations
#     println(combo)
# end
#
# Expected output for the above:
# (1, 7, true)
# (1, 8, true)
# (1, 8, false)
# (2, 7, true)
# (2, 8, true)
# (2, 8, false)
# (3, 7, true)   -- a > 2 is true
# (3, 8, true)   -- a > 2 is true
# (3, 8, false)  -- a > 2 is true
# (3,7,false) is disallowed by b==7&&c==false, but allowed because a>2.
# (1,7,false) -> b==7 && c==false is TRUE. a>2 is FALSE. So (TRUE || FALSE) is TRUE. Disallowed.
# (2,7,false) -> b==7 && c==false is TRUE. a>2 is FALSE. So (TRUE || FALSE) is TRUE. Disallowed.
#
# Let's trace (1,7,false) which means indices (1,1,2)
# a=1, b=7, c=false
# (b == 7 && c == false) -> (true && true) -> true
# a > 2 -> 1 > 2 -> false
# (true || false) -> true. So, (1,7,false) should be DISALLOWED.
#
# Let's trace (3,7,false) which means indices (3,1,2)
# a=3, b=7, c=false
# (b == 7 && c == false) -> (true && true) -> true
# a > 2 -> 3 > 2 -> true
# (true || true) -> true. So, (3,7,false) should be DISALLOWED.

# My manual trace for the example `(b == 7 && c == false) || a > 2`
# List values: L1=(1,2,3), L2=(7,8), L3=(true,false)
#
# Combo (a,b,c) | b==7 | c==false | (b==7 && c==false) | a>2  | OR result | Action
# --------------|------|----------|--------------------|------|-----------|----------
# (1,7,true)    | T    | F        | F                  | F    | F         | ALLOW
# (1,7,false)   | T    | T        | T                  | F    | T         | DISALLOW
# (1,8,true)    | F    | F        | F                  | F    | F         | ALLOW
# (1,8,false)   | F    | T        | F                  | F    | F         | ALLOW
# (2,7,true)    | T    | F        | F                  | F    | F         | ALLOW
# (2,7,false)   | T    | T        | T                  | F    | T         | DISALLOW
# (2,8,true)    | F    | F        | F                  | F    | F         | ALLOW
# (2,8,false)   | F    | T        | F                  | F    | F         | ALLOW
# (3,7,true)    | T    | F        | F                  | T    | T         | DISALLOW
# (3,7,false)   | T    | T        | T                  | T    | T         | DISALLOW
# (3,8,true)    | F    | F        | F                  | T    | T         | DISALLOW
# (3,8,false)   | F    | T        | F                  | T    | T         | DISALLOW
#
# Allowed: (1,7,true), (1,8,true), (1,8,false), (2,7,true), (2,8,true), (2,8,false)
# This matches the kind of filtering one would expect.