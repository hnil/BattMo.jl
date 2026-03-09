using BattMo
using Test

@testset "battmo_to_pybamm" begin

	@testset "Chen2020 scalar parameters" begin
		cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
		cycling_protocol = load_cycling_protocol(; from_default_set = "cc_discharge")

		pybamm_dict = battmo_to_pybamm(cell_parameters; cycling_protocol = cycling_protocol)

		# Cell capacity
		@test pybamm_dict["Nominal cell capacity [A.h]"] ≈ 4.8

		# Negative electrode
		@test pybamm_dict["Negative electrode thickness [m]"] ≈ 8.52e-5
		@test pybamm_dict["Negative electrode Bruggeman coefficient (electrolyte)"] ≈ 1.5
		@test pybamm_dict["Negative electrode conductivity [S.m-1]"] ≈ 215.0
		@test pybamm_dict["Negative electrode diffusivity [m2.s-1]"] ≈ 3.3e-14
		@test pybamm_dict["Negative particle radius [m]"] ≈ 5.86e-6
		@test pybamm_dict["Maximum concentration in negative electrode [mol.m-3]"] ≈ 33133.0

		# Computed porosity for negative electrode
		# EffectiveDensity=1695, Density_AM=2260, MassFraction=1.0
		# porosity = 1 - 1695/2260 ≈ 0.25
		@test pybamm_dict["Negative electrode porosity"] ≈ 1.0 - 1695.0 / 2260.0 atol = 1e-6
		@test pybamm_dict["Negative electrode active material volume fraction"] ≈ 1695.0 / 2260.0 atol = 1e-6

		# Positive electrode
		@test pybamm_dict["Positive electrode thickness [m]"] ≈ 7.56e-5
		@test pybamm_dict["Positive electrode conductivity [S.m-1]"] ≈ 0.18
		@test pybamm_dict["Maximum concentration in positive electrode [mol.m-3]"] ≈ 63104.0

		# Computed porosity for positive electrode
		@test pybamm_dict["Positive electrode porosity"] ≈ 1.0 - 3292.0 / 4950.0 atol = 1e-6

		# Separator
		@test pybamm_dict["Separator thickness [m]"] ≈ 1.2e-5
		@test pybamm_dict["Separator porosity"] ≈ 0.47
		@test pybamm_dict["Separator Bruggeman coefficient (electrolyte)"] ≈ 1.5

		# Electrolyte
		@test pybamm_dict["Initial concentration in electrolyte [mol.m-3]"] ≈ 1000.0
		@test pybamm_dict["Cation transference number"] ≈ 0.2594

		# Current collector
		@test pybamm_dict["Negative current collector thickness [m]"] ≈ 1.17e-5
		@test pybamm_dict["Positive current collector thickness [m]"] ≈ 1.63e-5
		@test pybamm_dict["Negative current collector conductivity [S.m-1]"] ≈ 3.55e7
		@test pybamm_dict["Positive current collector conductivity [S.m-1]"] ≈ 5.96e7

		# Cycling protocol
		@test pybamm_dict["Lower voltage cut-off [V]"] ≈ 2.4
		@test pybamm_dict["Upper voltage cut-off [V]"] ≈ 4.1
		@test pybamm_dict["Current function [A]"] ≈ 4.8 * 0.5  # DRate=0.5 from cc_discharge

		# OCP expression converted (c/cmax → sto, ^ → **)
		@test haskey(pybamm_dict, "Negative electrode OCP expression")
		ne_ocp = pybamm_dict["Negative electrode OCP expression"]
		@test occursin("sto", ne_ocp)
		@test !occursin("c/cmax", ne_ocp)
		@test !occursin("^", ne_ocp)

		# Reaction rate constant → m_ref
		@test haskey(pybamm_dict, "Negative electrode exchange-current density m_ref [A.m-2]")
		F = 96485.3329
		@test pybamm_dict["Negative electrode exchange-current density m_ref [A.m-2]"] ≈ 6.716e-12 * F atol = 1e-10
	end

	@testset "without cycling protocol" begin
		cell_parameters = load_cell_parameters(; from_default_set = "chen_2020")
		pybamm_dict = battmo_to_pybamm(cell_parameters)

		@test haskey(pybamm_dict, "Nominal cell capacity [A.h]")
		@test !haskey(pybamm_dict, "Current function [A]")
		@test !haskey(pybamm_dict, "Lower voltage cut-off [V]")
	end

	@testset "OCP expression conversion" begin
		# Test BattMo → PyBaMM expression conversion
		battmo_expr = "1.9793 * exp(-39.3631*(c/cmax)) + 0.2482"
		pybamm_expr = BattMo._battmo_ocp_to_pybamm_expr(battmo_expr)
		@test pybamm_expr == "1.9793 * exp(-39.3631*(sto)) + 0.2482"

		# Test PyBaMM → BattMo expression conversion
		roundtrip = BattMo._pybamm_ocp_to_battmo_expr(pybamm_expr)
		@test roundtrip == battmo_expr
	end

	@testset "reaction rate conversion" begin
		F = 96485.3329
		k0 = 6.716e-12
		m_ref = BattMo._battmo_k0_to_pybamm_mref(k0, 1)
		@test m_ref ≈ k0 * F

		k0_back = BattMo._pybamm_mref_to_battmo_k0(m_ref, 1)
		@test k0_back ≈ k0 atol = 1e-25
	end
end

@testset "pybamm_to_battmo" begin

	# Check if PyBaMM is available
	pybamm_available = try
		result = run_pybamm(; model_name = "SPM", parameter_set = "Chen2020", C_rate = 1.0)
		length(result.time) > 0
	catch
		false
	end

	if pybamm_available
		@testset "Chen2020 conversion" begin
			result = pybamm_to_battmo(; parameter_set = "Chen2020")

			cp = result.cell_parameters
			cyc = result.cycling_protocol

			# Check types
			@test cp isa CellParameters
			@test cyc isa CyclingProtocol

			# Verify key cell parameters exist
			@test haskey(cp, "Cell")
			@test haskey(cp, "NegativeElectrode")
			@test haskey(cp, "PositiveElectrode")
			@test haskey(cp, "Separator")
			@test haskey(cp, "Electrolyte")

			# Verify capacity is reasonable
			@test cp["Cell"]["NominalCapacity"] > 0

			# Check separator has porosity
			sep = cp["Separator"]
			@test haskey(sep, "Porosity")
			if haskey(sep, "Porosity")
				@test 0.0 < sep["Porosity"] < 1.0
			end

			# Check electrolyte concentration
			elyte = cp["Electrolyte"]
			@test haskey(elyte, "Concentration")
			if haskey(elyte, "Concentration")
				@test elyte["Concentration"] > 0
			end

			# Check cycling protocol
			@test cyc["Protocol"] == "CC"
			@test cyc["LowerVoltageLimit"] > 0
			@test cyc["UpperVoltageLimit"] > cyc["LowerVoltageLimit"]
		end

		@testset "round-trip: battmo → pybamm → verify" begin
			# Load BattMo Chen2020, convert to PyBaMM dict
			cell_params = load_cell_parameters(; from_default_set = "chen_2020")
			pybamm_dict = battmo_to_pybamm(cell_params)

			# Load PyBaMM Chen2020 directly and convert to BattMo
			pybamm_result = pybamm_to_battmo(; parameter_set = "Chen2020")

			# Key structural parameters should match between BattMo native and
			# the PyBaMM-converted version (within tolerance since PyBaMM values
			# may differ slightly)
			sep_native = cell_params["Separator"]
			sep_converted = pybamm_result.cell_parameters["Separator"]

			if haskey(sep_converted, "Thickness") && haskey(sep_native, "Thickness")
				@test sep_converted["Thickness"] ≈ sep_native["Thickness"] rtol = 0.01
			end

			if haskey(sep_converted, "Porosity") && haskey(sep_native, "Porosity")
				@test sep_converted["Porosity"] ≈ sep_native["Porosity"] rtol = 0.01
			end
		end
	else
		@info "Skipping pybamm_to_battmo tests: pybamm is not installed or not functional in the current Python environment."
		@test_skip true
	end
end
