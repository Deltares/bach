import multiprocessing
import shutil
from functools import partial
from pathlib import Path

import ribasim_testmodels
from alive_progress import alive_bar


def generate_model(args, datadir):
    model_name, model_constructor = args
    model = model_constructor()
    model.write(datadir / model_name / "ribasim.toml")
    return model_name


if __name__ == "__main__":
    datadir = Path("generated_testmodels")
    if datadir.is_dir():
        shutil.rmtree(datadir, ignore_errors=True)

    datadir.mkdir(exist_ok=True)
    readme = datadir / "README.md"
    readme.write_text(
        """\
# Ribasim testmodels

The content of this directory are generated testmodels for Ribasim
Don't put important stuff in here, it will be emptied for every run."""
    )

    generate_model_partial = partial(generate_model, datadir=datadir)

    testmodels = list(ribasim_testmodels.constructors.items())
    with alive_bar(len(testmodels)) as bar, multiprocessing.Pool() as p:
        for model_name in p.imap_unordered(generate_model_partial, testmodels):
            print(f"Generated {model_name}")
            bar()
