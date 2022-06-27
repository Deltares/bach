# %%
import imod
import pandas as pd
import numpy as np
import xarray as xr

import scipy.ndimage


# %%

def find_exterior(active):
    """
    Find the exterior boundaries of the model.
    
    Parameters
    ----------
    active: xr.DataArray of bool
    """
    # Only erode in the horizontal direction.
    structure = np.zeros((1, 3, 3), dtype=int)
    structure[:, 1, :] = 1
    structure[:, :, 1] = 1
    eroded = active.copy(data=scipy.ndimage.binary_erosion(active.values, structure))
    exterior = active & (~eroded)
    return exterior


def detect_empty(pkg):
    for var in pkg.dataset.data_vars:
        da = pkg.dataset[var]
        if "y" in da.coords and "x" in da.coords:
            if da.count() == 0:
                return True
    return False


def assign_axis_attrs(ds):
    """
    Assign the required attributes to a Dataset or DataArray so that QGIS (via
    GDAL) will interpret the coordinates appropriately.
    """
    ds["x"].attrs = {
        "long_name": "x coordinate of projection",
        "standard_name": "projection_x_coordinate",
        "axis": "X",
        "units": "m",
    }
    ds["y"].attrs = {
        "long_name": "x coordinate of projection",
        "standard_name": "projection_y_coordinate",
        "axis": "Y",
        "units": "m",
    }


def LHM_model(xmin=None, xmax=None, ymin=None, ymax=None):
    gwf = imod.mf6.GroundwaterFlowModel()
    # Static data
    gwf["dis"] = imod.mf6.StructuredDiscretization.from_file("netcdf/dis.nc")
    gwf["npf"] = imod.mf6.NodePropertyFlow.from_file("netcdf/npf.nc")
    # IC-steady is the head of an earlier steady-state run, matches this model
    # exactly.
    gwf["ic"] = imod.mf6.InitialConditions.from_file("netcdf/ic-steady-no-wells.nc")
    # Boundary conditions
    gwf["rch"] = imod.mf6.Recharge.from_file("netcdf/rch_sys1.nc")
    gwf["ghb"] = imod.mf6.GeneralHeadBoundary.from_file("netcdf/ghb_sys1.nc")
    # Note that MODFLOW6 does not have "infiltration factors". Instead, Drainage is
    # "stacked" on top of the River to achieve the same behavior.
    gwf["drn_sys1"] = imod.mf6.Drainage.from_file("netcdf/drn_sys1.nc")
    gwf["drn_sys2"] = imod.mf6.Drainage.from_file("netcdf/drn_sys2.nc")
    gwf["drn_sys3"] = imod.mf6.Drainage.from_file("netcdf/drn_sys3.nc")
    gwf["drn_sys4"] = imod.mf6.Drainage.from_file("netcdf/drn_sys4.nc")
    gwf["drn_sys5"] = imod.mf6.Drainage.from_file("netcdf/drn_sys5.nc")
    gwf["drn_sys6"] = imod.mf6.Drainage.from_file("netcdf/drn_sys6.nc")
    gwf["drn_sys7"] = imod.mf6.Drainage.from_file("netcdf/drn_sys7.nc")
    gwf["drn_sys8"] = imod.mf6.Drainage.from_file("netcdf/drn_sys8.nc")
    gwf["drn_sys9"] = imod.mf6.Drainage.from_file("netcdf/drn_sys9.nc")
    gwf["riv_sys1"] = imod.mf6.River.from_file("netcdf/riv_sys1.nc")
    gwf["riv_sys2"] = imod.mf6.River.from_file("netcdf/riv_sys2.nc")
    gwf["riv_sys4"] = imod.mf6.River.from_file("netcdf/riv_sys4.nc")
    gwf["riv_sys5"] = imod.mf6.River.from_file("netcdf/riv_sys5.nc")
    
    if any(limit is not None for limit in (xmin, xmax, ymin, ymax)):
        # Determine the original exterior
        active = gwf["dis"]["idomain"] > 0 
        exterior = find_exterior(active).sel(y=slice(ymax, ymin), x=slice(xmin, xmax))

        to_remove = []
        for name, pkg in gwf.items():
            pkg.dataset = pkg.dataset.sel(y=slice(ymax, ymin), x=slice(xmin, xmax))
            if detect_empty(pkg):
                to_remove.append(name)
                
        for name in to_remove:
            gwf.pop(name)

        submodel_active = gwf["dis"]["idomain"] > 0
        submodel_exterior = find_exterior(submodel_active)
        # Now find the cells which are new in the submodel exterior: these should become constant
        # head boundaries.
        is_chd = submodel_exterior & (~exterior)
        gwf["chd"] = imod.mf6.ConstantHead(head=gwf["ic"]["head"].where(is_chd))
        
    coupling_ds = xr.open_dataset("modflow-mozart-coupling.nc").sel(y=slice(ymax, ymin), x=slice(xmin, xmax))
    return gwf, coupling_ds

# %%

gwf, coupling_ds = LHM_model(
    xmin=195_000.0,
    xmax=275_000.0,
    ymin=425_000.0,
    ymax=510_000.0,
)

# Add a transient storage coefficient, with an effective specific yield in the
# top layer (since we simulate all layers as unconvertible and confined for
# numerical stability.)
storage_coefficient = xr.DataArray(
    data=np.full(15, 1.0e-5),
    coords={"layer": np.arange(1, 16)},
    dims=["layer"],
)
storage_coefficient[0] = 0.15

#transient = xr.DataArray(
#    data=[False, True],
#    coords={"time": pd.to_datetime(["2020-01-01", "2020-01-02"])},
#    dims=["time"],
#)

gwf["oc"] = imod.mf6.OutputControl(save_head="all")
gwf["sto"] = imod.mf6.StorageCoefficient(
    storage_coefficient=storage_coefficient,
    specific_yield=0.15,
    transient=False,
    convertible=0,
)

simulation = imod.mf6.Modflow6Simulation("lhm-dis")
simulation["gwf"] = gwf

simulation["solver"] = imod.mf6.Solution(
    outer_dvclose=1.0e-4,
    outer_maximum=30,
    inner_maximum=200,
    inner_dvclose=1.0e-4,
    inner_rclose=10.0,
    linear_acceleration="cg",
)
times = pd.date_range("2020-01-01", "2020-01-02", freq="d")
simulation.create_time_discretization(times)
simulation.write("LHM-steady-selection", binary=True)

# %%

coupling_ds.to_netcdf("selection-coupling.nc")
# %%


grb_path = r"c:\projects\NHI-prototype\modflow\LHM-steady-selection\gwf\dis.dis.grb"
hds_path = r"c:\projects\NHI-prototype\modflow\LHM-steady-selection\gwf\gwf.hds"
head = imod.mf6.open_hds(hds_path, grb_path).isel(time=0, drop=True)

# %%

assign_axis_attrs(head)
head.to_netcdf("head-steady-selection.nc")
# %%


grb_path = r"c:\projects\NHI-prototype\modflow\LHM-steady\gwf\dis.dis.grb"
hds_path = r"c:\projects\NHI-prototype\modflow\LHM-steady\gwf\gwf.hds"
head = imod.mf6.open_hds(hds_path, grb_path).isel(time=0, drop=True)
# %%
