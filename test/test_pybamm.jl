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
		@testset "Chen2020 DFN discharge" begin
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
		end

		@testset "Chen2020 DFN with SEI" begin
			result_sei = run_pybamm(;
				model_name    = "DFN",
				parameter_set = "Chen2020",
				C_rate        = 1.0,
				sei           = true,
			)

			@test length(result_sei.time) > 1
			@test length(result_sei.voltage) == length(result_sei.time)
			@test length(result_sei.current) == length(result_sei.time)
			@test result_sei.voltage[1] > 3.0
			@test result_sei.voltage[end] < 4.5
			@test all(result_sei.time .>= 0.0)
		end
	else
		@info "Skipping run_pybamm tests: pybamm is not installed or not functional in the current Python environment. " *
			  "The CondaPkg.toml shipped with this repository configures the correct Python and pybamm versions automatically."
		@test_skip true
	end

end
