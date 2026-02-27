using BattMo
using PythonCall
using Test

function pybamm_solve_available()
	try
		result = run_pybamm(; model_name = "SPM", parameter_set = "Chen2020", C_rate = 1.0)
		return length(result.time) > 0
	catch
		return false
	end
end

@testset "run_pybamm" begin

	if pybamm_solve_available()
		result = run_pybamm(;
			model_name    = "DFN",
			parameter_set = "Chen2020",
			C_rate        = 1.0,
		)

		@test length(result.time) > 1
		@test length(result.voltage) == length(result.time)
		@test length(result.current) == length(result.time)
		@test result.voltage[1] > 3.0
		@test result.voltage[end] < 4.5
		@test all(result.time .>= 0.0)
	else
		@info "Skipping run_pybamm tests: pybamm is not installed or not functional in the current Python environment."
		@test_skip true
	end

end
