# generated by datamodel-codegen:
#   filename:  root.schema.json
#   timestamp: 2023-06-12T13:49:07+00:00

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ControlCondition(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    listen_node_id: int = Field(..., description="listen_node_id")
    greater_than: float = Field(..., description="greater_than")
    node_id: int = Field(..., description="node_id")
    variable: str = Field(..., description="variable")


class Edge(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    edge_type: str = Field(..., description="edge_type")
    fid: int = Field(..., description="fid")
    to_node_id: int = Field(..., description="to_node_id")
    from_node_id: int = Field(..., description="from_node_id")


class PumpStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    flow_rate: float = Field(..., description="flow_rate")
    node_id: int = Field(..., description="node_id")
    control_state: Optional[str] = Field(None, description="control_state")


class LevelBoundaryStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    node_id: int = Field(..., description="node_id")
    level: float = Field(..., description="level")
    control_state: Optional[str] = Field(None, description="control_state")


class BasinForcing(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    time: datetime = Field(..., description="time")
    precipitation: float = Field(..., description="precipitation")
    infiltration: float = Field(..., description="infiltration")
    urban_runoff: float = Field(..., description="urban_runoff")
    node_id: int = Field(..., description="node_id")
    potential_evaporation: float = Field(..., description="potential_evaporation")
    drainage: float = Field(..., description="drainage")


class FractionalFlowStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    node_id: int = Field(..., description="node_id")
    fraction: float = Field(..., description="fraction")
    control_state: Optional[str] = Field(None, description="control_state")


class LinearResistanceStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    node_id: int = Field(..., description="node_id")
    resistance: float = Field(..., description="resistance")
    control_state: Optional[str] = Field(None, description="control_state")


class ControlLogic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    truth_state: str = Field(..., description="truth_state")
    node_id: int = Field(..., description="node_id")
    control_state: str = Field(..., description="control_state")


class ManningResistanceStatic(BaseModel):
    length: float = Field(..., description="length")
    manning_n: float = Field(..., description="manning_n")
    remarks: Optional[str] = Field("", description="a hack for pandera")
    profile_width: float = Field(..., description="profile_width")
    node_id: int = Field(..., description="node_id")
    profile_slope: float = Field(..., description="profile_slope")
    control_state: Optional[str] = Field(None, description="control_state")


class FlowBoundaryStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    flow_rate: float = Field(..., description="flow_rate")
    node_id: int = Field(..., description="node_id")
    control_state: Optional[str] = Field(None, description="control_state")


class Node(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    fid: int = Field(..., description="fid")
    type: str = Field(..., description="type")


class TabulatedRatingCurveTime(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    time: datetime = Field(..., description="time")
    node_id: int = Field(..., description="node_id")
    discharge: float = Field(..., description="discharge")
    level: float = Field(..., description="level")


class TabulatedRatingCurveStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    node_id: int = Field(..., description="node_id")
    discharge: float = Field(..., description="discharge")
    level: float = Field(..., description="level")


class BasinState(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    storage: float = Field(..., description="storage")
    node_id: int = Field(..., description="node_id")


class BasinProfile(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    area: float = Field(..., description="area")
    storage: float = Field(..., description="storage")
    node_id: int = Field(..., description="node_id")
    level: float = Field(..., description="level")


class TerminalStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    node_id: int = Field(..., description="node_id")


class BasinStatic(BaseModel):
    remarks: Optional[str] = Field("", description="a hack for pandera")
    precipitation: float = Field(..., description="precipitation")
    infiltration: float = Field(..., description="infiltration")
    urban_runoff: float = Field(..., description="urban_runoff")
    node_id: int = Field(..., description="node_id")
    potential_evaporation: float = Field(..., description="potential_evaporation")
    drainage: float = Field(..., description="drainage")


class Root(BaseModel):
    ControlCondition: Optional[ControlCondition] = None
    Edge: Optional[Edge] = None
    PumpStatic: Optional[PumpStatic] = None
    LevelBoundaryStatic: Optional[LevelBoundaryStatic] = None
    BasinForcing: Optional[BasinForcing] = None
    FractionalFlowStatic: Optional[FractionalFlowStatic] = None
    LinearResistanceStatic: Optional[LinearResistanceStatic] = None
    ControlLogic: Optional[ControlLogic] = None
    ManningResistanceStatic: Optional[ManningResistanceStatic] = None
    FlowBoundaryStatic: Optional[FlowBoundaryStatic] = None
    Node: Optional[Node] = None
    TabulatedRatingCurveTime: Optional[TabulatedRatingCurveTime] = None
    TabulatedRatingCurveStatic: Optional[TabulatedRatingCurveStatic] = None
    BasinState: Optional[BasinState] = None
    BasinProfile: Optional[BasinProfile] = None
    TerminalStatic: Optional[TerminalStatic] = None
    BasinStatic: Optional[BasinStatic] = None
