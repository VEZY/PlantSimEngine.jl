
"""
    RMSE(obs,sim)

Returns the Root Mean Squared Error between observations `obs` and simulations `sim`.

The closer to 0 the better.

# Examples

```@example
using PlantSimEngine

obs = [1.0, 2.0, 3.0]
sim = [1.1, 2.1, 3.1]

RMSE(obs, sim)
```
"""
function RMSE(obs, sim)
    return sqrt(sum((obs .- sim) .^ 2) / length(obs))
end

"""
    NRMSE(obs,sim)

Returns the Normalized Root Mean Squared Error between observations `obs` and simulations `sim`.
Normalization is performed using division by observations range (max-min).

# Examples

```@example
using PlantSimEngine

obs = [1.0, 2.0, 3.0]
sim = [1.1, 2.1, 3.1]

NRMSE(obs, sim)
```
"""
function NRMSE(obs, sim)
    return sqrt(sum((obs .- sim) .^ 2) / length(obs)) / (findmax(obs)[1] - findmin(obs)[1])
end

"""
    EF(obs,sim)

Returns the Efficiency Factor between observations `obs` and simulations `sim` using NSE (Nash-Sutcliffe efficiency) model.
More information can be found at https://en.wikipedia.org/wiki/Nash%E2%80%93Sutcliffe_model_efficiency_coefficient.

The closer to 1 the better.

# Examples

```@example
using PlantSimEngine

obs = [1.0, 2.0, 3.0]
sim = [1.1, 2.1, 3.1]

EF(obs, sim)
```
"""
function EF(obs, sim)
    SSres = sum((obs - sim) .^ 2)
    SStot = sum((obs .- Statistics.mean(obs)) .^ 2)
    return 1 - SSres / SStot
end

"""
    dr(obs,sim)

Returns the Willmott’s refined index of agreement dᵣ.
Willmot et al. 2011. A refined index of model performance. https://rmets.onlinelibrary.wiley.com/doi/10.1002/joc.2419

The closer to 1 the better.

# Examples

```@example
using PlantSimEngine

obs = [1.0, 2.0, 3.0]
sim = [1.1, 2.1, 3.1]

dr(obs, sim)
```
"""
function dr(obs, sim)
    a = sum(abs.(obs .- sim))
    b = 2 * sum(abs.(obs .- Statistics.mean(obs)))
    return 0 + (1 - a / b) * (a <= b) + (b / a - 1) * (a > b)
end
