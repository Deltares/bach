function BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model
    config = Config(config_path)
    BMI.initialize(T, config)
end

function BMI.initialize(T::Type{Model}, config::Config)::Model
    if config.solver.autodiff
        set_preferences!(ForwardDiff, "nansafe_mode" => true)
    end
    alg = algorithm(config.solver)
    gpkg_path = input_path(config, config.geopackage)
    if !isfile(gpkg_path)
        throw(SystemError("GeoPackage file not found: $gpkg_path"))
    end

    # Setup timing logging
    if config.logging.timing
        TimerOutputs.enable_debug_timings(Ribasim)  # causes recompilation (!)
    end

    # All data from the GeoPackage that we need during runtime is copied into memory,
    # so we can directly close it again.
    db = SQLite.DB(gpkg_path)
    local parameters, state, n, tstops
    try
        parameters = Parameters(db, config)

        if !valid_n_neighbors(parameters)
            error("Invalid number of connections for certain node types.")
        end

        if !valid_discrete_control(parameters, config)
            error("Invalid discrete control state definition(s).")
        end

        (; pid_control, connectivity, basin, pump, outlet, fractional_flow) = parameters
        if !valid_pid_connectivity(
            pid_control.node_id,
            pid_control.listen_node_id,
            connectivity.graph_flow,
            connectivity.graph_control,
            basin.node_id,
            pump.node_id,
        )
            error("Invalid PidControl connectivity.")
        end

        if !valid_fractional_flow(
            connectivity.graph_flow,
            fractional_flow.node_id,
            fractional_flow.fraction,
        )
            error("Invalid fractional flow node combinations found.")
        end

        for id in pid_control.node_id
            id_controlled = only(outneighbors(connectivity.graph_control, id))
            pump_idx = findsorted(pump.node_id, id_controlled)
            if isnothing(pump_idx)
                outlet_idx = findsorted(outlet.node_id, id_controlled)
                outlet.is_pid_controlled[outlet_idx] = true
            else
                pump.is_pid_controlled[pump_idx] = true
            end
        end

        # tstops for transient flow_boundary
        time_flow_boundary = load_structvector(db, config, FlowBoundaryTimeV1)
        tstops = get_tstops(time_flow_boundary.time, config.starttime)

        # use state
        state = load_structvector(db, config, BasinStateV1)
        n = length(get_ids(db, "Basin"))
    finally
        # always close the GeoPackage, also in case of an error
        close(db)
    end
    @debug "Read database into memory."

    storage = if isempty(state)
        # default to nearly empty basins, perhaps make required input
        fill(1.0, n)
    else
        storages, errors = get_storages_from_levels(parameters.basin, state.level)
        if errors
            error("Encountered errors while parsing the initial levels of basins.")
        end
        storages
    end
    @assert length(storage) == n "Basin / state length differs from number of Basins"
    # Integrals for PID control
    integral = zeros(length(parameters.pid_control.node_id))
    u0 = ComponentVector{Float64}(; storage, integral)
    t_end = seconds_since(config.endtime, config.starttime)
    # for Float32 this method allows max ~1000 year simulations without accuracy issues
    @assert eps(t_end) < 3600 "Simulation time too long"
    timespan = (zero(t_end), t_end)

    jac_prototype = config.solver.sparse ? get_jac_prototype(parameters) : nothing
    RHS = ODEFunction(water_balance!; jac_prototype)

    @timeit_debug to "Setup ODEProblem" begin
        prob = ODEProblem(RHS, u0, timespan, parameters)
    end
    @debug "Setup ODEProblem."

    callback, saved_flow = create_callbacks(parameters; config.solver.saveat)
    @debug "Created callbacks."

    @timeit_debug to "Setup integrator" integrator = init(
        prob,
        alg;
        progress = true,
        progress_name = "Simulating",
        callback,
        tstops,
        config.solver.saveat,
        config.solver.adaptive,
        config.solver.dt,
        config.solver.abstol,
        config.solver.reltol,
        config.solver.maxiters,
    )
    @debug "Setup integrator."

    if config.logging.timing
        @show Ribasim.to
    end

    set_initial_discrete_controlled_parameters!(integrator, storage)

    return Model(integrator, config, saved_flow)
end

function BMI.finalize(model::Model)::Model
    compress = get_compressor(model.config.output)
    write_basin_output(model, compress)
    write_flow_output(model, compress)
    write_discrete_control_output(model, compress)
    @debug "Wrote output."
    return model
end

function set_initial_discrete_controlled_parameters!(
    integrator,
    storage0::Vector{Float64},
)::Nothing
    (; p) = integrator
    (; basin, discrete_control) = p

    n_conditions = length(discrete_control.condition_value)
    condition_diffs = zeros(Float64, n_conditions)
    discrete_control_condition(condition_diffs, storage0, integrator.t, integrator)
    discrete_control.condition_value .= (condition_diffs .> 0.0)

    # For every discrete_control node find a condition_idx it listens to
    for discrete_control_node_id in unique(discrete_control.node_id)
        condition_idx =
            searchsortedfirst(discrete_control.node_id, discrete_control_node_id)
        discrete_control_affect!(integrator, condition_idx, missing)
    end
end

"""
Create the different callbacks that are used to store output
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
    parameters;
    saveat,
)::Tuple{CallbackSet, SavedValues{Float64, Vector{Float64}}}
    (; starttime, basin, tabulated_rating_curve, discrete_control) = parameters

    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(tstops, update_tabulated_rating_curve!)

    # add a single time step's contribution to the water balance step's totals
    # trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # flows: save the flows over time, as a Vector of the nonzeros(flow)

    saved_flow = SavedValues(Float64, Vector{Float64})

    save_flow_cb = SavingCallback(save_flow, saved_flow; saveat, save_start = false)

    n_conditions = length(discrete_control.node_id)
    if n_conditions > 0
        discrete_control_cb = VectorContinuousCallback(
            discrete_control_condition,
            discrete_control_affect_upcrossing!,
            discrete_control_affect_downcrossing!,
            n_conditions,
        )
        callback = CallbackSet(
            save_flow_cb,
            basin_cb,
            tabulated_rating_curve_cb,
            discrete_control_cb,
        )
    else
        callback = CallbackSet(save_flow_cb, basin_cb, tabulated_rating_curve_cb)
    end

    return callback, saved_flow
end

"""
Listens for changes in condition truths.
"""
function discrete_control_condition(out, u, t, integrator)
    (; p) = integrator
    (; discrete_control) = p

    for (i, (listen_feature_id, variable, greater_than, look_ahead)) in enumerate(
        zip(
            discrete_control.listen_feature_id,
            discrete_control.variable,
            discrete_control.greater_than,
            discrete_control.look_ahead,
        ),
    )
        value = get_value(p, listen_feature_id, variable, look_ahead, u, t)
        diff = value - greater_than
        out[i] = diff
    end
end

"""
Get a value for a condition. Currently supports getting levels from basins and flows
from flow boundaries.
"""
function get_value(
    p::Parameters,
    feature_id::Int,
    variable::String,
    Δt::Float64,
    u::AbstractVector{Float64},
    t::Float64,
)
    (; basin, flow_boundary, level_boundary) = p

    if variable == "level"
        hasindex_basin, basin_idx = id_index(basin.node_id, feature_id)
        level_boundary_idx = findsorted(level_boundary.node_id, feature_id)

        if hasindex_basin
            _, level = get_area_and_level(basin, basin_idx, u[basin_idx])
        elseif !isnothing(level_boundary_idx)
            level = level_boundary.level[level_boundary_idx](t + Δt)
        else
            error(
                "Level condition node '$feature_id' is neither a basin nor a level boundary.",
            )
        end

        value = level

    elseif variable == "flow_rate"
        flow_boundary_idx = findsorted(flow_boundary.node_id, feature_id)

        if isnothing(flow_boundary_idx)
            error("Flow condition node #$feature_id is not a flow boundary.")
        end

        value = flow_boundary.flow_rate[flow_boundary_idx](t + Δt)
    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

"""
An upcrossing means that a condition (always greater than) becomes true.
"""
function discrete_control_affect_upcrossing!(integrator, condition_idx)
    (; p, u, t) = integrator
    (; discrete_control, basin) = p
    (; variable, condition_value, listen_feature_id) = discrete_control

    condition_value[condition_idx] = true

    control_state_change = discrete_control_affect!(integrator, condition_idx, true)

    # Check whether the control state change changed the direction of the crossing
    # NOTE: This works for level conditions, but not for flow conditions on an
    # arbitrary edge. That is because parameter changes do not change the instantaneous level,
    # only possibly the du. Parameter changes can change the flow on an edge discontinuously,
    # giving the possibility of logical paradoxes where certain parameter changes immediately
    # undo the truth state that caused that parameter change.
    is_basin = id_index(basin.node_id, discrete_control.listen_feature_id[condition_idx])[1]
    # NOTE: The above no longer works when listen feature ids can be something other than node ids
    # I think the more durable option is to give all possible condition types a different variable string,
    # e.g. basin.level and level_boundary.level
    if variable[condition_idx] == "level" && control_state_change && is_basin
        # Calling water_balance is expensive, but it is a sure way of getting
        # du for the basin of this level condition
        du = zero(u)
        water_balance!(du, u, p, t)
        _, condition_basin_idx = id_index(basin.node_id, listen_feature_id[condition_idx])

        if du[condition_basin_idx] < 0.0
            condition_value[condition_idx] = false
            discrete_control_affect!(integrator, condition_idx, false)
        end
    end
end

"""
An downcrossing means that a condition (always greater than) becomes false.
"""
function discrete_control_affect_downcrossing!(integrator, condition_idx)
    (; p, u, t) = integrator
    (; discrete_control, basin) = p
    (; variable, condition_value, listen_feature_id) = discrete_control

    condition_value[condition_idx] = false

    control_state_change = discrete_control_affect!(integrator, condition_idx, false)

    # Check whether the control state change changed the direction of the crossing
    # NOTE: This works for level conditions, but not for flow conditions on an
    # arbitrary edge. That is because parameter changes do not change the instantaneous level,
    # only possibly the du. Parameter changes can change the flow on an edge discontinuously,
    # giving the possibility of logical paradoxes where certain parameter changes immediately
    # undo the truth state that caused that parameter change.
    if variable[condition_idx] == "level" && control_state_change
        # Calling water_balance is expensive, but it is a sure way of getting
        # du for the basin of this level condition
        du = zero(u)
        water_balance!(du, u, p, t)
        has_index, condition_basin_idx =
            id_index(basin.node_id, listen_feature_id[condition_idx])

        if has_index && du[condition_basin_idx] > 0.0
            condition_value[condition_idx] = true
            discrete_control_affect!(integrator, condition_idx, true)
        end
    end
end

"""
Change parameters based on the control logic.
"""
function discrete_control_affect!(
    integrator,
    condition_idx::Int,
    upcrossing::Union{Bool, Missing},
)::Bool
    p = integrator.p
    (; discrete_control, connectivity) = p

    # Get the discrete_control node that listens to this condition
    discrete_control_node_id = discrete_control.node_id[condition_idx]

    # Get the indices of all conditions that this control node listens to
    condition_ids = discrete_control.node_id .== discrete_control_node_id

    # Get the truth state for this discrete_control node
    condition_value_local = discrete_control.condition_value[condition_ids]
    truth_values = [ifelse(b, "T", "F") for b in condition_value_local]
    truth_state = join(truth_values, "")

    # Get the truth specific about the latest crossing
    if !ismissing(upcrossing)
        truth_values[condition_idx] = upcrossing ? "U" : "D"
    end
    truth_state_crossing_specific = join(truth_values, "")

    # What the local control state should be
    control_state_new =
        if haskey(
            discrete_control.logic_mapping,
            (discrete_control_node_id, truth_state_crossing_specific),
        )
            truth_state_used = truth_state_crossing_specific
            discrete_control.logic_mapping[(
                discrete_control_node_id,
                truth_state_crossing_specific,
            )]
        elseif haskey(
            discrete_control.logic_mapping,
            (discrete_control_node_id, truth_state),
        )
            truth_state_used = truth_state
            discrete_control.logic_mapping[(discrete_control_node_id, truth_state)]
        else
            error(
                "Control state specified for neither $truth_state_crossing_specific nor $truth_state for DiscreteControl node #$discrete_control_node_id.",
            )
        end

    # What the local control state is
    # TODO: Check time elapsed since control change
    control_state_now, control_state_start =
        discrete_control.control_state[discrete_control_node_id]

    control_state_change = false

    if control_state_now != control_state_new
        control_state_change = true

        # Store control action in record
        record = discrete_control.record

        push!(record.time, integrator.t)
        push!(record.control_node_id, discrete_control_node_id)
        push!(record.truth_state, truth_state_used)
        push!(record.control_state, control_state_new)

        # Loop over nodes which are under control of this control node
        for target_node_id in
            outneighbors(connectivity.graph_control, discrete_control_node_id)
            set_control_params!(p, target_node_id, control_state_new)
        end

        discrete_control.control_state[discrete_control_node_id] =
            (control_state_new, integrator.t)
    end
    return control_state_change
end

function set_control_params!(p::Parameters, node_id::Int, control_state::String)
    node = getfield(p, p.lookup[node_id])
    idx = searchsortedfirst(node.node_id, node_id)
    new_state = node.control_mapping[(node_id, control_state)]

    for (field, value) in zip(keys(new_state), new_state)
        if !ismissing(value)
            vec = preallocation_dispatch(getfield(node, field), 0)
            vec[idx] = value
        end
    end
end

"Copy the current flow to the SavedValues"
function save_flow(u, t, integrator)
    copy(nonzeros(preallocation_dispatch(integrator.p.connectivity.flow, u)))
end

"Load updates from 'Basin / time' into the parameters"
function update_basin(integrator)::Nothing
    (; basin) = integrator.p
    (; node_id, time) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)

    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    table = (;
        basin.precipitation,
        basin.potential_evaporation,
        basin.drainage,
        basin.infiltration,
    )

    for row in timeblock
        hasindex, i = id_index(node_id, row.node_id)
        @assert hasindex "Table 'Basin / time' contains non-Basin IDs"
        set_table_row!(table, row, i)
    end

    return nothing
end

"Load updates from 'TabulatedRatingCurve / time' into the parameters"
function update_tabulated_rating_curve!(integrator)::Nothing
    (; node_id, tables, time) = integrator.p.tabulated_rating_curve
    t = datetime_since(integrator.t, integrator.p.starttime)

    # get groups of consecutive node_id for the current timestamp
    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    for group in IterTools.groupby(row -> row.node_id, timeblock)
        # update the existing LinearInterpolation
        id = first(group).node_id
        level = [row.level for row in group]
        discharge = [row.discharge for row in group]
        i = searchsortedfirst(node_id, id)
        tables[i] = LinearInterpolation(discharge, level)
    end
    return nothing
end

function BMI.update(model::Model)::Model
    step!(model.integrator)
    return model
end

function BMI.update_until(model::Model, time)::Model
    integrator = model.integrator
    t = integrator.t
    dt = time - t
    if dt < 0
        error("The model has already passed the given timestamp.")
    elseif dt == 0
        return model
    else
        step!(integrator, dt, true)
    end
    return model
end

function BMI.get_value_ptr(model::Model, name::AbstractString)
    if name == "volume"
        model.integrator.u.storage
    elseif name == "level"
        model.integrator.p.basin.current_level
    elseif name == "infiltration"
        model.integrator.p.basin.infiltration
    elseif name == "drainage"
        model.integrator.p.basin.drainage
    else
        error("Unknown variable $name")
    end
end

BMI.get_current_time(model::Model) = model.integrator.t
BMI.get_start_time(model::Model) = 0.0
BMI.get_end_time(model::Model) = seconds_since(model.config.endtime, model.config.starttime)
BMI.get_time_units(model::Model) = "s"
BMI.get_time_step(model::Model) = get_proposed_dt(model.integrator)

run(config_file::AbstractString)::Model = run(Config(config_file))

function is_current_module(log)
    (log._module == @__MODULE__) ||
        (parentmodule(log._module) == @__MODULE__) ||
        log._module == OrdinaryDiffEq  # for the progress bar
end

function run(config::Config)::Model
    logger = current_logger()

    # Reconfigure the logger if necessary with the correct loglevel
    # but make sure to only log from Ribasim
    if min_enabled_level(logger) + 1 != config.logging.verbosity
        logger = EarlyFilteredLogger(
            is_current_module,
            LevelOverrideLogger(config.logging.verbosity, logger),
        )
    end

    with_logger(logger) do
        model = BMI.initialize(Model, config)
        solve!(model.integrator)
        BMI.finalize(model)
        return model
    end
end
