# # Chen 2020 DFN Model with SEI – Multi-Cycle Comparison (BattMo.jl vs PyBaMM)
#
# This example compares SEI layer growth during **multiple charge–discharge
# cycles** as modelled by BattMo.jl (Bolay SEI model) and PyBaMM
# (reaction-limited SEI model).
#
# BattMo.jl uses a CCCV cycling protocol, while PyBaMM uses an equivalent
# Experiment specification.  Both run 5 full cycles so the cumulative SEI
# thickness growth can be compared across cycles.
#
# **Note:** The BattMo and PyBaMM SEI models are based on different formulations
# and parameter sets, so the results are expected to differ.  This example is
# intended to show how to set up and visualise a multi-cycle SEI comparison.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.
# The CondaPkg.toml shipped with this repository handles this automatically.

using BattMo
using GLMakie

n_cycles = 5

# ### 1. Run BattMo.jl – CCCV cycling with SEI (Bolay model)
cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol = load_cycling_protocol(; from_default_set = "cccv")
model_settings = load_model_settings(; from_default_set = "p2d")
simulation_settings = load_simulation_settings(; from_default_set = "p2d")

model_settings["SEIModel"] = "Bolay"
cycling_protocol["TotalNumberOfCycles"] = n_cycles

model_setup = LithiumIonBattery(; model_settings)
sim = Simulation(model_setup, cell_parameters, cycling_protocol; simulation_settings)
output_battmo = solve(sim; info_level = 1)

time_battmo = output_battmo.time_series["Time"]
voltage_battmo = output_battmo.time_series["Voltage"]
sei_thickness_battmo = output_battmo.states["SEIThickness"][:, 1]

# ### 2. Run PyBaMM – Equivalent CCCV cycling with reaction-limited SEI
#
# PyBaMM's Experiment API is used to define the same CCCV protocol.
# The voltage limits are matched to the BattMo CCCV defaults (3.0 – 4.0 V).

experiment_steps = repeat([
	"Charge at 1C until 4.0 V",
	"Hold at 4.0 V until C/50",
	"Discharge at 1C until 3.0 V",
], n_cycles)

result_pybamm = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	initial_soc=0.01,
	sei           = true,
	experiment    = experiment_steps,
)

# ### 3. Compare voltage curves over multiple cycles
fig = Figure(size = (1200, 900))

ax1 = Axis(fig[1, 1];
	title  = "Chen 2020 with SEI – $(n_cycles)-Cycle Voltage Comparison",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

lines!(ax1, time_battmo, voltage_battmo;
	color = :blue, linewidth = 2,
	label = "BattMo.jl (Bolay SEI, CCCV)")
lines!(ax1, result_pybamm.time, result_pybamm.voltage;
	color = :red, linewidth = 2, linestyle = :dash,
	label = "PyBaMM (reaction-limited SEI, CCCV)")
axislegend(ax1; position = :rb)

# ### 4. Compare SEI thickness evolution
ax2 = Axis(fig[2, 1];
	title  = "SEI Thickness Growth – $(n_cycles) Cycles",
	xlabel = "Time [s]",
	ylabel = "SEI Thickness [m]",
)

lines!(ax2, time_battmo, sei_thickness_battmo;
	color = :blue, linewidth = 2,
	label = "BattMo.jl (Bolay)")
if !isnothing(result_pybamm.sei_thickness)
	lines!(ax2, result_pybamm.time, result_pybamm.sei_thickness;
		color = :red, linewidth = 2, linestyle = :dash,
		label = "PyBaMM (reaction-limited)")
end
axislegend(ax2; position = :rb)

# ### 5. Compare current profiles
ax3 = Axis(fig[3, 1];
	title  = "Current Profile – $(n_cycles) Cycles",
	xlabel = "Time [s]",
	ylabel = "Current [A]",
)

lines!(ax3, time_battmo, output_battmo.time_series["Current"];
	color = :blue, linewidth = 2,
	label = "BattMo.jl")
lines!(ax3, result_pybamm.time, result_pybamm.current;
	color = :red, linewidth = 2, linestyle = :dash,
	label = "PyBaMM")
axislegend(ax3; position = :rb)

fig
