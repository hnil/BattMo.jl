# # Chen 2020 DFN Model with Thermal Effects – BattMo.jl vs PyBaMM
#
# This example extends the basic Chen 2020 comparison by enabling thermal
# coupling (lumped thermal model) in both frameworks.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall:
# ```julia
# using CondaPkg; CondaPkg.add_pip("pybamm")
# ```

using BattMo
using GLMakie

# ### 1. Run BattMo.jl simulation with Arrhenius temperature dependence
model_settings = load_model_settings(; from_default_set = "p2d")
model_settings["TemperatureDependence"] = "Arrhenius"

cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
simulation_settings = load_simulation_settings(; from_default_set = "p2d")
solver_settings = load_solver_settings(; from_default_set = "direct")

model_setup = LithiumIonBattery(; model_settings)
sim = Simulation(model_setup, cell_parameters, cycling_protocol; simulation_settings)
output_battmo = solve(sim)

states_battmo = output_battmo[:states]
time_battmo = [state[:Control][:Controller].time for state in states_battmo]
voltage_battmo = [state[:Control][:ElectricPotential][1] for state in states_battmo]

# ### 2. Run PyBaMM simulation with lumped thermal model
result_pybamm = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	C_rate        = 1.0,
	thermal       = true,
)

# ### 3. Compare discharge voltage curves
fig = Figure(size = (900, 500))

ax = Axis(fig[1, 1];
	title  = "Chen 2020 with Thermal Effects – 1C CC Discharge",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

lines!(ax, time_battmo, voltage_battmo; color = :blue, linewidth = 2, label = "BattMo.jl (Arrhenius)")
lines!(ax, result_pybamm.time, result_pybamm.voltage; color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM (lumped thermal)")

axislegend(ax; position = :rb)

fig
