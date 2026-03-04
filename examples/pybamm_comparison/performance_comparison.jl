# # Performance Comparison – BattMo.jl vs PyBaMM
#
# This example benchmarks the wall-clock time for a Chen 2020 DFN 1C
# CC-discharge simulation in both frameworks.  First calls are included to
# trigger compilation / JIT warm-up, then the timing measurements are repeated.
#
# ## Prerequisites
# PyBaMM must be installed in the Python environment used by PythonCall:
# ```julia
# using CondaPkg; CondaPkg.add_pip("pybamm")
# ```

using BattMo
using Printf

# ### 1. Warm-up calls (compilation / import)
println("Warming up BattMo.jl …")
Crate = 0.5
simulation_input = load_full_simulation_input(; from_default_set = "chen_2020")
simulation_input["CyclingProtocol"]["DRate"] = Crate  
_ = run_simulation(simulation_input; info_level = -1)

println("Warming up PyBaMM …")
_ = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = Crate)

# ### 2. Timed runs
n_runs = 3
println("\nBenchmarking ($n_runs runs each) …\n")

# BattMo.jl
battmo_times = Float64[]
for i in 1:n_runs
	t = @elapsed begin
		_ = run_simulation(simulation_input; info_level = -1)
	end
	push!(battmo_times, t)
	@printf("  BattMo.jl  run %d: %.3f s\n", i, t)
end

# PyBaMM
pybamm_times = Float64[]
for i in 1:n_runs
	t = @elapsed begin
		_ = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = Crate)
	end
	push!(pybamm_times, t)
	@printf("  PyBaMM     run %d: %.3f s\n", i, t)
end

# Summary
println("\n─────────────────────────────────────")
@printf("  BattMo.jl  mean: %.3f s  (min %.3f s)\n", sum(battmo_times) / n_runs, minimum(battmo_times))
@printf("  PyBaMM     mean: %.3f s  (min %.3f s)\n", sum(pybamm_times) / n_runs, minimum(pybamm_times))
@printf("  Speed-up (min): %.2f×\n", minimum(pybamm_times) / minimum(battmo_times))
println("─────────────────────────────────────")
