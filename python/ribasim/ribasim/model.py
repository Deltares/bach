import datetime
from pathlib import Path
from typing import Any, Self

import tomli
import tomli_w
from matplotlib import pyplot as plt
from pydantic import (
    DirectoryPath,
    Field,
    FilePath,
    field_serializer,
    model_validator,
)

import ribasim
from ribasim.config import (
    Allocation,
    Basin,
    DiscreteControl,
    FlowBoundary,
    FractionalFlow,
    LevelBoundary,
    LinearResistance,
    ManningResistance,
    Outlet,
    PidControl,
    Pump,
    TabulatedRatingCurve,
    Terminal,
    UserDemand,
)
from ribasim.geometry.edge import Edge
from ribasim.input_base import (
    ChildModel,
    FileModel,
    NodeModel,
    context_file_loading,
)


class Model(FileModel):
    starttime: datetime.datetime
    endtime: datetime.datetime

    input_dir: Path = Field(default_factory=lambda: Path("."))
    results_dir: Path = Field(default_factory=lambda: Path("results"))

    allocation: Allocation = Field(default_factory=Allocation)
    basin: Basin = Field(default_factory=Basin)
    linear_resistance: LinearResistance = Field(default_factory=LinearResistance)
    manning_resistance: ManningResistance = Field(default_factory=ManningResistance)
    tabulated_rating_curve: TabulatedRatingCurve = Field(
        default_factory=TabulatedRatingCurve
    )
    fractional_flow: FractionalFlow = Field(default_factory=FractionalFlow)
    pump: Pump = Field(default_factory=Pump)
    level_boundary: LevelBoundary = Field(default_factory=LevelBoundary)
    flow_boundary: FlowBoundary = Field(default_factory=FlowBoundary)
    outlet: Outlet = Field(default_factory=Outlet)
    terminal: Terminal = Field(default_factory=Terminal)
    discrete_control: DiscreteControl = Field(default_factory=DiscreteControl)
    pid_control: PidControl = Field(default_factory=PidControl)
    user_demand: UserDemand = Field(default_factory=UserDemand)

    edge: Edge = Field(default_factory=Edge)

    @model_validator(mode="after")
    def set_node_parent(self) -> Self:
        for (
            k,
            v,
        ) in self.children().items():
            setattr(v, "_parent", self)
            setattr(v, "_parent_field", k)
        return self

    @field_serializer("input_dir", "results_dir")
    def serialize_path(self, path: Path) -> str:
        return str(path)

    def model_post_init(self, __context: Any) -> None:
        # Always write dir fields
        self.model_fields_set.update({"input_dir", "results_dir"})

    def __repr__(self) -> str:
        """Generate a succinct overview of the Model content.

        Skip "empty" NodeModel instances: when all dataframes are None.
        """
        content = ["ribasim.Model("]
        INDENT = "    "
        for field in self.fields():
            attr = getattr(self, field)
            content.append(f"{INDENT}{field}={repr(attr)},")

        content.append(")")
        return "\n".join(content)

    def _write_toml(self, fn: FilePath):
        fn = Path(fn)

        content = self.model_dump(exclude_unset=True, exclude_none=True, by_alias=True)
        # Filter empty dicts (default Nodes)
        content = dict(filter(lambda x: x[1], content.items()))
        content["ribasim_version"] = ribasim.__version__
        with open(fn, "wb") as f:
            tomli_w.dump(content, f)
        return fn

    def _save(self, directory: DirectoryPath, input_dir: DirectoryPath):
        db_path = directory / input_dir / "database.gpkg"
        db_path.parent.mkdir(parents=True, exist_ok=True)
        db_path.unlink(missing_ok=True)
        context_file_loading.get()["database"] = db_path
        self.edge._save(directory, input_dir)
        for sub in self.nodes().values():
            sub._save(directory, input_dir)

    def nodes(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), NodeModel)
        }

    def children(self):
        return {
            k: getattr(self, k)
            for k in self.model_fields.keys()
            if isinstance(getattr(self, k), ChildModel)
        }

    def validate_model_node_field_ids(self):
        raise NotImplementedError()

    def validate_model_node_ids(self):
        raise NotImplementedError()

    def validate_model(self):
        """Validate the model.

        Checks:
        - Whether the node IDs of the node_type fields are valid
        - Whether the node IDs in the node field correspond to the node IDs on the node type fields
        """

        self.validate_model_node_field_ids()
        self.validate_model_node_ids()

    @classmethod
    def read(cls, filepath: FilePath) -> "Model":
        """Read model from TOML file."""
        return cls(filepath=filepath)  # type: ignore

    def write(self, filepath: Path | str) -> Path:
        """
        Write the contents of the model to disk and save it as a TOML configuration file.

        If ``filepath.parent`` does not exist, it is created before writing.

        Parameters
        ----------
        filepath: FilePath ending in .toml
        """
        # TODO
        # self.validate_model()
        filepath = Path(filepath)
        if not filepath.suffix == ".toml":
            raise ValueError(f"Filepath '{filepath}' is not a .toml file.")
        context_file_loading.set({})
        filepath = Path(filepath)
        directory = filepath.parent
        directory.mkdir(parents=True, exist_ok=True)
        self._save(directory, self.input_dir)
        fn = self._write_toml(filepath)

        context_file_loading.set({})
        return fn

    @classmethod
    def _load(cls, filepath: Path | None) -> dict[str, Any]:
        context_file_loading.set({})

        if filepath is not None:
            with open(filepath, "rb") as f:
                config = tomli.load(f)

            context_file_loading.get()["directory"] = filepath.parent / config.get(
                "input_dir", "."
            )
            return config
        else:
            return {}

    @model_validator(mode="after")
    def reset_contextvar(self) -> Self:
        # Drop database info
        context_file_loading.set({})
        return self

    def plot_control_listen(self, ax):
        raise NotImplementedError()

    def plot(self, ax=None, indicate_subnetworks: bool = True) -> Any:
        """
        Plot the nodes, edges and allocation networks of the model.

        Parameters
        ----------
        ax : matplotlib.pyplot.Artist, optional
            Axes on which to draw the plot.

        Returns
        -------
        ax : matplotlib.pyplot.Artist
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        self.edge.plot(ax=ax, zorder=2)
        for node in self.nodes().values():
            node.node.plot(ax=ax, zorder=3)
        # TODO
        # self.plot_control_listen(ax)
        # self.node.plot(ax=ax, zorder=3)

        handles, labels = ax.get_legend_handles_labels()

        # TODO
        # if indicate_subnetworks:
        #     (
        #         handles_subnetworks,
        #         labels_subnetworks,
        #     ) = self.network.node.plot_allocation_networks(ax=ax, zorder=1)
        #     handles += handles_subnetworks
        #     labels += labels_subnetworks

        ax.legend(handles, labels, loc="lower left", bbox_to_anchor=(1, 0.5))

        return ax

    def print_discrete_control_record(self, path: FilePath) -> None:
        raise NotImplementedError()
