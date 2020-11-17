"""
This document looks at using probabilistic programming to specify tests.

- I could train test case generation using a set of recorded.
  function calls from actual use.
- I could choose weights for parameters and use random generation.
- I could specify disallowed sets of values as procedural code.
- I could construct an all-pairs or other algorithm as a specialized sampler.
"""

using Turing
using Random
using StatsPlots


### Start with running an example from Turing.jl
p_true = 0.5

# Iterate from having seen 0 observations to 100 observations.
Ns = 0:100

# Draw data from a Bernoulli distribution, i.e. draw heads or tails.
Random.seed!(12)
data = rand(Bernoulli(p_true), last(Ns))
@model function coinflip(y)
    # Our prior belief about the probability of heads in a coin.
    p ~ Beta(1, 1)

    # The number of observations.
    N = length(y)
    for n in 1:N
        # Heads or tails of a coin are drawn from a Bernoulli distribution.
        y[n] ~ Bernoulli(p)
    end
end

# Settings of the Hamiltonian Monte Carlo (HMC) sampler.
iterations = 1000
ϵ = 0.05
τ = 10

# Start sampling.
chain = sample(coinflip(data), HMC(ϵ, τ), iterations)

# Plot a summary of the sampling process for the parameter p, i.e. the probability of heads in a coin.
histogram(chain[:p])

### Now construct a sampler for a single parameter and see that it works for inference.
K = 5
@model function one_param_d(y)
    N = length(y)
    theta ~ Dirichlet(K, 1)
    for i in 1:N
        y[i] ~ Categorical(theta)
    end
end

data = rand(Categorical([0.1, 0.1, 0.1, 0.2, 0.5]), 500)
chain = sample(one_param_d(data), HMC(ϵ, τ), 1000)
describe(chain)

### Then move to two parameters to see if training data is in the right format.

@model function two_parameter(y)
    N = size(y, 2)
    theta ~ Dirichlet(2, 1)
    ulu ~ Dirichlet(3, 1)
    for i in 1:N
        y[1, i] ~ Categorical(theta)
        y[2, i] ~ Categorical(ulu)
    end
end
N = 1000
data = zeros(Int, 2, N)
data[1, :] = rand(Categorical([0.2, 0.8]), N)
data[2, :] = rand(Categorical([0.4, 0.2, 0.4]), N)
chain = sample(two_parameter(data), HMC(0.1, 5), 1000)

### We want to restrict parameters to allowed values.

@model function cross_depends(y)
    N = size(y, 2)
    theta ~ Dirichlet(2, 1)
    ulu ~ Dirichlet(3, 1)
    for i in 1:N
        y[1, i] ~ Categorical(theta)
        if y[1, i] == 1
            ulu[1:3] .= [1, 0, 0]
        end
        y[2, i] ~ Categorical(ulu)
    end
end

N = 1000
data = zeros(Int, 2, N)
data[1, :] = rand(Categorical([0.2, 0.8]), N)
data[2, :] = rand(Categorical([0.4, 0.2, 0.4]), N)
for i in 1:N
    if data[1, i] == 1
        data[2, i] = 1
    end
end
# chain = sample(cross_depends(data), HMC(0.1, 5), 1000)
chain = sample(cross_depends(data), PG(10), 1000)
chain = sample(cross_depends(data), NUTS(0.65), 1000)
