# Implement a new process

```@setup usepkg
using PlantSimEngine
using PlantBiophysics
using PlantMeteo
PlantSimEngine.@gen_process_methods growth
```

## Introduction

`PlantSimEngine.jl` was designed to make the implementation of new processes and models easy and fast. Let's learn about how to implement your own process with a simple example: implementing a growth model.

## Implement a new process

To implement a new process, we need to define the generic methods associated to it that helps run its simulation for:

- one or several time-steps
- one or several objects
- an MTG from MultiScaleTreeGraph

...and all the above with a mutating function and a non-mutating one.

This is a lot of work! But fortunately PlantBiophysics provides a macro to generate all of the above: [`@gen_process_methods`](@ref).

This macro takes only one argument: the name of the non-mutating function.

So for example all the photosynthesis methods in the [PlantBiophysics.jl](https://github.com/VEZY/PlantBiophysics.jl) package are created using just this tiny line of code:

```julia
@gen_process_methods photosynthesis
```

So for example if we want to simulate the growth of a plant, we could add a new process called `growth`. To create the generic functions to simulate the `growth` we would do:

```julia
@gen_process_methods growth
```

And that's it! Note that the function guides you in the steps you can make after creating a process. Let's break it up here.

So what you just did is to create a new process called `growth`. By doing so, you created three new functions:

- `growth!`: the mutating function
- `growth`: the non-mutating function
- `growth!_`: the function that actually make the computation. You'll have to implement methods for each model you need, else it will not work.

Now users can call `growth!` and `growth` on any number of time steps or objects, even on MTGs, and PlantSimEngine will handle everything.

Creating the process also defined a default abstract type for the process that is used as a supertype for the models types. This abstract type is always named using the process name in title case (using `titlecase()`), prefixed with `Abstract` and suffixed with `Model`. So in our case our process abstract type is named `AbstractGrowthModel`.

!!! note
    If you don't understand what a supertype is, no worries, you'll understand in the examples below

## Implement a new model for the process

To better understand how models are implemented, you can read the detailed instructions from the [previous section](@ref model_implementation_page). But for the sake of completeness, we'll implement a growth model here.

This growth model uses the assimilation computed using the coupled energy balance process from `PlantBiophysics.jl`. Then it removes the maintenance respiration and the growth respiration from that source of carbon, and increments the leaf biomass by the remaining carbon offer.

Let's implement this model below:

```@example usepkg
# Let's import our package:
using PlantSimEngine
# PlantMeteo for using the meteorology-related functions:
using PlantMeteo
# And PlantBiophysics because we want our model to compute growth based on 
# photosynthesis computed from `energy_balance!_()`:
using PlantBiophysics

# Make the struct to hold the parameters, with its documentation:
"""
    DummyGrowth(Rm_factor, Rg_cost)
    DummyGrowth(;Rm_factor = 0.5, Rg_cost = 1.2)

Computes the leaf biomass growth of a plant.

# Arguments

- `Rm_factor`: the fraction of assimilation that goes into maintenance respiration
- `Rg_cost`: the cost of growth maintenance, in gram of carbon biomass per gram of assimilate
"""
struct DummyGrowth{T} <: AbstractGrowthModel
    Rm_factor::T
    Rg_cost::T
end

# Note that DummyGrowth is a subtype of AbstractGrowthModel, this is important

# Instantiate the struct with default values + kwargs:
function DummyGrowth(;Rm_factor = 0.5, Rg_cost = 1.2)
    DummyGrowth(promote(Rm_factor,Rg_cost)...)
end

# Define inputs:
function PlantSimEngine.inputs_(::DummyGrowth)
    (A=-999.99,)
end

# Define outputs:
function PlantSimEngine.outputs_(::DummyGrowth)
    (Rm=-999.99, Rg=-999.99, leaf_allocation=-999.99, leaf_biomass=0.0)
end

# Tells Julia what is the type of elements:
Base.eltype(x::DummyGrowth{T}) where {T} = T

# Implement the growth model:
function growth!_(::DummyGrowth, models, status, meteo, constants=Constants())

    # Compute the energy balance of the plant, coupled to the photosynthesis model:
    PlantBiophysics.energy_balance!_(models.energy_balance, models, status, meteo)
    # Here we expect the assimilation of the plant, which is the source for Carbon

    # The maintenance respiration is simply a factor of the assimilation:
    status.Rm = status.A * models.growth.Rm_factor

    # Let's say that all carbon is allocated to the leaves:
    status.leaf_allocation = status.A - status.Rm

    # And that this carbon is allocated with a cost (growth respiration Rg):
    status.Rg = 1 - (status.leaf_allocation / models.growth.Rg_cost)

    status.leaf_biomass = status.leaf_biomass + status.leaf_allocation - status.Rg
end
```

Now we can make a simulation as usual:

```@example usepkg
meteo = Atmosphere(T = 22.0, Wind = 0.8333, P = 101.325, Rh = 0.4490995)

leaf = ModelList(
        # Processes and models from PlantBiophysics:
        energy_balance = Monteith(),
        photosynthesis = Fvcb(),
        stomatal_conductance = Medlyn(0.03, 12.0),
        # Our process and associated model:
        growth = DummyGrowth(),
        status = (Rₛ = 13.747, sky_fraction = 1.0, PPFD = 1500.0, d = 0.03)
    )

growth!(leaf,meteo)

leaf[:leaf_biomass] # biomass in gC
```

We can also start the simulation later when the plant already has some biomass by initializing the `leaf_biomass`:

```@example usepkg
meteo = Atmosphere(T = 22.0, Wind = 0.8333, P = 101.325, Rh = 0.4490995)

leaf = ModelList(
        energy_balance = Monteith(),
        photosynthesis = Fvcb(),
        stomatal_conductance = Medlyn(0.03, 12.0),
        growth = DummyGrowth(),
        status = (Rₛ = 13.747, sky_fraction = 1.0, PPFD = 1500.0, d = 0.03, leaf_biomass = 2400.0)
    )

growth!(leaf,meteo)

leaf[:leaf_biomass] # biomass in gC
```
