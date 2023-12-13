@testitem "Allocation solve" begin
    using PreallocationTools: get_tmp
    using Ribasim: NodeID
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    close(db)

    graph = p.graph
    Ribasim.set_flow!(graph, NodeID(1), NodeID(2), 4.5) # Source flow
    allocation_model = p.allocation_models[1]
    Ribasim.allocate!(p, allocation_model, 0.0)

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 0.0]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]
end

@testitem "Allocation objective types" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    @test objective.aff.constant == 2.0
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test objective == F_abs[NodeID(5)] + F_abs[NodeID(6)]

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs in keys(problem.obj_dict)
    F_abs = problem[:F_abs]
    @test objective == F_abs[NodeID(5)] + F_abs[NodeID(6)]
end

@testitem "Allocation with controlled fractional flow" begin
    using DataFrames
    using SQLite
    using Ribasim: NodeID
    using OrdinaryDiffEq: solve!

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/fractional_flow_subnetwork/ribasim.toml",
    )
    model = Ribasim.BMI.initialize(Ribasim.Model, toml_path)
    close(db)
    fractional_flow_constraints =
        model.integrator.p.allocation_models[1].problem[:fractional_flow]
    @test string(fractional_flow_constraints[(NodeID(3), NodeID(5))]) ==
          "fractional_flow[(#3, #5)] : -0.25 F[(#2, #3)] + F[(#3, #5)] <= 0"
    @test string(fractional_flow_constraints[(NodeID(3), NodeID(8))]) ==
          "fractional_flow[(#3, #8)] : -0.75 F[(#2, #3)] + F[(#3, #8)] <= 0"

    solve!(model)
    record_allocation = DataFrame(model.integrator.p.user.record)
    record_control = model.integrator.p.discrete_control.record
    groups = groupby(record_allocation, [:user_node_id, :priority])
    fractional_flow = model.integrator.p.fractional_flow
    (; control_mapping) = fractional_flow
    t_control = record_control.time[2]

    allocated_6_before = groups[(6, 1)][groups[(6, 1)].time .< t_control, :].allocated
    allocated_9_before = groups[(9, 1)][groups[(9, 1)].time .< t_control, :].allocated
    allocated_6_after = groups[(6, 1)][groups[(6, 1)].time .> t_control, :].allocated
    allocated_9_after = groups[(9, 1)][groups[(9, 1)].time .> t_control, :].allocated
    @test all(
        allocated_9_before ./ allocated_6_before .<=
        control_mapping[(NodeID(7), "A")].fraction /
        control_mapping[(NodeID(4), "A")].fraction,
    )
    @test all(allocated_9_after ./ allocated_6_after .<= 1.0)

    @test record_control.truth_state == ["F", "T"]
    @test record_control.control_state == ["A", "B"]

    fractional_flow_constraints =
        model.integrator.p.allocation_models[1].problem[:fractional_flow]
    @test string(fractional_flow_constraints[(NodeID(3), NodeID(5))]) ==
          "fractional_flow[(#3, #5)] : -0.75 F[(#2, #3)] + F[(#3, #5)] <= 0"
    @test string(fractional_flow_constraints[(NodeID(3), NodeID(8))]) ==
          "fractional_flow[(#3, #8)] : -0.25 F[(#2, #3)] + F[(#3, #8)] <= 0"
end
