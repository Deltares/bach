from enum import Enum
from pathlib import Path

from pydantic import Field

from ribasim.input_base import BaseModel, NodeModel, TableModel

# These schemas are autogenerated
from ribasim.schemas import (  # type: ignore
    BasinProfileSchema,
    BasinStateSchema,
    BasinStaticSchema,
    BasinTimeSchema,
    DiscreteControlConditionSchema,
    DiscreteControlLogicSchema,
    FlowBoundaryStaticSchema,
    FlowBoundaryTimeSchema,
    FractionalFlowStaticSchema,
    LevelBoundaryStaticSchema,
    LevelBoundaryTimeSchema,
    LinearResistanceStaticSchema,
    ManningResistanceStaticSchema,
    OutletStaticSchema,
    PidControlStaticSchema,
    PidControlTimeSchema,
    PumpStaticSchema,
    TabulatedRatingCurveStaticSchema,
    TabulatedRatingCurveTimeSchema,
    TerminalStaticSchema,
    UserStaticSchema,
    UserTimeSchema,
)


class Allocation(BaseModel):
    timestep: float | None = None
    use_allocation: bool = False
    objective_type: str = "quadratic_relative"


class Compression(str, Enum):
    zstd = "zstd"
    lz4 = "lz4"


class Results(BaseModel):
    basin: Path = Field(default=Path("basin.arrow"), exclude=True, repr=False)
    flow: Path = Field(default=Path("flow.arrow"), exclude=True, repr=False)
    control: Path = Field(default=Path("control.arrow"), exclude=True, repr=False)
    allocation: Path = Field(default=Path("allocation.arrow"), exclude=True, repr=False)
    outstate: str | None = None
    compression: Compression = Compression.zstd
    compression_level: int = 6


class Solver(BaseModel):
    algorithm: str = "QNDF"
    saveat: float | list[float] = []
    adaptive: bool = True
    dt: float | None = None
    dtmin: float | None = None
    dtmax: float | None = None
    force_dtmin: bool = False
    abstol: float = 1e-06
    reltol: float = 1e-05
    maxiters: int = 1000000000
    sparse: bool = True
    autodiff: bool = True


class Verbosity(str, Enum):
    debug = "debug"
    info = "info"
    warn = "warn"
    error = "error"


class Logging(BaseModel):
    verbosity: Verbosity = Verbosity.info
    timing: bool = False


class Terminal(NodeModel):
    static: TableModel[TerminalStaticSchema] = Field(
        default_factory=TableModel[TerminalStaticSchema]
    )


class PidControl(NodeModel):
    static: TableModel[PidControlStaticSchema] = Field(
        default_factory=TableModel[PidControlStaticSchema]
    )
    time: TableModel[PidControlTimeSchema] = Field(
        default_factory=TableModel[PidControlTimeSchema]
    )

    _sort_keys: dict[str, list[str]] = {"time": ["time", "node_id"]}


class LevelBoundary(NodeModel):
    static: TableModel[LevelBoundaryStaticSchema] = Field(
        default_factory=TableModel[LevelBoundaryStaticSchema]
    )
    time: TableModel[LevelBoundaryTimeSchema] = Field(
        default_factory=TableModel[LevelBoundaryTimeSchema]
    )

    _sort_keys: dict[str, list[str]] = {"time": ["time", "node_id"]}


class Pump(NodeModel):
    static: TableModel[PumpStaticSchema] = Field(
        default_factory=TableModel[PumpStaticSchema]
    )


class TabulatedRatingCurve(NodeModel):
    static: TableModel[TabulatedRatingCurveStaticSchema] = Field(
        default_factory=TableModel[TabulatedRatingCurveStaticSchema]
    )
    time: TableModel[TabulatedRatingCurveTimeSchema] = Field(
        default_factory=TableModel[TabulatedRatingCurveTimeSchema]
    )
    _sort_keys: dict[str, list[str]] = {
        "static": ["node_id", "level"],
        "time": ["time", "node_id", "level"],
    }


class User(NodeModel):
    static: TableModel[UserStaticSchema] = Field(
        default_factory=TableModel[UserStaticSchema]
    )
    time: TableModel[UserTimeSchema] = Field(default_factory=TableModel[UserTimeSchema])

    _sort_keys: dict[str, list[str]] = {
        "static": ["node_id", "priority"],
        "time": ["node_id", "priority", "time"],
    }


class FlowBoundary(NodeModel):
    static: TableModel[FlowBoundaryStaticSchema] = Field(
        default_factory=TableModel[FlowBoundaryStaticSchema]
    )
    time: TableModel[FlowBoundaryTimeSchema] = Field(
        default_factory=TableModel[FlowBoundaryTimeSchema]
    )

    _sort_keys: dict[str, list[str]] = {"time": ["time", "node_id"]}


class Basin(NodeModel):
    profile: TableModel[BasinProfileSchema] = Field(
        default_factory=TableModel[BasinProfileSchema]
    )
    state: TableModel[BasinStateSchema] = Field(
        default_factory=TableModel[BasinStateSchema]
    )
    static: TableModel[BasinStaticSchema] = Field(
        default_factory=TableModel[BasinStaticSchema]
    )
    time: TableModel[BasinTimeSchema] = Field(
        default_factory=TableModel[BasinTimeSchema]
    )

    _sort_keys: dict[str, list[str]] = {
        "profile": ["node_id", "level"],
        "time": ["time", "node_id"],
    }


class ManningResistance(NodeModel):
    static: TableModel[ManningResistanceStaticSchema] = Field(
        default_factory=TableModel[ManningResistanceStaticSchema]
    )


class DiscreteControl(NodeModel):
    condition: TableModel[DiscreteControlConditionSchema] = Field(
        default_factory=TableModel[DiscreteControlConditionSchema]
    )
    logic: TableModel[DiscreteControlLogicSchema] = Field(
        default_factory=TableModel[DiscreteControlLogicSchema]
    )


class Outlet(NodeModel):
    static: TableModel[OutletStaticSchema] = Field(
        default_factory=TableModel[OutletStaticSchema]
    )


class LinearResistance(NodeModel):
    static: TableModel[LinearResistanceStaticSchema] = Field(
        default_factory=TableModel[LinearResistanceStaticSchema]
    )


class FractionalFlow(NodeModel):
    static: TableModel[FractionalFlowStaticSchema] = Field(
        default_factory=TableModel[FractionalFlowStaticSchema]
    )
