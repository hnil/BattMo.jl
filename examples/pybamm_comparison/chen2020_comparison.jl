# # Chen 2020 DFN Model – BattMo.jl vs PyBaMM Comparison
#
# This example runs the Chen 2020 DFN (Doyle-Fuller-Newman) model in both
# **BattMo.jl** and **PyBaMM** (called from Julia via PythonCall) and compares
# the resulting discharge-voltage curves.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall:
# ```julia
# using CondaPkg; CondaPkg.add_pip("pybamm")
# ```

using BattMo
using GLMakie

# ### 1. Run BattMo.jl simulation
Crate = 2.70001  # Set to 0.5C discharge
dt_org=3600.0*1.5/500.0
simulation_input = load_full_simulation_input(; from_default_set = "chen_2020")
simulation_input["CyclingProtocol"]["DRate"] = Crate  # Set to 0.5C discharge
#dt_org = simulation_input["SimulationSettings"]["TimeStepDuration"]
simulation_input["SimulationSettings"]["TimeStepDuration"]  = dt_org/Crate
simulation_input["SimulationSettings"]["RampUpTime"] = 10.0/Crate
output_battmo = run_simulation(simulation_input; accept_invalid = true, info_level = -1	)

# Extract BattMo time series
states_battmo = output_battmo.jutul_output[:states]
time_battmo = [state[:Control][:Controller].time for state in states_battmo]
voltage_battmo = [state[:Control][:ElectricPotential][1] for state in states_battmo]
current_battmo = [state[:Control][:Current][1] for state in states_battmo]

# ### 2. Run PyBaMM simulation (Chen2020 DFN, 1C discharge)
result_pybamm = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = Crate)

# ### 3. Compare discharge voltage curves
fig = Figure(size = (900, 500))

ax = Axis(fig[1, 1];
	title  = "Chen 2020 – 1C CC Discharge: BattMo.jl vs PyBaMM",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

lines!(ax, time_battmo, voltage_battmo; color = :blue, linewidth = 2, label = "BattMo.jl")
lines!(ax, result_pybamm.time, result_pybamm.voltage; color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM")

axislegend(ax; position = :rb)

fig
