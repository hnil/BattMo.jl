# # Chen 2020 DFN Model with Thermal Effects – BattMo.jl vs PyBaMM
#
# This example extends the basic Chen 2020 comparison by enabling thermal
# effects in both frameworks:
#   - BattMo.jl: Arrhenius temperature dependence
#   - PyBaMM: lumped thermal model
#
# Discharge curves are compared at two temperatures (25 °C and 10 °C) to
# show the impact of temperature on cell performance.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall:
# ```julia
# using CondaPkg; CondaPkg.add_pip("pybamm")
# ```

using BattMo
using GLMakie

# ### 1. Define temperatures
temperatures_C = [25.0, 10.0]
colors_battmo = [:blue, :green]
colors_pybamm = [:red, :orange]

fig = Figure(size = (1000, 500))
ax = Axis(fig[1, 1];
	title  = "Chen 2020 with Thermal Effects – 1C CC Discharge",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

for (i, T_C) in enumerate(temperatures_C)
	T_K = T_C + 273.15

	# --- BattMo.jl with Arrhenius temperature dependence ---
	model_settings = load_model_settings(; from_default_set = "p2d")
	model_settings["TemperatureDependence"] = "Arrhenius"

	cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
	cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
	simulation_settings = load_simulation_settings(; from_default_set = "p2d")

	cycling_protocol["DRate"] = 1.0
	cycling_protocol["InitialTemperature"] = T_K

	model_setup = LithiumIonBattery(; model_settings)
	sim = Simulation(model_setup, cell_parameters, cycling_protocol; simulation_settings)
	output_battmo = solve(sim; info_level = -1)

	time_battmo = output_battmo.time_series["Time"]
	voltage_battmo = output_battmo.time_series["Voltage"]

	# --- PyBaMM with lumped thermal model ---
	t_end = 3700.0
	t_eval = collect(range(0.0, t_end; length = 200))

	result_pybamm = run_pybamm(;
		model_name    = "DFN",
		parameter_set = "Chen2020",
		C_rate        = 1.0,
		thermal       = true,
		temperature   = T_K,
		t_eval        = t_eval,
	)

	# --- Plot ---
	T_label = "$(Int(T_C)) °C"
	lines!(ax, time_battmo, voltage_battmo;
		color = colors_battmo[i], linewidth = 2,
		label = "BattMo.jl $T_label")
	lines!(ax, result_pybamm.time, result_pybamm.voltage;
		color = colors_pybamm[i], linewidth = 2, linestyle = :dash,
		label = "PyBaMM $T_label")
end

axislegend(ax; position = :rb)

fig
