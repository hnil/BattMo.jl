# # Chen 2020 DFN Model – BattMo.jl vs PyBaMM Comparison (Multiple C-Rates)
#
# This example runs the Chen 2020 DFN (Doyle-Fuller-Newman) model in both
# **BattMo.jl** and **PyBaMM** (called from Julia via PythonCall) at multiple
# C-rates and compares the resulting discharge-voltage curves.  The time stepping
# and protocol are set to be equivalent between the two frameworks, and the
# simulations run into the voltage cutoff region.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall:
# ```julia
# using CondaPkg; CondaPkg.add_pip("pybamm")
# ```

using BattMo
using GLMakie

# ### 1. Define C-rates to compare
c_rates = [0.5, 1.0, 2.0]
colors = [:blue, :green, :purple]

# ### 2. Run simulations at each C-rate
fig = Figure(size = (1000, 500))
ax = Axis(fig[1, 1];
	title  = "Chen 2020 – CC Discharge: BattMo.jl vs PyBaMM",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

for (i, Crate) in enumerate(c_rates)
	# --- BattMo.jl ---
	cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
	cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
	cycling_protocol["DRate"] = Crate

	model = LithiumIonBattery()
	sim = Simulation(model, cell_parameters, cycling_protocol)
	output_battmo = solve(sim; info_level = -1)

	time_battmo = output_battmo.time_series["Time"]
	voltage_battmo = output_battmo.time_series["Voltage"]

	# --- PyBaMM ---
	# Use equivalent time evaluation points so both frameworks are sampled the
	# same way.  The time span extends beyond 1/C hours to capture the voltage
	# cutoff region.
	t_end = 3700.0 / Crate
	dt_fixed = 10.0
	n_points = max(200, round(Int, t_end / dt_fixed))
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
		label = "BattMo.jl $(Crate)C")
	lines!(ax, result_pybamm.time, result_pybamm.voltage;
		color = colors[i], linewidth = 2, linestyle = :dash,
		label = "PyBaMM $(Crate)C")
end

axislegend(ax; position = :rb)

fig
