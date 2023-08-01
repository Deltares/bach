function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    linear_resistance::LinearResistance,
    t::Float64,
)::Nothing
    (; basin, connectivity) = p
    (; active, resistance, node_id) = linear_resistance
    (; graph_flow) = connectivity

    for (id, isactive, R) in zip(node_id, active, resistance)
        if !isactive
            continue
        end

        id_in = only(inneighbors(graph_flow, id))
        id_out = only(outneighbors(graph_flow, id))

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            area_in = basin.current_area[idx_in]
            term_in = 1 / (area_in * R)
            J[idx_in, idx_in] -= term_in
        end

        if has_index_out
            area_out = basin.current_area[idx_out]
            term_out = 1 / (area_out * R)
            J[idx_out, idx_out] -= term_out
        end

        if has_index_in && has_index_out
            J[idx_in, idx_out] += term_out
            J[idx_out, idx_in] += term_in
        end
    end
    return nothing
end

function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    manning_resistance::ManningResistance,
    t::Float64,
)::Nothing
    (; basin, connectivity) = p
    (; node_id, active, length, manning_n, profile_width, profile_slope) =
        manning_resistance
    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        #TODO: this was copied from formulate! for the manning_resistance,
        # maybe put in separate function
        basin_a_id = only(inneighbors(graph_flow, id))
        basin_b_id = only(outneighbors(graph_flow, id))

        h_a = get_level(p, basin_a_id)
        h_b = get_level(p, basin_b_id)
        bottom_a, bottom_b = basin_bottoms(basin, basin_a_id, basin_b_id, id)
        slope = profile_slope[i]
        width = profile_width[i]
        n = manning_n[i]
        L = length[i]

        Δh = h_a - h_b
        q_sign = sign(Δh)

        # Average d, A, R
        d_a = h_a - bottom_a
        d_b = h_b - bottom_b
        d = 0.5 * (d_a + d_b)

        A_a = width * d + slope * d_a^2
        A_b = width * d + slope * d_b^2
        A = 0.5 * (A_a + A_b)

        slope_unit_length = sqrt(slope^2 + 1.0)
        P_a = width + 2.0 * d_a * slope_unit_length
        P_b = width + 2.0 * d_b * slope_unit_length
        R_h_a = A_a / P_a
        R_h_b = A_b / P_b
        R_h = 0.5 * (R_h_a + R_h_b)

        k = 1000.0
        kΔh = k * Δh
        atankΔh = atan(k * Δh)
        ΔhatankΔh = Δh * atankΔh

        q = q_sign * A / n * R_h^(2 / 3) * sqrt(ΔhatankΔh / L)

        id_in = only(inneighbors(graph_flow, id))
        id_out = only(outneighbors(graph_flow, id))

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            basin_in_area = basin.current_area[idx_in]
            ∂A_a = (width + 2 * slope * d_a) / basin_in_area
            ∂A = 0.5 * ∂A_a
            ∂P_a = 2 * slope_unit_length / basin_in_area
            ∂R_h_a = (P_a * ∂A_a - A_a * ∂P_a) / P_a^2
            ∂R_h_b = width / (2 * basin_in_area * P_b)
            ∂R_h = 0.5 * (∂R_h_a + ∂R_h_b)
            sqrt_contribution =
                (atankΔh + kΔh / (1 + kΔh^2)) / (basin_in_area * sqrt(2 * π) * ΔhatankΔh)
            term_in = q * (∂A / A + ∂R_h / R_h + sqrt_contribution)
            J[idx_in, idx_in] -= term_in
        end

        if has_index_out
            basin_out_area = basin.current_area[idx_out]
            ∂A_b = (width + 2 * slope * d_b) / basin_out_area
            ∂A = 0.5 * ∂A_b
            ∂P_b = 2 * slope_unit_length / basin_out_area
            ∂R_h_b = (P_b * ∂A_b - A_b * ∂P_b) / P_b^2
            ∂R_h_b = width / (2 * basin_out_area * P_b)
            ∂R_h = 0.5 * (∂R_h_b + ∂R_h_a)
            sqrt_contribution =
                (atankΔh + kΔh / (1 + kΔh^2)) / (basin_out_area * sqrt(2 * π) * ΔhatankΔh)
            term_out = q * (∂A / A + ∂R_h / R_h + sqrt_contribution)

            J[idx_out, idx_out] -= term_out
        end

        if has_index_in && has_index_out
            J[idx_in, idx_out] += term_out
            J[idx_out, idx_in] += term_in
        end
    end
    return nothing
end

function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    pump::Pump,
    t::Float64,
)::Nothing
    (; basin, fractional_flow, connectivity, pid_control) = p
    (; active, node_id, flow_rate) = pump

    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        if id in pid_control.listen_node_id
            continue
        end

        id_in = only(inneighbors(graph_flow, id))

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        # (but not both at the same time!)
        if has_index_in
            s = u.storage[idx_in]

            if s < 10.0
                dq = flow_rate[i] / 10.0

                J[idx_in, idx_in] -= dq

                has_index_out, idx_out = id_index(basin.node_id, id_in)

                idxs_fractional_flow, idxs_out = get_fractional_flow_connected_basins(
                    id,
                    basin,
                    fractional_flow,
                    graph_flow,
                )

                if isempty(idxs_out)
                    id_out = only(outneighbors(graph_flow, id))
                    has_index_out, idx_out = id_index(basin.node_id, id_out)

                    if has_index_out
                        J[idx_in, idx_out] = dq
                    end
                else
                    for (idx_fractional_flow, idx_out) in
                        zip(idxs_fractional_flow, idxs_out)
                        J[idx_in, idx_out] +=
                            dq * fractional_flow.fraction[idx_fractional_flow]
                    end
                end
            end
        end
    end
    return nothing
end

function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    tabulated_rating_curve::TabulatedRatingCurve,
    t::Float64,
)::Nothing
    (; basin, fractional_flow, connectivity) = p
    (; node_id, active, tables) = tabulated_rating_curve
    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        id_in = only(inneighbors(graph_flow, id))

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        if has_index_in
            # Computing this slope here is silly,
            # should eventually be computed pre-simulation and cached!
            table = tables[i]
            levels = table.t
            flows = table.u
            level = basin.current_level[idx_in]
            level_smaller_idx = searchsortedlast(table.t, level)
            if level_smaller_idx == 0
                level_smaller_idx = 1
            elseif level_smaller_idx == length(flows)
                level_smaller_idx = length(flows) - 1
            end

            slope =
                (flows[level_smaller_idx + 1] - flows[level_smaller_idx]) /
                (levels[level_smaller_idx + 1] - levels[level_smaller_idx])

            dq = slope / basin.current_area[idx_in]

            J[idx_in, idx_in] -= dq

            idxs_fractional_flow, idxs_out =
                get_fractional_flow_connected_basins(id, basin, fractional_flow, graph_flow)

            if isempty(idxs_out)
                id_out = only(outneighbors(graph_flow, id))
                has_index_out, idx_out = id_index(basin.node_id, id_out)

                if has_index_out
                    J[idx_in, idx_out] = dq
                end
            else
                for (idx_fractional_flow, idx_out) in zip(idxs_fractional_flow, idxs_out)
                    J[idx_in, idx_out] += dq * fractional_flow.fraction[idx_fractional_flow]
                end
            end
        end
    end
    return nothing
end

function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    pid_control::PidControl,
    t::Float64,
)::Nothing
    (; basin, connectivity, pump) = p
    (; node_id, active, listen_node_id, proportional, integral, derivative, error) =
        pid_control
    (; min_flow_rate, max_flow_rate) = pump
    (; graph_flow, graph_control) = connectivity

    get_error!(pid_control, p)

    n_basins = length(basin.node_id)
    integral_value = u.integral

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        # TODO: This has been copied from continuous_control!, maybe
        # put in separate function
        flow_rate = 0.0

        K_p = proportional[i]
        if !isnan(K_p)
            flow_rate += K_p * error[i]
        end

        K_d = derivative[i]
        if !isnan(K_d)
            # dlevel/dstorage = 1/area
            area = basin.current_area[listened_node_idx]

            error_deriv = -dstorage[listened_node_idx] / area
            flow_rate += K_d * error_deriv
        end

        K_i = integral[i]
        if !isnan(K_i)
            # coefficient * current value of integral
            flow_rate += K_i * integral_value[i]
        end

        # Clip values outside pump flow rate bounds
        was_clipped = false

        if flow_rate < min_flow_rate[i]
            was_clipped = true
            flow_rate = min_flow_rate[i]
        end

        if !isnan(max_flow_rate[i])
            if flow_rate > max_flow_rate[i]
                was_clipped = true
                flow_rate = max_flow_rate[i]
            end
        end

        id_pump = only(outneighbors(graph_control, id))
        listen_id = listen_node_id[i]
        _, listen_idx = id_index(basin.node_id, listen_id)
        listen_area = basin.current_area[listen_idx]

        # PID control integral state
        pid_state_idx = n_basins + i
        J[pid_state_idx, listen_idx] -= 1 / listen_area

        # If the flow rate is clipped to one of the bounds it does
        # not change with storages and thus doesn't contribute to the
        # Jacobian
        if was_clipped
            continue
        end

        storage_controlled = u.storage[listen_idx]
        phi = storage_controlled < 10.0 ? storage_controlled / 10 : 1.0
        dphi = storage_controlled < 10.0 ? 1 / 10 : 0.0

        dq = dphi * flow_rate

        if !isnan(K_p)
            dq += K_p * phi / listen_area
        end

        if !isnan(K_d)
            dq += K_d * flow_rate * basin.current_darea[listen_idx] / listen_area^2
            dq /= 1.0 + K_d * phi / listen_area
        end

        J[listen_idx, listen_idx] -= dq

        if !isnan(K_i)
            J[listen_idx, pid_state_idx] -= K_i * phi
        end

        id_out = only(outneighbors(graph_flow, id_pump))
        has_index, idx_out_out = id_index(basin.node_id, id_out)

        if has_index
            jac_prototype[pid_state_idx, idx_out_out] += K_i * phi
            jac_prototype[listen_idx, idx_out_out] += dq
        end
    end
    return nothing
end

"""
Method for nodes that do not contribute to the Jacobian
"""
function formulate_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    node::AbstractParameterNode,
    t::Float64,
)::Nothing
    node_type = nameof(typeof(node))

    if !isa(
        node,
        Union{
            Basin,
            DiscreteControl,
            FlowBoundary,
            FractionalFlow,
            LevelBoundary,
            Terminal,
        },
    )
        error(
            "It is not specified how nodes of type $node_type contribute to the Jacobian.",
        )
    end
    return nothing
end

function water_balance_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t,
)::Nothing
    (; basin) = p
    J .= 0.0

    # Ensures current_level and current_area are current
    set_current_area_and_level!(basin, u.storage, t)

    for nodefield in nodefields(p)
        formulate_jac!(J, u, p, getfield(p, nodefield), t)
    end

    return nothing
end
