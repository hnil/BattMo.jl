# # Chen 2020 DFN Model with SEI Formation – BattMo.jl vs PyBaMM
#
# This example compares SEI layer growth during a CC discharge as modelled by
# BattMo.jl (Bolay SEI model) and PyBaMM (reaction-limited SEI model).
#
# Both frameworks use the same CC discharge protocol for a fair comparison.
# The voltage and SEI thickness evolution are plotted side-by-side.
#
# **Note:** The BattMo and PyBaMM SEI models are based on different formulations
# and use different parameter sets, so the results are expected to differ.  This
# example is intended to show how to run both and visualise them side-by-side.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.
# The CondaPkg.toml shipped with this repository handles this automatically.

using BattMo
using GLMakie

# ### 1. Run BattMo.jl simulation with SEI (Bolay model, CC discharge)
cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
model_settings = load_model_settings(; from_default_set = "p2d")
simulation_settings = load_simulation_settings(; from_default_set = "p2d")

model_settings["SEIModel"] = "Bolay"
cycling_protocol["DRate"] = 1.0

model_setup = LithiumIonBattery(; model_settings)
sim = Simulation(model_setup, cell_parameters, cycling_protocol; simulation_settings)
output_battmo = solve(sim; info_level = -1)

time_battmo = output_battmo.time_series["Time"]
voltage_battmo = output_battmo.time_series["Voltage"]
sei_thickness_battmo = output_battmo.states["SEIThickness"][:, 1]

# ### 2. Run PyBaMM simulation with SEI (reaction-limited, CC discharge)
t_end = 3700.0
t_eval = collect(range(0.0, t_end; length = 200))

result_pybamm = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	C_rate        = 1.0,
	thermal       = false,
	sei           = true,
	t_eval        = t_eval,
)

# ### 3. Compare discharge voltage curves
fig = Figure(size = (1000, 800))

ax1 = Axis(fig[1, 1];
	title  = "Chen 2020 with SEI – Voltage Comparison (1C CC Discharge)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)

lines!(ax1, time_battmo, voltage_battmo; color = :blue, linewidth = 2, label = "BattMo.jl (Bolay SEI)")
lines!(ax1, result_pybamm.time, result_pybamm.voltage; color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM (reaction-limited SEI)")
axislegend(ax1; position = :rb)

# ### 4. Plot SEI thickness evolution from both frameworks
ax2 = Axis(fig[2, 1];
	title  = "SEI Thickness – BattMo.jl vs PyBaMM",
	xlabel = "Time [s]",
	ylabel = "SEI Thickness [m]",
)

lines!(ax2, time_battmo, sei_thickness_battmo; color = :blue, linewidth = 2, label = "BattMo.jl (Bolay)")
if !isnothing(result_pybamm.sei_thickness)
	lines!(ax2, result_pybamm.time, result_pybamm.sei_thickness; color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM (reaction-limited)")
end
axislegend(ax2; position = :rb)

fig
