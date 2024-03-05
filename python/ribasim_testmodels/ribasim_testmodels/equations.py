import numpy as np
from ribasim.config import Node, Solver
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    flow_boundary,
    fractional_flow,
    level_boundary,
    linear_resistance,
    manning_resistance,
    pid_control,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def linear_resistance_model() -> Model:
    """Set up a minimal model which uses a linear_resistance node."""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(area=100.0, level=[0.0, 10.0]), basin.State(level=[10.0])],
    )
    model.linear_resistance.add(
        Node(2, Point(1, 0)),
        [linear_resistance.Static(resistance=[5e4], max_flow_rate=[6e-5])],
    )
    model.level_boundary.add(Node(3, Point(2, 0)), [level_boundary.Static(level=[5.0])])

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.linear_resistance[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.linear_resistance[2],
        to_node=model.level_boundary[3],
        edge_type="flow",
    )

    return model


def rating_curve_model() -> Model:
    """Set up a minimal model which uses a tabulated_rating_curve node."""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0]),
            basin.State(level=[10.5]),
        ],
    )

    level_min = 1.0
    level = np.linspace(0, 12, 100)
    flow_rate = np.square(level - level_min) / (60 * 60 * 24)
    model.tabulated_rating_curve.add(
        Node(2, Point(1, 0)),
        [tabulated_rating_curve.Static(level=level, flow_rate=flow_rate)],
    )

    model.terminal.add(Node(3, Point(2, 0)))

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.tabulated_rating_curve[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.tabulated_rating_curve[2],
        to_node=model.terminal[3],
        edge_type="flow",
    )

    return model


def manning_resistance_model() -> Model:
    """Set up a minimal model which uses a manning_resistance node."""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    basin_profile = basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0])

    model.basin.add(Node(1, Point(0, 0)), [basin_profile, basin.State(level=[9.5])])
    model.manning_resistance.add(
        Node(2, Point(1, 0)),
        [
            manning_resistance.Static(
                manning_n=[1e7], profile_width=50.0, profile_slope=0.0, length=2000.0
            )
        ],
    )
    model.basin.add(Node(3, Point(2, 0)), [basin_profile, basin.State(level=[4.5])])

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.manning_resistance[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.manning_resistance[2],
        to_node=model.basin[3],
        edge_type="flow",
    )

    return model


def misc_nodes_model() -> Model:
    """Set up a minimal model using flow_boundary, fractional_flow and pump nodes."""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        solver=Solver(dt=24 * 60 * 60, algorithm="Euler"),
    )

    basin_shared = [
        basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0]),
        basin.State(level=[10.5]),
    ]

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[3e-4])]
    )
    model.fractional_flow.add(
        Node(2, Point(0, 1)), [fractional_flow.Static(fraction=[0.5])]
    )
    model.basin.add(Node(3, Point(0, 2)), basin_shared)
    model.pump.add(Node(4, Point(0, 3)), [pump.Static(flow_rate=[1e-4])])
    model.basin.add(Node(5, Point(0, 4)), basin_shared)
    model.fractional_flow.add(
        Node(6, Point(1, 0)), [fractional_flow.Static(fraction=[0.5])]
    )
    model.terminal.add(Node(7, Point(2, 0)))

    model.edge.add(
        from_node=model.flow_boundary[1],
        to_node=model.fractional_flow[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.fractional_flow[2],
        to_node=model.basin[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.basin[3],
        to_node=model.pump[4],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[4],
        to_node=model.basin[5],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.flow_boundary[1],
        to_node=model.fractional_flow[6],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.fractional_flow[6],
        to_node=model.terminal[7],
        edge_type="flow",
    )

    return model


def pid_control_equation_model() -> Model:
    """Set up a model with pid control for an analytical solution test"""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2020-01-01 00:05:00",
    )
    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0]),
            basin.State(level=[10.5]),
        ],
    )
    # Pump flow_rate will be overwritten by the PidControl
    model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.0])])
    model.terminal.add(Node(3, Point(2, 0)))
    model.pid_control.add(
        Node(4, Point(0.5, 1)),
        [
            pid_control.Static(
                listen_node_id=[1],
                target=10.0,
                proportional=-2.5,
                integral=-0.001,
                derivative=10.0,
            )
        ],
    )

    model.edge.add(
        from_node=model.basin[1],
        to_node=model.pump[2],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pump[2],
        to_node=model.terminal[3],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.pid_control[4],
        to_node=model.pump[2],
        edge_type="control",
    )

    return model
