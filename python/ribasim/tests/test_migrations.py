from pathlib import Path

import pytest
from ribasim import Model
from ribasim.db_utils import _get_db_schema_version

root_folder = Path(__file__).parent.parent.parent.parent
print(root_folder)


@pytest.mark.regression
def test_hws_migration():
    toml_path = root_folder / "models/hws_migration_test/hws.toml"
    db_path = root_folder / "models/hws_migration_test/database.gpkg"

    assert (
        toml_path.exists()
    ), "Can't find the model, did you retrieve it with get_benchmark.py?"

    assert _get_db_schema_version(db_path) == 0
    Model.read(toml_path)
