"""
    @gen_process_methods(process::String)

This macro generate all standard methods for processes:

- The base method that calls the actual algorithms implemented using the process name
    suffixed by `_`, *e.g.* `photosynthesis_`.
- The method applying the computation over several objects (*e.g.* all leaves of a plant)
in an Array
- The same method over a Dict(-alike) of objects
- The method that applies the computation over several meteo time steps (called Weather) and
possibly several objects
- A method for calling the process without any meteo (*e.g.* for fitting)
- A method to apply the above over MTG nodes (see details)
- A non-mutating version of the function (make a copy before the call, and return the copy)

The macro returns two functions: the mutating one and the non-mutating one.
For example `energy_balance()` and `energy_balance!()` for the energy balance. And of course
the function that implements the computation is assumed to be `energy_balance!_()`.

# Details

Note that the `extra` argument can be anything, and its use only depends on the algorithm used. 
This argument is not available for MTG computations, as it is used to pass the MTF Node that is
being processed, to *e.g.* get the node's children values.

# Examples

```julia
@gen_process_methods "dummy_process"
```
"""
macro gen_process_methods(f)

    non_mutating_f = process_field = Symbol(f)
    mutating_f = Symbol(string(f, "!"))
    f_ = Symbol(string(mutating_f, "_")) # The actual function implementing the process

    expr = quote

        function $(esc(f_))(mod_type, models, status, meteo=nothing, constants=nothing, extra=nothing)
            process_models = Dict(process => typeof(getfield(models, process)).name.wrapper for process in keys(models))
            error(
                "No model was found for this combination of processes:",
                "\nProcess simulation: ", $(String(non_mutating_f)),
                "\nModels: ", join(["$(i.first) => $(i.second)" for i in process_models], ", ", " and ")
            )
        end

        # Base method that calls the actual algorithms (NB: or calling it without meteo too):
        function $(esc(mutating_f))(object::ModelList{T,S}, meteo::M=nothing, constants=PlantMeteo.Constants(), extra=nothing) where {T,S<:Status,M<:Union{PlantMeteo.AbstractAtmosphere,Nothing}}
            $(esc(f_))(object.models.$(process_field), object.models, object.status, meteo, constants, extra)
            return nothing
        end

        # Method for a status with several TimeSteps but one meteo only (or no meteo):
        function $(esc(mutating_f))(object::ModelList{T,S}, meteo::M=nothing, constants=PlantMeteo.Constants(), extra=nothing) where {T,S,M<:Union{PlantMeteo.AbstractAtmosphere,Nothing}}

            for i in Tables.rows(status(object))
                $(esc(f_))(object.models.$(process_field), object.models, i, meteo, constants, extra)
            end

            return nothing
        end

        # Process method over several objects (e.g. all leaves of a plant) in an Array
        function $(esc(mutating_f))(object::O, meteo::PlantMeteo.AbstractAtmosphere, constants=PlantMeteo.Constants(), extra=nothing) where {O<:AbstractArray}
            for i in values(object)
                $(mutating_f)(i, meteo, constants, extra)
            end
            return nothing
        end

        # Process method over several objects (e.g. all leaves of a plant) in a kind of Dict.
        function $(esc(mutating_f))(object::O, meteo::PlantMeteo.AbstractAtmosphere, constants=PlantMeteo.Constants(), extra=nothing) where {O<:AbstractDict}
            for (k, v) in object
                $(mutating_f)(v, meteo, constants, extra)
            end
            return nothing
        end

        # Process method over several meteo time steps (called Weather) and possibly several components:
        function $(esc(mutating_f))(
            object::T,
            meteo::Weather,
            constants=PlantMeteo.Constants(),
            extra=nothing
        ) where {T<:Union{AbstractArray,AbstractDict}}

            # Check if the meteo data and the status have the same length (or length 1)
            check_status_wheather(object, meteo)

            # Each object:
            for obj in object
                # Computing for each time-step:
                for (i, meteo_i) in enumerate(meteo.data)
                    $(esc(f_))(obj.models.$(process_field), obj.models, obj[i], meteo_i, constants, extra)
                end
            end

        end

        # If we call weather with one component only:
        function $(esc(mutating_f))(object::T, meteo::Weather, constants=PlantMeteo.Constants(), extra=nothing) where {T<:ModelList}

            # Check if the meteo data and the status have the same length (or length 1)
            check_status_wheather(object, meteo)

            # Computing for each time-steps:
            for (i, meteo_i) in enumerate(meteo.data)
                $(esc(f_))(object.models.$(process_field), object.models, object.status[i], meteo_i, constants, extra)
            end
        end

        # Compatibility with MTG:
        function $(esc(mutating_f))(
            mtg::MultiScaleTreeGraph.Node,
            models::Dict{String,M},
            meteo::PlantMeteo.AbstractAtmosphere,
            constants=PlantMeteo.Constants()
        ) where {M<:ModelList}
            # Define the attribute name used for the models in the nodes
            attr_name = MultiScaleTreeGraph.cache_name("PlantBiophysics models")

            # initialize the MTG nodes with the corresponding models:
            init_mtg_models!(mtg, models, attr_name=attr_name)

            MultiScaleTreeGraph.transform!(
                mtg,
                (node) -> $(mutating_f)(node[attr_name], meteo, constants, node),
                ignore_nothing=true
            )
        end

        # Compatibility with MTG + Weather, compute all nodes for one time step, then move to the next time step.
        function $(esc(mutating_f))(
            mtg::MultiScaleTreeGraph.Node,
            models::Dict{String,M},
            meteo::Weather,
            constants=PlantMeteo.Constants()
        ) where {M<:ModelList}
            # Define the attribute name used for the models in the nodes
            attr_name = Symbol(MultiScaleTreeGraph.cache_name("PlantBiophysics models"))

            # Init the status for the meteo step only (with an PlantMeteo.AbstractAtmosphere)
            to_init = init_mtg_models!(mtg, models, 1, attr_name=attr_name)
            #! Here we use only one time-step for the status whatever the number of timesteps
            #! to simulate. Then we use this status for all the meteo steps (we re-initialize
            #! its values at each step). We do this to not replicate much data, but it is not
            #! the best way to do it because we don't use the nice methods from above that
            #! control the simulations for meteo / status timesteps. What we could do instead
            #! is to have a TimeSteps status for several timesteps, and then use pointers to
            #! the values in the node attributes. This we would avoid to replicate the data
            #! and we could use the fancy methods from above.

            # Pre-allocate the node attributes based on the simulated variables and number of steps:
            nsteps = length(meteo)

            MultiScaleTreeGraph.traverse!(
                mtg,
                (x -> pre_allocate_attr!(x, nsteps; attr_name=attr_name)),
            )

            # Computing for each time-steps:
            for (i, meteo_i) in enumerate(meteo.data)
                # Then update the initialisation each time-step.
                update_mtg_models!(mtg, i, to_init, attr_name)

                MultiScaleTreeGraph.transform!(
                    mtg,
                    (node) -> Symbol($(esc(process_field))) in keys(node[attr_name].models) && $(mutating_f)(node[attr_name], meteo_i, constants, node),
                    (node) -> pull_status_one_step!(node, i, attr_name=attr_name),
                    ignore_nothing=true
                )
            end
        end

        # Non-mutating version (make a copy before the call, and return the copy):
        function $(esc(non_mutating_f))(
            object::O,
            meteo::Union{Nothing,PlantMeteo.AbstractAtmosphere,Weather}=nothing,
            constants=PlantMeteo.Constants(),
            extra=nothing
        ) where {O<:Union{ModelList,AbstractArray,AbstractDict}}
            object_tmp = copy(object)
            $(esc(mutating_f))(object_tmp, meteo, constants, extra)
            return object_tmp
        end
    end
end
