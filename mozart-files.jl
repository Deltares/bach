# Functions to read Mozart input files into DataFrames, or derived structures like graphs.

using DataFrames
using CSV
using Dates

"Parse a Mozart style date string"
function datestring(s)
    # uslswdem once has "20100000.000000", parse as Jan 1st
    if s == "20100000.000000"
        DateTime(2010, 1, 1)
    else
        DateTime(s, dateformat"yyyymmdd.000000")
    end
end

"Write a table to a Tab Separated Value"
tsv(path, table) = CSV.write(path, table; delim = '\t')

"Read local surface water value"
function read_lswvalue(path)
    names = [
        "lsw",
        "time_start",
        "time_end",
        "concentration",
        "evaporation",
        "level",
        "seepage",
        "discharge",
        "area",
        "volume",
        "level_rtc",
        "volume_rtc",
        "alien_water_ratio",
    ]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

"Read lsw routing"
function read_lswrouting(path)
    names = ["lsw_from", "lsw_to", "usercode", "fraction"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read lsw routing dbc"
function read_lswrouting_dbc(path)
    names = ["lsw_from", "lsw_to", "usercode", "fraction"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read local surface water"
function read_lsw(path)
    # no name given and last 3 columns are missing
    names = [
        "lsw",
        "lsw_exchanges",
        "districtwatercode",
        "districtwatercode_exchanges",
        "meteostationcode",
        "local_surface_water_type",
        "depth_surface_water",
        "target_level",
        "target_volume",
        "maximum_level",
        "fraction",
        "priority",
        "alien_waterquality_standard",
        "salt_waterquality_standard",
        "seepage_coëfficiënt",
        "sum_all_plot_areas_not_in_DB",
        "salt_concentration_groundwater",
    ]
    types = Dict(
        "target_level" => Float64,
        "target_volume" => Float64,
        "maximum_level" => Float64,
        "fraction" => Float64,
        "priority" => Float64,
        "alien_waterquality_standard" => Float64,
        "salt_waterquality_standard" => Float64,
        "sum_all_plot_areas_not_in_DB" => Float64,
    )
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
end

"Read district water value"
function read_dwvalue(path)
    names = [
        "districtwatercode",
        "time_start",
        "time_end",
        "concentration",
        "evaporation",
        "total_flushing_demand",
        "volume",
        "alien_water_ratio",
    ]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

"Read weir area"
function read_weirarea(path)
    names = ["weirarea", "lsw"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read level area discharge value"
function read_ladvalue(path)
    names = ["level", "lsw", "area", "discharge"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read volume area discharge"
function read_vadvalue(path)
    names = ["lsw", "volume", "area", "discharge"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read volume level"
function read_vlvalue(path)
    names = ["lsw", "weirarea", "volume_lsw", "level", "level_slope"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read district water"
function read_dw(path)
    names = [
        "districtwatercode",
        "districtwatername",
        "meteostationcode",
        "area",
        "depth_surface_water",
        "target_volume",
        "alien_water_ratio",
        "salt_concentration_in_network",
        "debiet",
        "upstream_factor",
    ]
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
    df[!, "districtwatername"] .= String.(strip.(df.districtwatername))
    return df
end

"Read drain plot"
function read_drpl(path)
    # TODO find name of last columns (always 0)
    names = ["plot", "drain", "draintype", "x1", "x2", "x3"]
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
    @assert all(iszero, df.x1)
    @assert all(iszero, df.x2)
    @assert all(iszero, df.x3)
    return df
end

"Read drain plot value"
function read_drplval(path)
    # TODO find name of last column (always 0)
    names = ["drain", "plot", "time_start", "time_end", "x1"]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    @assert all(iszero, df.x1)
    return df
end

"Read plot boundary"
function read_plbound(path)
    # TODO find name of last columns
    # 030984 19660101.000000 19680101.000000 -1.260000000 0.1000 0.0000 0.0000000000
    names = ["plot", "time_start", "time_end", "x1", "x2", "x3", "x4"]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    @assert all(iszero, df.x3)
    @assert all(iszero, df.x4)
    return df
end

"Read plot"
function read_plot(path)
    # TODO find names of columns
    # 030984 0002 0002 030984 R 0002 236875.00 0.0000000 0.5800 -9.420 0.40 5.10 00000039 0000 16 S 0.0015 1.50 0.000000
    # 030985 0002 0002 030985 R 0002 237862.00 12138.000 0.3200 -9.680 0.40 5.10 00000033 0000 17 N 0.0015 1.50 0.000000
    names = vcat("plot", [string('x', i) for i = 1:18])
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read plot segment value"
function read_plsgval(path)
    # TODO find names of columns
    # 030984 16 1 01 19651221.000000 19660101.000000 1.0000 0.000 16.016 0.389960 0.0000000000 -1.335000000 118.31000000 0.0000000000 0.00000000 000
    # 030984 16 2 01 19651221.000000 19660101.000000 0.0000 0.000 40.430 0.472780 0.0000000000 -1.135000000 1183.1000000 0.0000000000 0.00000000 000
    names = [
        "plot",
        "x1",
        "x1",
        "x3",
        "time_start",
        "time_end",
        "x4",
        "x5",
        "x6",
        "x7",
        "x8",
        "x9",
        "x10",
        "x11",
        "x12",
        "x13",
    ]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

"Read plot value"
function read_plvalue(path)
    # TODO find names of columns
    # 030984 19651221.000000 19660101.000000 1.0000 0.0000 11831.000000 -0.955 0.0000 0.0000 0.0000 28.000 0.1000000000 1.0000 0.000000 0.0000 0.0000000000 0.0000000000 0.000000 0.0000000000 0.0000 0.0000000000 1183.1000000
    # 030985 19651221.000000 19660101.000000 1.0000 0.0000 11592.000000 -1.080 0.0000 0.0000 0.0000 28.000 0.1000000000 1.0000 0.000000 0.0000 0.0000000000 0.0000000000 0.000000 0.0000000000 0.0000 0.0000000000 1159.2000000
    names = [
        "plot",
        "time_start",
        "time_end",
        "x1",
        "x2",
        "x3",
        "x4",
        "x5",
        "x6",
        "x7",
        "x8",
        "x9",
        "x10",
        "x11",
        "x12",
        "x13",
        "x14",
        "x15",
        "x16",
        "x17",
        "x18",
        "x19",
    ]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

"Read user per lsw"
function read_uslsw(path)
    names = ["lsw", "usercode"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        strict = true,
    )
end

"Read user demand per lsw"
function read_uslswdem(path)
    names = [
        "lsw",
        "time_start",
        "usercode",
        "time_end",
        "user_groundwater_demand",
        "user_surfacewater_demand",
        "fraction",
        "priority",
        "alien_waterquality_standard",
        "salt_waterquality_standard",
        "level_real_time_control",
    ]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

"Read lsw attributes"
function read_lswattr(path)
    # TODO find names of columns
    # 10020, 517, 149642, 30, 10020, 7976
    # 10037, 3146, 58335, 49, 10037, 27017
    names = ["lsw", "x1", "x2", "x3", "x4", "x5"]
    return CSV.read(path, DataFrame; header = names, stringtype = String, strict = true)
end

"Read MODFLOW LSW coupling"
function read_mftolsw(path)
    names = ["col", "row", "lsw", "weirarea", "oppw_correctie"]
    return CSV.read(
        path,
        DataFrame;
        header = names,
        skipto = 2,
        stringtype = String,
        strict = true,
    )
end

"Read plot LSW coupling"
function read_plottolsw(path)
    return CSV.read(path, DataFrame; stringtype = String, strict = true)
end

"Read weir area attributes"
function read_waattr(path)
    # TODO find name of last column
    # 111002,100003,602
    # 111002,100015,839
    names = ["lsw", "weirarea", "x1"]
    return CSV.read(path, DataFrame; header = names, stringtype = String, strict = true)
end

"Read meteo input timeseries"
function read_meteo(path)
    # type 1 is evaporation, 2 is precipitation
    names = ["type", "lsw", "time_start", "time_end", "value"]
    types = Dict("time_start" => String, "time_end" => String)
    df = CSV.read(
        path,
        DataFrame;
        header = names,
        delim = ' ',
        ignorerepeated = true,
        stringtype = String,
        types,
        strict = true,
    )
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

reference_model = "decadal"
if reference_model == "daily"
    simdir = normpath(@__DIR__, "data/lhm-daily/LHM41_dagsom")
    mozart_dir = normpath(simdir, "work/mozart")
    mozartout_dir = mozart_dir
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = normpath(simdir, "tmp")
elseif reference_model == "decadal"
    simdir = normpath(@__DIR__, "data/lhm-input/")
    mozart_dir = normpath(@__DIR__, "data/lhm-input/mozart/mozartin") # duplicate of mozartin now
    mozartout_dir = normpath(@__DIR__, "data/lhm-output/mozart")
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = normpath(simdir, "mozart", "mozartin")
else
    error("unknown reference model")
end
coupling_dir = joinpath(@__DIR__, "data", "lhm-input", "coupling")
# this must be after mozartin has run, or the VAD relations are not correct
unsafe_mozartin_dir = joinpath(@__DIR__, "data", "lhm-input", "mozart", "mozartin")

tot_dir = joinpath(@__DIR__, "data", "lhm-input", "mozart", "tot")
meteo_dir = joinpath(
    @__DIR__,
    "data",
    "lhm-input",
    "control",
    "control_LHM4_2_2019_2020",
    "meteo",
    "mozart",
)

mftolsw = read_mftolsw(joinpath(coupling_dir, "MFtoLSW.csv"))
plottolsw = read_plottolsw(joinpath(coupling_dir, "PlottoLSW.csv"))

dw = read_dw(joinpath(mozartin_dir, "dw.dik"))
dwvalue = read_dwvalue(joinpath(mozartin_dir, "dwvalue.dik"))
ladvalue = read_ladvalue(joinpath(mozartin_dir, "ladvalue.dik"))
lswdik = read_lsw(joinpath(mozartin_dir, "lsw.dik"))
lswrouting = read_lswrouting(joinpath(mozartin_dir, "lswrouting.dik"))
lswvalue = read_lswvalue(joinpath(mozartin_dir, "lswvalue.dik"))
uslsw = read_uslsw(joinpath(mozartin_dir, "uslsw.dik"))
uslswdem = read_uslswdem(joinpath(mozartin_dir, "uslswdem.dik"))
vadvalue = read_vadvalue(joinpath(mozartin_dir, "vadvalue.dik"))
vlvalue = read_vlvalue(joinpath(mozartin_dir, "vlvalue.dik"))
weirarea = read_weirarea(joinpath(mozartin_dir, "weirarea.dik"))
# wavalue.dik is missing

# these are not in mozartin_dir
lswrouting_dbc = read_lswrouting_dbc(joinpath(mozart_dir, "LswRouting_dbc.dik"))
lswattr = read_lswattr(joinpath(unsafe_mozartin_dir, "lswattr.csv"))
waattr = read_waattr(joinpath(unsafe_mozartin_dir, "waattr.csv"))

drpl = read_drpl(joinpath(tot_dir, "drpl.dik"))
drplval = read_drplval(joinpath(tot_dir, "drplval.dik"))
plbound = read_plbound(joinpath(tot_dir, "plbound.dik"))
plotdik = read_plot(joinpath(tot_dir, "plot.dik"))
plsgval = read_plsgval(joinpath(tot_dir, "plsgval.dik"))
plvalue = read_plvalue(joinpath(tot_dir, "plvalue.dik"))

meteo = read_meteo(joinpath(meteo_dir, "metocoef.ext"))

nothing
