import pytest
import ribasim
import ribasim_testmodels


# we can't call fixtures directly, so we keep separate versions
@pytest.fixture()
def basic() -> ribasim.Model:
    return ribasim_testmodels.basic_model()


@pytest.fixture()
def basic_arrow() -> ribasim.Model:
    return ribasim_testmodels.basic_arrow_model()


@pytest.fixture()
def basic_transient() -> ribasim.Model:
    return ribasim_testmodels.basic_transient_model()


@pytest.fixture()
def tabulated_rating_curve() -> ribasim.Model:
    return ribasim_testmodels.tabulated_rating_curve_model()


@pytest.fixture()
def backwater() -> ribasim.Model:
    return ribasim_testmodels.backwater_model()


@pytest.fixture()
def discrete_control_of_pid_control() -> ribasim.Model:
    return ribasim_testmodels.discrete_control_of_pid_control_model()


@pytest.fixture()
def subnetwork() -> ribasim.Model:
    return ribasim_testmodels.subnetwork_model()


@pytest.fixture()
def main_network_with_subnetworks() -> ribasim.Model:
    return ribasim_testmodels.main_network_with_subnetworks_model()


def level_setpoint_with_minmax() -> ribasim.Model:
    return ribasim_testmodels.level_setpoint_with_minmax_model()
