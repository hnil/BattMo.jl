# # Chayambuka 2022 Sodium-Ion – BattMo.jl vs PyBaMM Comparison
#
# This example demonstrates the Chayambuka 2022 sodium-ion parameter set in
# BattMo.jl at several C-rates and compares the discharge curves with PyBaMM's
# Chen 2020 lithium-ion parameter set as a reference.
#
# The Chayambuka 2022 set models a hard-carbon-based sodium-ion cell.  PyBaMM
# does not include sodium-ion parameter sets in its standard library, so the
# comparison highlights differences between the Na-ion chemistry (BattMo.jl) and
# a representative Li-ion chemistry (PyBaMM Chen 2020).
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.

using BattMo
using GLMakie

c_rates = [0.1, 0.5, 1.0]
colors  = [:blue, :green, :purple]

fig = Figure(size = (1000, 500))
ax = Axis(fig[1, 1];
	title  = "Chayambuka 2022 Na-ion (BattMo.jl) vs Chen 2020 Li-ion (PyBaMM)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

for (i, Crate) in enumerate(c_rates)
	# --- BattMo.jl with Chayambuka 2022 (sodium ion) ---
	cell_parameters = load_cell_parameters(; from_default_set = "chayambuka_2022")
	cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
	model_settings = load_model_settings(; from_default_set = "p2d")
	simulation_settings = load_simulation_settings(; from_default_set = "p2d")

	model_settings["ButlerVolmer"] = "Chayambuka"
	cycling_protocol["DRate"] = Crate
	cycling_protocol["LowerVoltageLimit"] = 2.0
	cycling_protocol["UpperVoltageLimit"] = 4.2

	simulation_settings["NegativeElectrodeCoatingGridPoints"] = 8
	simulation_settings["PositiveElectrodeCoatingGridPoints"] = 50
	simulation_settings["NegativeElectrodeParticleGridPoints"] = 50
	simulation_settings["PositiveElectrodeParticleGridPoints"] = 50
	simulation_settings["SeparatorGridPoints"] = 5

	model = SodiumIonBattery(; model_settings)
	sim = Simulation(model, cell_parameters, cycling_protocol; simulation_settings)
	output_battmo = solve(sim; info_level = -1)

	time_battmo = output_battmo.time_series["Time"]
	voltage_battmo = output_battmo.time_series["Voltage"]

	# --- PyBaMM with Chen 2020 (reference, Li-ion) ---
	t_end = 3700.0 / Crate
	n_points = max(200, round(Int, t_end / 10.0))
	t_eval = collect(range(0.0, t_end; length = n_points))

	result_pybamm = run_pybamm(;
		model_name    = "DFN",
		parameter_set = "Chen2020",
		C_rate        = Crate,
		t_eval        = t_eval,
	)

	# --- Plot ---
	lines!(ax, time_battmo, voltage_battmo;
		color = colors[i], linewidth = 2,
		label = "BattMo Na-ion $(Crate)C")
	lines!(ax, result_pybamm.time, result_pybamm.voltage;
		color = colors[i], linewidth = 2, linestyle = :dash,
		label = "PyBaMM Li-ion $(Crate)C")
end

axislegend(ax; position = :rb)

fig
