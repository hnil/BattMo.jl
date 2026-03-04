# # Control Protocol Comparison – BattMo.jl vs PyBaMM
#
# This example compares BattMo.jl and PyBaMM across **several control
# protocols** to show how each framework handles different operating modes:
#
# 1. **CC discharge** – constant-current discharge at 1C
# 2. **CC cycling** – constant-current charge/discharge for 3 cycles
# 3. **CCCV cycling** – constant-current–constant-voltage for 3 cycles
# 4. **Multi-cycle CCCV** – 10 full CCCV cycles (long-duration test)
#
# All simulations use the Chen 2020 parameter set in both frameworks.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall.

using BattMo
using GLMakie

fig = Figure(size = (1200, 1000))

# ─────────────────────────────────────────────────────────────────────────────
# ### 1. CC Discharge (1C)
# ─────────────────────────────────────────────────────────────────────────────

cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")
cycling_protocol["DRate"] = 1.0

model = LithiumIonBattery()
sim = Simulation(model, cell_parameters, cycling_protocol)
out_cc = solve(sim; info_level = -1)

t_end = 3700.0
t_eval = collect(range(0.0, t_end; length = 200))
res_cc = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	C_rate        = 1.0,
	t_eval        = t_eval,
)

ax1 = Axis(fig[1, 1];
	title  = "CC Discharge (1C)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)
lines!(ax1, out_cc.time_series["Time"], out_cc.time_series["Voltage"];
	color = :blue, linewidth = 2, label = "BattMo.jl")
lines!(ax1, res_cc.time, res_cc.voltage;
	color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM")
axislegend(ax1; position = :rb)

# ─────────────────────────────────────────────────────────────────────────────
# ### 2. CC Cycling (3 cycles)
# ─────────────────────────────────────────────────────────────────────────────

cell_parameters_cc = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol_cc = load_cycling_protocol(; from_default_set = "cc_cycling")
cycling_protocol_cc["TotalNumberOfCycles"] = 3

sim_cc = Simulation(LithiumIonBattery(), cell_parameters_cc, cycling_protocol_cc)
out_cc_cyc = solve(sim_cc; info_level = -1)

res_cc_cyc = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	experiment    = repeat([
		"Charge at 0.5C until 4.1 V",
		"Discharge at 0.5C until 2.5 V",
	], 3),
)

ax2 = Axis(fig[1, 2];
	title  = "CC Cycling (3 cycles)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)
lines!(ax2, out_cc_cyc.time_series["Time"], out_cc_cyc.time_series["Voltage"];
	color = :blue, linewidth = 2, label = "BattMo.jl")
lines!(ax2, res_cc_cyc.time, res_cc_cyc.voltage;
	color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM")
axislegend(ax2; position = :rb)

# ─────────────────────────────────────────────────────────────────────────────
# ### 3. CCCV Cycling (3 cycles)
# ─────────────────────────────────────────────────────────────────────────────

cell_parameters_cccv = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol_cccv = load_cycling_protocol(; from_default_set = "cccv")
cycling_protocol_cccv["TotalNumberOfCycles"] = 3

sim_cccv = Simulation(LithiumIonBattery(), cell_parameters_cccv, cycling_protocol_cccv)
out_cccv = solve(sim_cccv; info_level = -1)

res_cccv = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	experiment    = repeat([
		"Charge at 1C until 4.0 V",
		"Hold at 4.0 V until C/50",
		"Discharge at 1C until 3.0 V",
	], 3),
)

ax3 = Axis(fig[2, 1];
	title  = "CCCV Cycling (3 cycles)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)
lines!(ax3, out_cccv.time_series["Time"], out_cccv.time_series["Voltage"];
	color = :blue, linewidth = 2, label = "BattMo.jl")
lines!(ax3, res_cccv.time, res_cccv.voltage;
	color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM")
axislegend(ax3; position = :rb)

# ─────────────────────────────────────────────────────────────────────────────
# ### 4. Multi-Cycle CCCV (10 cycles)
# ─────────────────────────────────────────────────────────────────────────────

cell_parameters_mc = load_cell_parameters(; from_default_set = "chen_2020")
cycling_protocol_mc = load_cycling_protocol(; from_default_set = "cccv")
cycling_protocol_mc["TotalNumberOfCycles"] = 10

sim_mc = Simulation(LithiumIonBattery(), cell_parameters_mc, cycling_protocol_mc)
out_mc = solve(sim_mc; info_level = -1)

res_mc = run_pybamm(;
	model_name    = "DFN",
	parameter_set = "Chen2020",
	experiment    = repeat([
		"Charge at 1C until 4.0 V",
		"Hold at 4.0 V until C/50",
		"Discharge at 1C until 3.0 V",
	], 10),
)

ax4 = Axis(fig[2, 2];
	title  = "Multi-Cycle CCCV (10 cycles)",
	xlabel = "Time [s]",
	ylabel = "Voltage [V]",
)
lines!(ax4, out_mc.time_series["Time"], out_mc.time_series["Voltage"];
	color = :blue, linewidth = 2, label = "BattMo.jl")
lines!(ax4, res_mc.time, res_mc.voltage;
	color = :red, linewidth = 2, linestyle = :dash, label = "PyBaMM")
axislegend(ax4; position = :rb)

fig
