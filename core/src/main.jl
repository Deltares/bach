function help(x::AbstractString)::Cint
    println(x)
    println("Usage: ribasim path/to/model/ribasim.toml")
    return 1
end

function main(ARGS::Vector{AbstractString})::Cint
    n = length(ARGS)
    if n != 1
        return help("Exactly 1 argument expected, got $n")
    end
    arg = only(ARGS)

    if arg == "--version"
        version = pkgversion(Ribasim)
        print(version)
        return 0
    end

    if !isfile(arg)
        return help("File not found: $arg")
    end

    try
        # show progress bar in terminal
        config = Config(arg)
        open(results_path(config, "ribasim.log"), "w") do io
            logger =
                Ribasim.setup_logger(; verbosity = config.logging.verbosity, stream = io)
            with_logger(logger) do
                model = Ribasim.run(config)
                if successful_retcode(model)
                    @info "The model finished successfully"
                    return 0
                end

                t = Ribasim.datetime_since(model.integrator.t, model.config.starttime)
                retcode = model.integrator.sol.retcode
                @error "The model exited at model time $t with return code $retcode.\nSee https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes"
                return 1
            end
        end
    catch
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end
end
