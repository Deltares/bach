using Ribasim
using CSV
using DataFrames
using DataFrameMacros
import BasicModelInterface as BMI
using SciMLBase

@testset "allocation_V" begin
    config = Ribasim.parsefile("testrun.toml")
    config["add_levelcontrol"] = false
    config["waterbalance"] = "output/waterbalance_alloc_V.arrow"

    # Load dummmy forcing
    df = CSV.read("data/dummyforcing_151358_V.csv",
                  DataFrame;
                  header = ["time", "variable", "location", "value"],
                  delim = ',',
                  ignorerepeated = true,
                  stringtype = String,
                  strict = true)

    config["forcing"] = df
    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)

    output = Ribasim.samples_long(reg)

    demand_getvar = :demand
    demand = @subset(output, :variable==demand_getvar).value
    alloc_getvar = :alloc
    alloc = @subset(output, :variable==alloc_getvar).value
    abs_getvar = :abs
    abs = @subset(output, :variable==abs_getvar).value
    area_getvar = :area
    area = @subset(output, :variable==area_getvar).value
    P_getvar = :P
    P = @subset(output, :variable==P_getvar).value   # P and Epot are from the forcing
    Epot_getvar = :E_pot
    E_pot = @subset(output, :variable==Epot_getvar).value

    t = reg.integrator.sol.t
    S = reg.integrator.sol(t, idxs = 1) # TODO: improve ease of using usyms names
    drainage = reg.integrator.sol(t, idxs = 4)
    infiltration = reg.integrator.sol(t, idxs = 5)
    urban_runoff = reg.integrator.sol(t, idxs = 6)

    @test S[1] == 14855.394135012128 # To update
    @test S[235] == 7427.697265625 # To update

    # Test allocation
    @test demand >= alloc
    @test alloc[2] ==
          ((P[2] - E_pot[2]) * area[2]) / 86400.00 -
          min(0.0, infiltration[2] - drainage[2] - urban_runoff[2])
    @test abs[2] == alloc[2] * (0.5 * tanh((S[2] - 50.0) / 10.0) + 0.5)

    # TODO: Set up test for when there are more than one users (indus?)

    # TODO: Test for multiple allocation users

end

@testset "allocation_P" begin
    config = Ribasim.parsefile("testrun.toml")
    config["add_levelcontrol"] = true
    config["waterbalance"] = "output/waterbalance_alloc_P.arrow"

    # Load dummmy input forcing
    datadir = normpath(@__DIR__, "data")
    df = CSV.read(normpath(datadir, "dummyforcing_151358_P.csv"), #update
                  DataFrame;
                  header = ["time", "variable", "location", "value"],
                  delim = ',',
                  ignorerepeated = true,
                  stringtype = String,
                  strict = true)

    config["forcing"] = df

    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)

    output = Ribasim.samples_long(reg)

    # Test the output parameters are as expected
    demand_getvar = :demand
    demand = @subset(output, :variable==demand_getvar).value
    alloc_getvar = :alloc
    alloc = @subset(output, :variable==alloc_getvar).value
    abs_getvar = :abs
    abs = @subset(output, :variable==abs_getvar).value
    area_getvar = :area
    area = @subset(output, :variable==area_getvar).value
    P_getvar = :P
    P = @subset(output, :variable==P_getvar).value   # P and Epot are from the forcing
    Epot_getvar = :E_pot
    E_pot = @subset(output, :variable==Epot_getvar).value

    t = reg.integrator.sol.t
    S = reg.integrator.sol(t, idxs = 1) # TODO: improve ease of using usyms names
    drainage = reg.integrator.sol(t, idxs = 4)
    infiltration = reg.integrator.sol(t, idxs = 5)
    urban_runoff = reg.integrator.sol(t, idxs = 6)

    @test S[1] == 14855.394135012128 # To update
    @test S[235] == 7427.697265625 # To update

    bQ = @subset(output, :variable==Symbol("b.Q")).value
    aQ = @subset(output, :variable==Symbol("a.Q")).value

    # Test allocation equations
    @test demand >= alloc
    @test alloc[2] ==
          ((P[2] - E_pot[2]) * area[2]) / 86400.00 -
          min(0.0, infiltration[2] - drainage[2] - urban_runoff[2])
    @test abs[2] == alloc[2] * (0.5 * tanh((S[2] - 50.0) / 10.0) + 0.5)

    @test aQ == -bQ

    # Test that prio_wm is > prio_agric

    # Test that at timestep i, abstraction wm = x, abstraction agric = y

    # Test that "external water" alloc_b used when shortage occurs

end

@testset "flushing" begin

    # TODO: Test for situation when there is a flushing requirement (salinity)

end
