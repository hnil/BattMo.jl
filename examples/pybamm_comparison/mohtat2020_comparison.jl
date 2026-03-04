# # Mohtat 2020 Parameter Set – BattMo.jl vs PyBaMM Comparison
#
# This example compares discharge curves between BattMo.jl (Chen 2020) and
# PyBaMM (Mohtat 2020) at multiple C-rates.
#
# The Mohtat 2020 parameter set is available in PyBaMM's standard library but
# not yet in BattMo.jl, so BattMo.jl uses the Chen 2020 set as a reference.
# The comparison illustrates the differences between the two cell
# parameterisations and how each framework handles the DFN model.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.

using BattMo
using GLMakie

c_rates = [0.5, 1.0, 2.0]
colors  = [:blue, :green, :purple]

fig = Figure(size = (1000, 500))
ax = Axis(fig[1, 1];
	title  = "Mohtat 2020 (PyBaMM) vs Chen 2020 (BattMo.jl) – CC Discharge",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

for (i, Crate) in enumerate(c_rates)
	# --- BattMo.jl with Chen 2020 ---
	cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
	cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
	cycling_protocol["DRate"] = Crate

	model = LithiumIonBattery()
	sim = Simulation(model, cell_parameters, cycling_protocol)
	output_battmo = solve(sim; info_level = -1)

	time_battmo = output_battmo.time_series["Time"]
	voltage_battmo = output_battmo.time_series["Voltage"]

	# --- PyBaMM with Mohtat 2020 ---
	t_end = 3700.0 / Crate
	n_points = max(200, round(Int, t_end / 10.0))
	t_eval = collect(range(0.0, t_end; length = n_points))

	result_pybamm = run_pybamm(;
		model_name    = "DFN",
		parameter_set = "Mohtat2020",
		C_rate        = Crate,
		t_eval        = t_eval,
	)

	# --- Plot ---
	lines!(ax, time_battmo, voltage_battmo;
		color = colors[i], linewidth = 2,
		label = "BattMo Chen2020 $(Crate)C")
	lines!(ax, result_pybamm.time, result_pybamm.voltage;
		color = colors[i], linewidth = 2, linestyle = :dash,
		label = "PyBaMM Mohtat2020 $(Crate)C")
end

axislegend(ax; position = :rb)

fig
