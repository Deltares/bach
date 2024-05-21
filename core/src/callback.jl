struct TrapezoidIntegrationAffect{IntegrandFunc, T}
    integrand_func!::IntegrandFunc
    integrand_value::T
    cache::T
    integral::T
end

function TrapezoidIntegrationCallback(integrand_func!, integral_value)::DiscreteCallback
    integrand_value = zero(integral_value)
    cache = zero(integral_value)
    affect! =
        TrapezoidIntegrationAffect(integrand_func!, integrand_value, cache, integral_value)
    return DiscreteCallback(
        (u, t, integrator) -> t != 0,
        affect!;
        save_positions = (false, false),
    )
end

function (affect!::TrapezoidIntegrationAffect)(integrator)::Nothing
    (; integrand_func!, integrand_value, cache, integral) = affect!
    (; dt, p) = integrator

    # What is a good way to check that this is the first time this
    # function is called? E.g. that only one timestep has been done?
    if iszero(integral)
        integrand_func!(integrand_value, p)
    end

    cache .= integrand_value
    integrand_func!(integrand_value, p)
    cache .+= integrand_value
    cache .*= 0.5 * dt

    integral .+= cache
    return nothing
end

"""
Create the different callbacks that are used to store results
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
    parameters::Parameters,
    config::Config,
    saveat,
)::Tuple{CallbackSet, SavedResults}
    (;
        starttime,
        graph,
        basin,
        user_demand,
        tabulated_rating_curve,
        discrete_control,
        allocation,
    ) = parameters
    callbacks = SciMLBase.DECallback[]

    # Check for negative storages
    negative_storage_cb = FunctionCallingCallback(check_negative_storage)
    push!(callbacks, negative_storage_cb)

    # Integrate flows and vertical basin fluxes for mean outputs
    integrating_flow_cb =
        TrapezoidIntegrationCallback(flow_integrand!, graph[].integrated_flow)
    push!(callbacks, integrating_flow_cb)

    # Save mean flows
    saved_flow = SavedValues(Float64, SavedFlow)
    save_flow_cb = SavingCallback(
        save_flow,
        saved_flow;
        saveat = (saveat isa Vector) ? filter(x -> x != 0, saveat) : saveat,
        save_start = false,
    )
    push!(callbacks, save_flow_cb)

    # Integrate vertical basin fluxes for BMI
    integrated_bmi_data = ComponentVector{Float64}(;
        get_tmp(basin.vertical_flux, 0)...,
        user_realized = zeros(length(user_demand.node_id)),
    )
    integrating_for_bmi_cb =
        TrapezoidIntegrationCallback(bmi_integrand!, integrated_bmi_data)
    push!(callbacks, integrating_for_bmi_cb)

    # Integrate flows for allocation input
    integrating_for_allocation_cb =
        TrapezoidIntegrationCallback(allocation_integrand!, allocation.integrated_flow)
    push!(callbacks, integrating_for_allocation_cb)

    # TODO: What is this?
    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin; save_positions = (false, false))
    push!(callbacks, basin_cb)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(
        tstops,
        update_tabulated_rating_curve!;
        save_positions = (false, false),
    )
    push!(callbacks, tabulated_rating_curve_cb)

    # interpolate the levels
    saved_subgrid_level = SavedValues(Float64, Vector{Float64})
    if config.results.subgrid
        export_cb = SavingCallback(
            save_subgrid_level,
            saved_subgrid_level;
            saveat,
            save_start = true,
        )
        push!(callbacks, export_cb)
    end

    saved = SavedResults(saved_flow, saved_subgrid_level, integrated_bmi_data)

    n_conditions = sum(length(vec) for vec in discrete_control.greater_than; init = 0)
    if n_conditions > 0
        discrete_control_cb = FunctionCallingCallback(apply_discrete_control!)
        push!(callbacks, discrete_control_cb)
    end
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function flow_integrand!(out, p)::Nothing
    (; basin, graph) = p
    (; vertical_flux) = basin
    vertical_flux = get_tmp(vertical_flux, 0)
    flow = get_tmp(graph[].flow, 0)

    out.flow .= flow
    vertical_flux_view(out) .= vertical_flux
    return nothing
end

function bmi_integrand!(out, p)::Nothing
    (; basin, user_demand, graph) = p
    vertical_flux_view(out) .= get_tmp(basin.vertical_flux, 0)

    for i in eachindex(user_demand.node_id)
        out.user_realized[i] = get_flow(graph, user_demand.inflow_edge[i], 0)
    end
    return
end

function allocation_integrand!(out, p)::Nothing
    (; allocation, graph, basin) = p
    for (edge, i) in allocation.integrated_flow_mapping
        if edge[1] == edge[2]
            # Vertical fluxes
            _, basin_idx = id_index(basin.node_id, edge[1])
            out[i] = get_influx(basin, basin_idx)
        else
            # Horizontal flows
            out[i] = get_flow(graph, edge..., 0)
        end
    end
    return nothing
end

function save_flow(u, t, integrator)
    (; basin, graph) = integrator.p
    (; integrated_flow) = graph[]
    Δt = get_Δt(integrator)
    flow_mean = copy(integrated_flow)
    flow_mean ./= Δt
    fill!(integrated_flow, 0.0)
    inflow_mean, outflow_mean = compute_mean_inoutflows(flow_mean.flow, basin)
    return SavedFlow(; flow = flow_mean, inflow = inflow_mean, outflow = outflow_mean)
end

function check_negative_storage(u, t, integrator)::Nothing
    (; basin) = integrator.p
    (; node_id) = basin
    errors = false
    for (i, id) in enumerate(node_id)
        if u.storage[i] < 0
            @error "Negative storage detected in $id"
            errors = true
        end
    end

    if errors
        t_datetime = datetime_since(integrator.t, integrator.p.starttime)
        error("Negative storages found at $t_datetime.")
    end
    return nothing
end

function apply_discrete_control!(u, t, integrator)::Nothing
    (; p) = integrator
    (; discrete_control) = p

    discrete_control_condition!(u, t, integrator)

    # For every compound variable see whether it changes a control state
    for compound_variable_idx in eachindex(discrete_control.node_id)
        discrete_control_affect!(integrator, compound_variable_idx)
    end
end

"""
Update discrete control condition truths.
"""
function discrete_control_condition!(u, t, integrator)
    (; p) = integrator
    (; discrete_control) = p

    # Loop over compound variables
    for (
        listen_node_ids,
        variables,
        weights,
        greater_thans,
        look_aheads,
        condition_values,
    ) in zip(
        discrete_control.listen_node_id,
        discrete_control.variable,
        discrete_control.weight,
        discrete_control.greater_than,
        discrete_control.look_ahead,
        discrete_control.condition_value,
    )
        value = 0.0
        for (listen_node_id, variable, weight, look_ahead) in
            zip(listen_node_ids, variables, weights, look_aheads)
            value += weight * get_value(p, listen_node_id, variable, look_ahead, u, t)
        end

        condition_values .= false
        condition_values[1:searchsortedlast(greater_thans, value)] .= true
    end
end

"""
Get a value for a condition. Currently supports getting levels from basins and flows
from flow boundaries.
"""
function get_value(
    p::Parameters,
    node_id::NodeID,
    variable::String,
    Δt::Float64,
    u::AbstractVector{Float64},
    t::Float64,
)
    (; basin, flow_boundary, level_boundary) = p

    if variable == "level"
        if node_id.type == NodeType.Basin
            has_index, basin_idx = id_index(basin.node_id, node_id)
            if !has_index
                error("Discrete control listen node $node_id does not exist.")
            end
            _, level = get_area_and_level(basin, basin_idx, u[basin_idx])
        elseif node_id.type == NodeType.LevelBoundary
            level_boundary_idx = findsorted(level_boundary.node_id, node_id)
            level = level_boundary.level[level_boundary_idx](t + Δt)
        else
            error(
                "Level condition node '$node_id' is neither a basin nor a level boundary.",
            )
        end
        value = level

    elseif variable == "flow_rate"
        if node_id.type == NodeType.FlowBoundary
            flow_boundary_idx = findsorted(flow_boundary.node_id, node_id)
            value = flow_boundary.flow_rate[flow_boundary_idx](t + Δt)
        else
            error("Flow condition node $node_id is not a flow boundary.")
        end

    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

"""
Change parameters based on the control logic.
"""
function discrete_control_affect!(integrator, compound_variable_idx)
    p = integrator.p
    (; discrete_control, graph) = p

    # Get the discrete_control node to which this compound variable belongs
    discrete_control_node_id = discrete_control.node_id[compound_variable_idx]

    # Get the indices of all conditions that this control node listens to
    where_node_id = searchsorted(discrete_control.node_id, discrete_control_node_id)

    # Get the truth state for this discrete_control node
    truth_values = cat(
        [
            [ifelse(b, "T", "F") for b in discrete_control.condition_value[i]] for
            i in where_node_id
        ]...;
        dims = 1,
    )
    truth_state = join(truth_values, "")

    # What the local control state should be
    control_state_new =
        if haskey(discrete_control.logic_mapping, (discrete_control_node_id, truth_state))
            discrete_control.logic_mapping[(discrete_control_node_id, truth_state)]
        else
            error(
                "No control state specified for $discrete_control_node_id for truth state $truth_state.",
            )
        end

    control_state_now, _ = discrete_control.control_state[discrete_control_node_id]
    if control_state_now != control_state_new
        # Store control action in record
        record = discrete_control.record

        push!(record.time, integrator.t)
        push!(record.control_node_id, Int32(discrete_control_node_id))
        push!(record.truth_state, truth_state)
        push!(record.control_state, control_state_new)

        # Loop over nodes which are under control of this control node
        for target_node_id in
            outneighbor_labels_type(graph, discrete_control_node_id, EdgeType.control)
            set_control_params!(p, target_node_id, control_state_new)
        end

        discrete_control.control_state[discrete_control_node_id] =
            (control_state_new, integrator.t)
    end
    return nothing
end

function get_allocation_model(p::Parameters, subnetwork_id::Int32)::AllocationModel
    (; allocation) = p
    (; subnetwork_ids, allocation_models) = allocation
    idx = findsorted(subnetwork_ids, subnetwork_id)
    if isnothing(idx)
        error("Invalid allocation network ID $subnetwork_id.")
    else
        return allocation_models[idx]
    end
end

function get_main_network_connections(
    p::Parameters,
    subnetwork_id::Int32,
)::Vector{Tuple{NodeID, NodeID}}
    (; allocation) = p
    (; subnetwork_ids, main_network_connections) = allocation
    idx = findsorted(subnetwork_ids, subnetwork_id)
    if isnothing(idx)
        error("Invalid allocation network ID $subnetwork_id.")
    else
        return main_network_connections[idx]
    end
    return
end

"""
Update the fractional flow fractions in an allocation problem.
"""
function set_fractional_flow_in_allocation!(
    p::Parameters,
    node_id::NodeID,
    fraction::Number,
)::Nothing
    (; graph) = p

    subnetwork_id = graph[node_id].subnetwork_id
    # Get the allocation model this fractional flow node is in
    allocation_model = get_allocation_model(p, subnetwork_id)
    if !isnothing(allocation_model)
        problem = allocation_model.problem
        # The allocation edge which jumps over the fractional flow node
        edge = (inflow_id(graph, node_id), outflow_id(graph, node_id))
        if haskey(graph, edge...)
            # The constraint for this fractional flow node
            if edge in keys(problem[:fractional_flow])
                constraint = problem[:fractional_flow][edge]

                # Set the new fraction on all inflow terms in the constraint
                for inflow_id in inflow_ids_allocation(graph, edge[1])
                    flow = problem[:F][(inflow_id, edge[1])]
                    JuMP.set_normalized_coefficient(constraint, flow, -fraction)
                end
            end
        end
    end
    return nothing
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)
    node = getfield(p, p.graph[node_id].type)
    idx = searchsortedfirst(node.node_id, node_id)
    new_state = node.control_mapping[(node_id, control_state)]

    for (field, value) in zip(keys(new_state), new_state)
        if !ismissing(value)
            vec = get_tmp(getfield(node, field), 0)
            vec[idx] = value
        end

        # Set new fractional flow fractions in allocation problem
        if is_active(p.allocation) && node isa FractionalFlow && field == :fraction
            set_fractional_flow_in_allocation!(p, node_id, value)
        end
    end
end

function update_subgrid_level!(integrator)::Nothing
    basin_level = get_tmp(integrator.p.basin.current_level, 0)
    subgrid = integrator.p.subgrid
    for (i, (index, interp)) in enumerate(zip(subgrid.basin_index, subgrid.interpolations))
        subgrid.level[i] = interp(basin_level[index])
    end
end

"Interpolate the levels and save them to SavedValues"
function save_subgrid_level(u, t, integrator)
    update_subgrid_level!(integrator)
    return copy(integrator.p.subgrid.level)
end

"Load updates from 'Basin / time' into the parameters"
function update_basin(integrator)::Nothing
    (; p, u) = integrator
    (; basin) = p
    (; storage) = u
    (; node_id, time, vertical_flux_from_input, vertical_flux) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)
    vertical_flux = get_tmp(vertical_flux, integrator.u)

    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    table = (;
        vertical_flux_from_input.precipitation,
        vertical_flux_from_input.potential_evaporation,
        vertical_flux_from_input.drainage,
        vertical_flux_from_input.infiltration,
    )

    for row in timeblock
        hasindex, i = id_index(node_id, NodeID(NodeType.Basin, row.node_id))
        @assert hasindex "Table 'Basin / time' contains non-Basin IDs"
        set_table_row!(table, row, i)
    end

    update_vertical_flux!(basin, storage)
    update_vertical_flux_integrands!(integrator, vertical_flux)
    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; p, t, u) = integrator
    (; allocation) = p
    (; allocation_models, integrated_flow) = allocation

    # Don't run the allocation algorithm if allocation is not active
    # (Specifically for running Ribasim via the BMI)
    if !is_active(allocation)
        return nothing
    end

    (; Δt_allocation) = allocation_models[1]

    # Divide by the allocation Δt to obtain the mean flows
    # from the integrated flows
    integrated_flow ./= Δt_allocation

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            allocate!(p, allocation_model, t, u, OptimizationType.internal_sources)
            allocate!(p, allocation_model, t, u, OptimizationType.collect_demands)
        end
    end

    # Solve the allocation problems
    # If a main network is present this is solved first,
    # which provides allocation to the subnetworks
    for allocation_model in allocation_models
        allocate!(p, allocation_model, t, u, OptimizationType.allocate)
    end

    # Reset the mean source flows
    integrated_flow .= 0.0
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
        flow_rate = [row.flow_rate for row in group]
        i = searchsortedfirst(node_id, NodeID(NodeType.TabulatedRatingCurve, id))
        tables[i] = LinearInterpolation(flow_rate, level; extrapolate = true)
    end
    return nothing
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
