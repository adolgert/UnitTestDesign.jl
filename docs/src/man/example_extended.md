# Extended Example

Combinatorial interaction testing is most useful when testing a complicated function, so let's look at testing code with more branches.

## Code Under Test

This code takes any pair of integers, ``(i, j)`` and returns a single integer, ``z`` that will be unique for every unique ``(i,j)``. It's called a Hilbert index, and it's used to provide an ad-hoc clustering of values in a grid. What we see in this code is lots of if-then decisions and some bitshifting. Writing this, I was worried about type stability, interactions among signed and unsigned integers, and errors due to integer size differences.

```julia
struct Simple2D{T}
end

function encode_hilbert_zero(::Simple2D{T}, X::Vector{A})::T where {A, T}
    x = X[1]
    y = X[2]
    z = zero(T)
    if x == zero(A) && y == zero(A)
        return z
    end
    rmin = convert(Int, floor(log2(max(x, y))) + 1)
    w = one(A) << (rmin - 1)
    while rmin > 0
        z <<= 2
        if rmin&1 == 1  # odd
            if x < w
                if y >= w
                    # 1
                    x, y = (y - w, x)
                    z += one(T)
                end  # else x, y remain the same.
            else
                if y < w
                    x, y = ((w<<1) - x - one(w), w - y - one(w))
                    # 3
                    z += T(3)
                else
                    x, y = (y - w, x - w)
                    z += T(2)
                    # 2
                end
            end
        else  # even
            if x < w
                if y >= w
                    # Quadrant 3
                    x, y = (w - x - one(w), (w << 1) - y - one(w))
                    z += T(3)
                end  # else do nothing for quadrant 0.
            else
                if y < w
                    # 1
                    x, y = (y, x-w)
                    z += one(T)
                else
                    # 2
                    x, y = (y-w, x-w)
                    z += T(2)
                end
            end
        end
        rmin -= 1
        w >>= 1
    end
    z
end

# Decoding does the opposite of encoding, so it turns a single z into an (i,j).
function decode_hilbert_zero!(::Simple2D{T}, X::Vector{A}, z::T) where {A,T}
    r = z & T(3)
    x, y = [(zero(A), zero(A)), (zero(A), one(A)), (one(A), one(A)), (one(A), zero(A))][r + 1]
    z >>= 2
    rmin = 2
    w = one(A) << 1
    while z > zero(T)
        r = z & T(3)
        parity = 2 - rmin&1
        if rmin & 1 != 0
            # Nothing to do for quadrant 0.
            if r == 1
                x, y = (y, x + w)
            elseif r == 2
                x, y = (y + w, x + w)
            elseif r == 3
                x, y = ((w << 1) - x - one(A), w - y - one(A))
            end
        else
            if r == 1
                x, y = (y + w, x)
            elseif r == 2
                x, y = (y + w, x + w)
            elseif r == 3
                x, y = (w - x - one(A), (w << 1) - y - one(A))
            end
        end
        z >>= 2
        rmin += 1
        w <<= 1
    end
    X[1] = x
    X[2] = y
end

# These are the same functions with 1-offsets, for use in Julia array indexing.
function encode_hilbert(gg::Simple2D{T}, X::Vector{A}) where {A, T}
    encode_hilbert_zero(gg, X .- one(A)) + one(T)
end


function decode_hilbert!(gg::Simple2D{T}, X::Vector{A}, h::T) where {A,T}
    decode_hilbert_zero!(gg, X, h - one(T))
    X .+= one(A)
end
```

## Combinatorial Test of the Code

The code above is a just two functions, but there is lots of opportunity for problems. Because Julia let's us create a single function to work for multiple types, we effectively have multiple functions to test. How many cases are there, in total?

* The ``(i,j)`` can be Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128 (10).
* The same options are possible for the ``z`` value, the Hilbert index (10).
* This function could be called in a 0-based or 1-based way (2).
* The ``(i,j)`` could range over different extents. This is a semi-infinite set, but let's choose powers of two, so 4, 8, 16, 32, 64, and trust past that (5).
* This test allows the input vector to be too-large. That's a feature of some Hilbert implementations, and means we test for 2D, 3D, 4D (3).

In all, we could have 3000 test runs. Of those 3000, the `all_pairs` function chooses 100 tests that contain every possible pair of arguments. In each test run, the code will do self-consistency checks. It will check that consecutive ``z`` values produce contiguous ``(i,j)`` values. It will test that decoding is the opposite of encoding. These tests may sound trivial, but four out of the six major papers on Hilbert indices contained code that failed these tests. All were later fixed after publication.

Combinatorial interaction testing of this function caught one major problem. The use of types wasn't consistent within the functions. While there are user-chosen types for input and output, all bitshifting should use simple integers. This testing also reassured the author that unsigned and signed integers would work together for this particular use of bitshifting functions.

```julia
using UnitTestDesign
using Random
using Test
rng = Random.MersenneTwister(9790323)
for retrial in 1:5
    AxisTypes = shuffle(rng, [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128])
    IndexTypes = shuffle(rng, [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128])
    Count= shuffle(rng, [0, 1])
    Dims = shuffle(rng, [2, 3, 4])
    Bits = shuffle(rng, [2, 3, 4, 5])
    test_set = all_pairs(
        AxisTypes, IndexTypes, Count, Dims, Bits;
    )
    for (A, I, C, D, B) in test_set
        gg = Simple2D{I}()
        if B * D > log2(typemax(I))
            continue
        end
        # Add this because these values aren't in Hilbert order because
        # It's an asymmetrical space.
        if B * D > log2(typemax(A))
            continue
        end
        last = (one(I) << (B * D)) - one(I) + I(C)
        mid = one(I) << (B * D - 1)
        few = 5
        X = zeros(A, D)
        hlarr = vcat(C:min(mid, few), max(mid + 1, last - few):last)
        for hl in hlarr
            hli = I(hl)
            if C == 0
                decode_hilbert_zero!(gg, X, hli)
                hl2 = encode_hilbert_zero(gg, X)
                if hl2 != hli
                    @show A, I, C, D, B, X
                    @test hl2 == hli
                end
                @test typeof(hl2) == typeof(hli)
            else
                decode_hilbert!(gg, X, hli)
                hl3 = encode_hilbert(gg, X)
                @test hl3 == hli
                @test typeof(hl3) == typeof(hli)
            end
        end
    end
end
```

One technique you might note above is that the code generates five versions of the test suite. It does this because the combinatorial tests are generated with a deterministic algorithm, so one way to increase test coverage is to shuffle test inputs and regenerate the test suite.
