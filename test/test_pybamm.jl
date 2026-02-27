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
		@test begin

			result = run_pybamm(;
				model_name    = "DFN",
				parameter_set = "Chen2020",
				C_rate        = 1.0,
			)

			# Basic sanity checks
			@assert length(result.time) > 1
			@assert length(result.voltage) == length(result.time)
			@assert length(result.current) == length(result.time)
			@assert result.voltage[1] > 3.0      # Reasonable starting voltage
			@assert result.voltage[end] < 4.5     # Below max voltage
			@assert all(result.time .>= 0.0)      # Non-negative times
			true

		end
	else
		@info "Skipping run_pybamm tests: pybamm is not installed or not functional in the current Python environment."
		@test_skip true
	end

end
