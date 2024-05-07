"""
Get a sparse matrix whose sparsity matches (with some false positives) the sparsity of the Jacobian
of the ODE problem. All nodes are taken into consideration, also the ones
that are inactive.

In Ribasim the Jacobian is typically sparse because each state only depends on a small
number of other states.

The aim is that jac_prototype[i,j] = 1.0 if and only if
there is the possibility that at some point in the simulation:

∂water_balance![j]/∂u[i] ≠ 0.0

which means that du[j] depends on u[i].

Note: the name 'prototype' does not mean this code is a prototype, it comes
from the naming convention of this sparsity structure in the
differentialequations.jl docs.
"""
function get_jac_prototype(
    p::Parameters,
    u::ComponentVector,
)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control, graph, user_demand, allocation) = p
    n_states = length(u)
    axis = only(getfield(u, :axes))
    jac_prototype = ComponentMatrix(spzeros(n_states, n_states), (axis, axis))

    # Storages depending on storages
    update_jac_prototype!(jac_prototype, basin, graph)

    # PID control states depending on storages (and the other way around)
    update_jac_prototype!(jac_prototype, pid_control, basin, graph)

    # Flows depending on storages
    update_jac_prototype!(jac_prototype, p)

    # Evaporation and infiltration depending on storages
    update_jac_prototype!(jac_prototype, basin)

    # Allocation input flows depending on storages
    # Note, this is copied from the update_jac_prototype!(jac_prototype, p)
    # result so the order is important
    update_jac_prototype!(jac_prototype, allocation, graph)

    # UserDemand inflows depending on storages
    update_jac_prototype!(jac_prototype, user_demand, graph, basin)
    return jac_prototype.data
end

"""
Add nonzeros for basins connected to eachother via 1 node and possibly a fractional flow node.
Basins are also assumed to depend on themselves (main diagonal terms)
"""
function update_jac_prototype!(
    jac_prototype::ComponentMatrix,
    basin::Basin,
    graph::MetaGraph,
)::Nothing
    jac_prototype_storage = @view jac_prototype[:storage, :storage]
    for (idx_1, id) in enumerate(basin.node_id)
        for id_neighbor in inoutflow_ids(graph, id)
            for id_neighbor_neighbor in inoutflow_ids(graph, id_neighbor)
                if id_neighbor_neighbor.type == NodeType.FractionalFlow
                    id_neighbor_neighbor = outflow_id(graph, id_neighbor_neighbor)
                end
                if id_neighbor_neighbor.type == NodeType.Basin
                    _, idx_2 = id_index(basin.node_id, id_neighbor_neighbor)
                    jac_prototype_storage[idx_1, idx_2] = 1.0
                end
            end
        end
    end
    return nothing
end

"""
Add nonzeros for the integral term and the basins on either side of the controlled node
"""
function update_jac_prototype!(
    jac_prototype::ComponentMatrix,
    pid_control::PidControl,
    basin::Basin,
    graph::MetaGraph,
)::Nothing
    jac_prototype_storage_integral = @view jac_prototype[:storage, :integral]
    jac_prototype_integral_storage = @view jac_prototype[:integral, :storage]
    for (idx_integral, id) in enumerate(pid_control.node_id)
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        for id_basin in inoutflow_ids(graph, id_controlled)
            if id_basin.type == NodeType.Basin
                _, idx_basin = id_index(basin.node_id, id_basin)
                jac_prototype_storage_integral[idx_basin, idx_integral] = 1.0
                jac_prototype_integral_storage[idx_integral, idx_basin] = 1.0
            end
        end
    end
    return nothing
end

"""
Add nonzeros for flows depending on storages.
"""
function update_jac_prototype!(jac_prototype::ComponentMatrix, p::Parameters)::Nothing
    (; graph, basin) = p
    (; flow_dict) = graph[]
    jac_prototype_storage_flow = @view jac_prototype[:storage, :flow_integrated]
    # Per node, find the connected edges and basins
    # (possibly via FractionalFlow), and assume
    # that all found edges depend on all found storages
    for node_id in values(graph.vertex_labels)
        if node_id.type in [NodeType.Basin, NodeType.FractionalFlow]
            continue
        end
        basin_ids = Set{NodeID}()
        edges = Set{Tuple{NodeID, NodeID}}()
        for inneighbor_id in inflow_ids(graph, node_id)
            push!(edges, (inneighbor_id, node_id))
            if inneighbor_id.type == NodeType.Basin
                push!(basin_ids, inneighbor_id)
            end
        end
        for outneighbor_id in outflow_ids(graph, node_id)
            push!(edges, (node_id, outneighbor_id))
            if outneighbor_id.type == NodeType.Basin
                push!(basin_ids, outneighbor_id)
            elseif outneighbor_id.type == NodeType.FractionalFlow
                fractional_flow_outflow_id = outflow_id(graph, outneighbor_id)
                push!(edges, (outneighbor_id, fractional_flow_outflow_id))
            end
        end
        for (basin_id, edge) in Iterators.product(basin_ids, edges)
            _, basin_idx = id_index(basin.node_id, basin_id)
            edge_idx = flow_dict[edge]
            jac_prototype_storage_flow[basin_idx, edge_idx] = 1.0
        end
    end
    return nothing
end

"""
Add nonzeros for evaporation and infiltration depending on storages
"""
function update_jac_prototype!(jac_prototype::ComponentMatrix, basin::Basin)::Nothing
    jac_prototype_evaporation = @view jac_prototype[:storage, :evaporation_integrated]
    jac_prototype_infiltration = @view jac_prototype[:storage, :infiltration_integrated]
    jac_prototype_evaporation_bmi = @view jac_prototype[:storage, :evaporation_integrated]
    jac_prototype_infiltration_bmi = @view jac_prototype[:storage, :infiltration_integrated]
    for (i, id) in enumerate(basin.node_id)
        jac_prototype_evaporation[i, i] = 1.0
        jac_prototype_infiltration[i, i] = 1.0
        jac_prototype_evaporation_bmi[i, i] = 1.0
        jac_prototype_infiltration_bmi[i, i] = 1.0
    end
    return nothing
end

"""
Add nonzeros for allocation input flows depending on storages.
"""
function update_jac_prototype!(
    jac_prototype::ComponentMatrix,
    allocation::Allocation,
    graph::MetaGraph,
)::Nothing
    (; input_flow_dict) = allocation
    (; flow_dict) = graph[]
    jac_prototype_storage_flow = @view jac_prototype[:storage, :flow_integrated]
    jac_prototype_storage_flow_allocation =
        @view jac_prototype[:storage, :flow_allocation_input]
    # Copy which storages a flow depends on
    for (edge, i) in input_flow_dict
        # A self-loop indicates basin forcing
        if edge[1] == edge[2]
            continue
        end
        jac_prototype_storage_flow_allocation[:, i] =
            jac_prototype_storage_flow[:, flow_dict[edge]]
    end
    return nothing
end

"""
Add nonzeros for UserDemand intake flows depending on storages.
"""
function update_jac_prototype!(
    jac_prototype::ComponentMatrix,
    user_demand::UserDemand,
    graph::MetaGraph,
    basin::Basin,
)::Nothing
    jac_prototype_storage_realized_demand =
        @view jac_prototype[:storage, :realized_user_demand_bmi]
    for (user_demand_idx, node_id) in enumerate(user_demand.node_id)
        basin_node_id = inflow_id(graph, node_id)
        has_index, i = id_index(basin.node_id, basin_node_id)
        @assert has_index "UserDemand inflow node is not a basin."
        jac_prototype_storage_realized_demand[i, user_demand_idx] = 1.0
    end
    return nothing
end
