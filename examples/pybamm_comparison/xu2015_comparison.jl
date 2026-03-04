# # Xu 2015 Parameter Set – BattMo.jl vs PyBaMM Comparison
#
# This example runs the Xu 2015 (LP2770120 prismatic LiFePO₄/graphite)
# parameter set in BattMo.jl at multiple C-rates and compares the discharge
# curves with PyBaMM's Chen 2020 parameter set as a reference.
#
# The Xu 2015 set is available in BattMo.jl but not in PyBaMM's standard
# library, so the comparison highlights differences between the two
# chemistries / cell designs rather than a direct framework-to-framework
# comparison with identical parameters.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.

using BattMo
using GLMakie

c_rates = [0.5, 1.0, 2.0]
colors  = [:blue, :green, :purple]

fig = Figure(size = (1000, 500))
ax = Axis(fig[1, 1];
	title  = "Xu 2015 (BattMo.jl) vs Chen 2020 (PyBaMM) – CC Discharge",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

for (i, Crate) in enumerate(c_rates)
	# --- BattMo.jl with Xu 2015 ---
	cell_parameters = load_cell_parameters(; from_default_set = "xu_2015")
	cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
	cycling_protocol["DRate"] = Crate

	model = LithiumIonBattery()
	sim = Simulation(model, cell_parameters, cycling_protocol)
	output_battmo = solve(sim; info_level = -1)

	time_battmo = output_battmo.time_series["Time"]
	voltage_battmo = output_battmo.time_series["Voltage"]

	# --- PyBaMM with Chen 2020 (reference) ---
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
		label = "BattMo Xu2015 $(Crate)C")
	lines!(ax, result_pybamm.time, result_pybamm.voltage;
		color = colors[i], linewidth = 2, linestyle = :dash,
		label = "PyBaMM Chen2020 $(Crate)C")
end

axislegend(ax; position = :rb)

fig
