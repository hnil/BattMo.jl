export battmo_to_pybamm, pybamm_to_battmo

# ─────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    _get_nested(d::Dict, keys...)

Safely traverse a nested dictionary returning `nothing` when any key is missing.
"""
function _get_nested(d::Dict, keys...)
	val = d
	for k in keys
		val isa Dict || return nothing
		val = get(val, String(k), nothing)
		val === nothing && return nothing
	end
	return val
end

"""
    _compute_electrode_porosity(electrode::Dict) -> Float64

Compute electrode porosity from BattMo coating/material parameters.

    porosity = 1 − EffectiveDensity / (Σ MassFraction_i × Density_i)
"""
function _compute_electrode_porosity(electrode::Dict)
	coating = get(electrode, "Coating", Dict())
	am = get(electrode, "ActiveMaterial", Dict())
	binder = get(electrode, "Binder", Dict())
	additive = get(electrode, "ConductiveAdditive", Dict())

	eff_density = get(coating, "EffectiveDensity", nothing)
	eff_density === nothing && return nothing

	am_mf = get(am, "MassFraction", 1.0)
	am_rho = get(am, "Density", nothing)
	am_rho === nothing && return nothing
	b_mf = get(binder, "MassFraction", 0.0)
	b_rho = get(binder, "Density", 0.0)
	add_mf = get(additive, "MassFraction", 0.0)
	add_rho = get(additive, "Density", 0.0)

	solid_density = am_mf * am_rho + b_mf * b_rho + add_mf * add_rho
	solid_density ≈ 0.0 && return nothing
	vf_solid = eff_density / solid_density
	return 1.0 - vf_solid
end

"""
    _compute_am_volume_fraction(electrode::Dict) -> Float64

Compute active-material volume fraction in the electrode.

    vf_AM = EffectiveDensity × MassFraction_AM / Density_AM
"""
function _compute_am_volume_fraction(electrode::Dict)
	coating = get(electrode, "Coating", Dict())
	am = get(electrode, "ActiveMaterial", Dict())

	eff_density = get(coating, "EffectiveDensity", nothing)
	eff_density === nothing && return nothing
	am_mf = get(am, "MassFraction", 1.0)
	am_rho = get(am, "Density", nothing)
	am_rho === nothing && return nothing
	am_rho ≈ 0.0 && return nothing

	return eff_density * am_mf / am_rho
end

"""
    _battmo_ocp_to_pybamm_expr(ocp_string::String) -> String

Convert a BattMo OCP expression string to a PyBaMM-compatible Python
expression.  BattMo uses `c/cmax` (stoichiometry); PyBaMM uses `sto`.
The caret `^` is replaced with Python's `**`.
"""
function _battmo_ocp_to_pybamm_expr(ocp_string::String)
	expr = replace(ocp_string, "c/cmax" => "sto")
	expr = replace(expr, "^" => "**")
	return expr
end

"""
    _pybamm_ocp_to_battmo_expr(ocp_string::String) -> String

Convert a PyBaMM OCP expression string to a BattMo-compatible expression.
PyBaMM uses `sto` (stoichiometry); BattMo uses `c/cmax`. Python `**` is
replaced with `^`.
"""
function _pybamm_ocp_to_battmo_expr(ocp_string::String)
	expr = replace(ocp_string, "sto" => "c/cmax")
	expr = replace(expr, "**" => "^")
	return expr
end

"""
    _battmo_elyte_to_pybamm_expr(expr_string::String) -> String

Convert a BattMo electrolyte expression (variable `c`) to a PyBaMM-compatible
Python expression (variable `c_e`).  Also translates `^` → `**` and the
MATLAB-style `10^(…)` notation.
"""
function _battmo_elyte_to_pybamm_expr(expr_string::String)
	expr = replace(expr_string, "^" => "**")
	return expr
end

"""
    _pybamm_elyte_to_battmo_expr(expr_string::String) -> String

Convert a PyBaMM electrolyte expression (variable `c_e`) to BattMo format
(variable `c`).  Translates `**` → `^`.
"""
function _pybamm_elyte_to_battmo_expr(expr_string::String)
	expr = replace(expr_string, "**" => "^")
	return expr
end

"""
    _battmo_k0_to_pybamm_mref(k0, n_electrons=1) -> Float64

Convert BattMo reaction rate constant k₀ to PyBaMM reference exchange-current
prefactor m_ref.

For Butler–Volmer kinetics with symmetric transfer coefficient (α = 0.5):

    j₀ = m_ref · c_e^0.5 · c_s^0.5 · (c_max − c_s)^0.5      (PyBaMM)
    j₀ = n · F · k₀ · c_e^0.5 · c_s^0.5 · (c_max − c_s)^0.5  (BattMo)

Hence  m_ref = n · F · k₀.
"""
function _battmo_k0_to_pybamm_mref(k0::Real, n_electrons::Int = 1)
	F = 96485.3329  # Faraday constant  [C/mol]
	return Float64(k0) * n_electrons * F
end

"""
    _pybamm_mref_to_battmo_k0(m_ref, n_electrons=1) -> Float64

Inverse of [`_battmo_k0_to_pybamm_mref`](@ref).
"""
function _pybamm_mref_to_battmo_k0(m_ref::Real, n_electrons::Int = 1)
	F = 96485.3329
	return Float64(m_ref) / (n_electrons * F)
end

# ─────────────────────────────────────────────────────────────────────────────
# battmo_to_pybamm
# ─────────────────────────────────────────────────────────────────────────────

"""
    battmo_to_pybamm(cell_parameters::CellParameters;
                     cycling_protocol::Union{CyclingProtocol, Nothing} = nothing)

Translate BattMo.jl cell parameters (and, optionally, a cycling protocol) into a
flat `Dict{String, Any}` whose keys are PyBaMM parameter names.

The returned dictionary can be used to update a PyBaMM `ParameterValues` object
via PythonCall, e.g.

```julia
pybamm_dict = battmo_to_pybamm(cell_params; cycling_protocol = cp)
pybamm = pyimport("pybamm")
params = pybamm.ParameterValues("Chen2020")
for (k, v) in pybamm_dict
    params[k] = v
end
```

# Mapped parameters

| BattMo path                        | PyBaMM key                                          |
|------------------------------------|-----------------------------------------------------|
| Cell / NominalCapacity             | Nominal cell capacity [A.h]                         |
| Electrode / Coating / Thickness    | {Neg,Pos} electrode thickness [m]                   |
| Electrode / Coating / Bruggeman    | {Neg,Pos} electrode Bruggeman coefficient (elyte)   |
| (computed from EffectiveDensity)   | {Neg,Pos} electrode porosity                        |
| (computed from EffectiveDensity)   | {Neg,Pos} electrode active material volume fraction |
| AM / ElectronicConductivity        | {Neg,Pos} electrode conductivity [S.m-1]            |
| AM / DiffusionCoefficient          | {Neg,Pos} electrode diffusivity [m2.s-1]            |
| AM / ParticleRadius                | {Neg,Pos} particle radius [m]                       |
| AM / MaximumConcentration          | Maximum concentration in {neg,pos} electrode        |
| AM / NumberOfElectronsTransfered   | {Neg,Pos} electrode electrons in reaction            |
| AM / ReactionRateConstant          | (converted to m_ref via k₀·n·F)                     |
| CC / Thickness                     | {Neg,Pos} current collector thickness [m]            |
| CC / Density                       | {Neg,Pos} current collector density [kg.m-3]         |
| CC / ElectronicConductivity        | {Neg,Pos} current collector conductivity [S.m-1]     |
| Separator / Thickness              | Separator thickness [m]                              |
| Separator / Porosity               | Separator porosity                                   |
| Separator / BruggemanCoefficient   | Separator Bruggeman coefficient (electrolyte)        |
| Separator / Density                | Separator density [kg.m-3]                           |
| Electrolyte / Concentration        | Initial concentration in electrolyte [mol.m-3]       |
| Electrolyte / TransferenceNumber   | Cation transference number                           |
| CyclingProtocol / LowerVoltageLimit| Lower voltage cut-off [V]                            |
| CyclingProtocol / UpperVoltageLimit| Upper voltage cut-off [V]                            |
| CyclingProtocol / DRate/CRate      | Current function [A]                                 |

# Arguments
- `cell_parameters::CellParameters` : BattMo cell parameters.
- `cycling_protocol` : Optional BattMo cycling protocol.

# Returns
`Dict{String, Any}` – PyBaMM-compatible parameter dictionary.
"""
function battmo_to_pybamm(cell_parameters::CellParameters;
	cycling_protocol::Union{CyclingProtocol, Nothing} = nothing)

	params = cell_parameters.all
	result = Dict{String, Any}()

	# ── Cell-level ────────────────────────────────────────────────────────
	capacity = _get_nested(params, "Cell", "NominalCapacity")
	if !isnothing(capacity)
		result["Nominal cell capacity [A.h]"] = capacity
	end

	# ── Electrodes ────────────────────────────────────────────────────────
	electrode_specs = [
		("NegativeElectrode", "Negative electrode", "Negative"),
		("PositiveElectrode", "Positive electrode", "Positive"),
	]

	for (battmo_key, pybamm_prefix, particle_prefix) in electrode_specs
		electrode = get(params, battmo_key, nothing)
		electrode === nothing && continue

		coating = get(electrode, "Coating", Dict())
		am = get(electrode, "ActiveMaterial", Dict())
		cc = get(electrode, "CurrentCollector", Dict())

		# Coating / geometry
		_maybe_set!(result, "$(pybamm_prefix) thickness [m]", get(coating, "Thickness", nothing))
		_maybe_set!(result, "$(pybamm_prefix) Bruggeman coefficient (electrolyte)", get(coating, "BruggemanCoefficient", nothing))

		# Computed porosity & AM volume fraction
		porosity = _compute_electrode_porosity(electrode)
		_maybe_set!(result, "$(pybamm_prefix) porosity", porosity)
		am_vf = _compute_am_volume_fraction(electrode)
		_maybe_set!(result, "$(pybamm_prefix) active material volume fraction", am_vf)

		# Active material properties
		_maybe_set!(result, "$(pybamm_prefix) conductivity [S.m-1]", get(am, "ElectronicConductivity", nothing))
		_maybe_set!(result, "$(pybamm_prefix) diffusivity [m2.s-1]", get(am, "DiffusionCoefficient", nothing))
		_maybe_set!(result, "$(particle_prefix) particle radius [m]", get(am, "ParticleRadius", nothing))
		_maybe_set!(result, "Maximum concentration in $(lowercase(pybamm_prefix)) [mol.m-3]", get(am, "MaximumConcentration", nothing))
		_maybe_set!(result, "$(pybamm_prefix) electrons in reaction", get(am, "NumberOfElectronsTransfered", nothing))

		# Reaction rate constant → m_ref
		k0 = get(am, "ReactionRateConstant", nothing)
		n_e = get(am, "NumberOfElectronsTransfered", 1)
		if !isnothing(k0)
			result["$(pybamm_prefix) exchange-current density m_ref [A.m-2]"] =
				_battmo_k0_to_pybamm_mref(k0, n_e isa Number ? Int(n_e) : 1)
		end

		# Stoichiometric limits
		_maybe_set!(result, "$(pybamm_prefix) stoichiometry at x=0", get(am, "StoichiometricCoefficientAtSOC0", nothing))
		_maybe_set!(result, "$(pybamm_prefix) stoichiometry at x=100", get(am, "StoichiometricCoefficientAtSOC100", nothing))

		# OCP expression
		ocp_str = get(am, "OpenCircuitPotential", nothing)
		if !isnothing(ocp_str) && ocp_str isa String
			result["$(pybamm_prefix) OCP expression"] = _battmo_ocp_to_pybamm_expr(ocp_str)
		end

		# Current collector
		_maybe_set!(result, "$(particle_prefix) current collector thickness [m]", get(cc, "Thickness", nothing))
		_maybe_set!(result, "$(particle_prefix) current collector density [kg.m-3]", get(cc, "Density", nothing))
		_maybe_set!(result, "$(particle_prefix) current collector conductivity [S.m-1]", get(cc, "ElectronicConductivity", nothing))
	end

	# ── Separator ─────────────────────────────────────────────────────────
	sep = get(params, "Separator", nothing)
	if !isnothing(sep)
		_maybe_set!(result, "Separator thickness [m]", get(sep, "Thickness", nothing))
		_maybe_set!(result, "Separator porosity", get(sep, "Porosity", nothing))
		_maybe_set!(result, "Separator Bruggeman coefficient (electrolyte)", get(sep, "BruggemanCoefficient", nothing))
		_maybe_set!(result, "Separator density [kg.m-3]", get(sep, "Density", nothing))
	end

	# ── Electrolyte ───────────────────────────────────────────────────────
	elyte = get(params, "Electrolyte", nothing)
	if !isnothing(elyte)
		_maybe_set!(result, "Initial concentration in electrolyte [mol.m-3]", get(elyte, "Concentration", nothing))
		_maybe_set!(result, "Cation transference number", get(elyte, "TransferenceNumber", nothing))

		cond_str = get(elyte, "IonicConductivity", nothing)
		if !isnothing(cond_str) && cond_str isa String
			result["Electrolyte conductivity expression"] = _battmo_elyte_to_pybamm_expr(cond_str)
		end

		diff_str = get(elyte, "DiffusionCoefficient", nothing)
		if !isnothing(diff_str) && diff_str isa String
			result["Electrolyte diffusivity expression"] = _battmo_elyte_to_pybamm_expr(diff_str)
		end
	end

	# ── Cycling protocol ──────────────────────────────────────────────────
	if !isnothing(cycling_protocol)
		cp = cycling_protocol.all
		_maybe_set!(result, "Lower voltage cut-off [V]", get(cp, "LowerVoltageLimit", nothing))
		_maybe_set!(result, "Upper voltage cut-off [V]", get(cp, "UpperVoltageLimit", nothing))

		if !isnothing(capacity)
			initial_control = get(cp, "InitialControl", "discharging")
			if initial_control == "discharging"
				d_rate = get(cp, "DRate", 1.0)
				result["Current function [A]"] = capacity * d_rate
			else
				c_rate = get(cp, "CRate", 1.0)
				result["Current function [A]"] = -capacity * c_rate
			end
		end

		_maybe_set!(result, "Initial State of Charge", get(cp, "InitialStateOfCharge", nothing))
	end

	return result
end

"""Helper – insert `value` into `d[key]` only when `value !== nothing`."""
function _maybe_set!(d::Dict, key::String, value)
	value === nothing || (d[key] = value)
	return d
end

# ─────────────────────────────────────────────────────────────────────────────
# pybamm_to_battmo
# ─────────────────────────────────────────────────────────────────────────────

"""
    pybamm_to_battmo(; parameter_set::String = "Chen2020")

Load a PyBaMM parameter set via PythonCall and convert it to BattMo.jl
`CellParameters` and `CyclingProtocol`.

Requires PyBaMM to be installed in the Python environment used by PythonCall
(see `CondaPkg.toml` shipped with this repository).

# Arguments
- `parameter_set::String` : PyBaMM parameter set name
  (e.g. `"Chen2020"`, `"Marquis2019"`, `"Ecker2015"`).

# Returns
A `NamedTuple` with fields:
- `cell_parameters  :: CellParameters`
- `cycling_protocol :: CyclingProtocol`

# Example
```julia
using BattMo
result = pybamm_to_battmo(; parameter_set = "Chen2020")
sim = Simulation(LithiumIonBattery(), result.cell_parameters, result.cycling_protocol)
output = solve(sim; info_level = -1)
```
"""
function pybamm_to_battmo(; parameter_set::String = "Chen2020")

	pybamm = _ensure_pybamm()
	pybamm_version = pyconvert(String, pybamm.__version__)
	is_legacy = startswith(pybamm_version, "0.")

	# Load the PyBaMM parameter set
	py_params = if is_legacy
		chemistry = getproperty(pybamm.parameter_sets, Symbol(parameter_set))
		pybamm.ParameterValues(; chemistry)
	else
		pybamm.ParameterValues(parameter_set)
	end

	# ── Helper closures ───────────────────────────────────────────────────

	function _getf(key::String, default = nothing)
		try
			v = py_params[key]
			return pyconvert(Float64, v)
		catch
			return default
		end
	end

	function _geti(key::String, default = nothing)
		try
			v = py_params[key]
			return pyconvert(Int, v)
		catch
			return default
		end
	end

	function _gets(key::String, default = nothing)
		try
			v = py_params[key]
			return pyconvert(String, v)
		catch
			return default
		end
	end

	# ── Cell ──────────────────────────────────────────────────────────────
	capacity_key = is_legacy ? "Cell capacity [A.h]" : "Nominal cell capacity [A.h]"
	capacity = _getf(capacity_key, 5.0)

	cell_dict = Dict{String, Any}(
		"Metadata" => Dict{String, Any}(
			"Title" => parameter_set,
			"Source" => "Converted from PyBaMM parameter set: $parameter_set",
			"Description" => "Automatically converted from PyBaMM $parameter_set",
			"Models" => Dict{String, Any}(
				"ModelFramework" => "P2D",
				"TransportInSolid" => "FullDiffusion",
			),
		),
		"Cell" => Dict{String, Any}(
			"NominalCapacity" => capacity,
		),
	)

	# ── Electrodes ────────────────────────────────────────────────────────
	electrode_specs = [
		("NegativeElectrode", "Negative electrode", "Negative", "Copper"),
		("PositiveElectrode", "Positive electrode", "Positive", "Aluminum"),
	]

	for (battmo_key, pybamm_prefix, particle_prefix, cc_material) in electrode_specs
		thickness = _getf("$pybamm_prefix thickness [m]")
		bruggeman = _getf("$pybamm_prefix Bruggeman coefficient (electrolyte)", 1.5)
		porosity = _getf("$pybamm_prefix porosity")
		am_vf = _getf("$pybamm_prefix active material volume fraction")
		conductivity = _getf("$pybamm_prefix conductivity [S.m-1]")
		diffusivity = _getf("$pybamm_prefix diffusivity [m2.s-1]")
		particle_radius = _getf("$particle_prefix particle radius [m]")
		max_conc = _getf("Maximum concentration in $(lowercase(pybamm_prefix)) [mol.m-3]")
		n_electrons = _geti("$pybamm_prefix electrons in reaction", 1)

		cc_thickness = _getf("$particle_prefix current collector thickness [m]")
		cc_density = _getf("$particle_prefix current collector density [kg.m-3]")
		cc_conductivity = _getf("$particle_prefix current collector conductivity [S.m-1]")

		# Compute BattMo EffectiveDensity from porosity and active material
		# volume fraction.  BattMo stores the effective (dry) coating density:
		#   EffectiveDensity = vf_solid × solid_phase_density
		# With the simplification MassFraction_AM = 1 (no binder/additive):
		#   EffectiveDensity = am_vf × Density_AM
		# We estimate Density_AM from am_vf and porosity:
		#   am_vf ≤ (1 − porosity)
		# For 100 % active material: am_vf = 1 − porosity ⟹ Density_AM = EffectiveDensity / am_vf
		#
		# When am_vf < (1 − porosity), the remaining solid is binder + additive.
		# We set MassFraction_AM < 1 accordingly, but keep density estimation.

		am_density = nothing
		eff_density = nothing
		am_mf = 1.0
		vf_solid = isnothing(porosity) ? nothing : 1.0 - porosity

		if !isnothing(am_vf) && !isnothing(vf_solid) && vf_solid > 0
			if am_vf ≈ vf_solid
				# 100 % active material – typical for Chen2020
				# Density_AM must be inferred from a reference; try PyBaMM param
				am_density_key = "$pybamm_prefix density [kg.m-3]"
				am_density_pybamm = _getf(am_density_key)
				if isnothing(am_density_pybamm)
					am_density_pybamm = _getf("$particle_prefix particle density [kg.m-3]")
				end
				if !isnothing(am_density_pybamm)
					am_density = am_density_pybamm
					eff_density = am_vf * am_density
				end
			else
				# Mixed solid phase – approximate
				am_mf = am_vf / vf_solid
				am_density_key = "$particle_prefix particle density [kg.m-3]"
				am_density = _getf(am_density_key)
			end
		end

		# Active material dict
		am_dict = Dict{String, Any}(
			"MassFraction" => am_mf,
			"ChargeTransferCoefficient" => 0.5,
			"NumberOfElectronsTransfered" => n_electrons,
		)
		_maybe_set!(am_dict, "ElectronicConductivity", conductivity)
		_maybe_set!(am_dict, "DiffusionCoefficient", diffusivity)
		_maybe_set!(am_dict, "ParticleRadius", particle_radius)
		_maybe_set!(am_dict, "MaximumConcentration", max_conc)
		_maybe_set!(am_dict, "Density", am_density)

		# Stoichiometric limits (try PyBaMM naming variants)
		soc0 = _getf("$pybamm_prefix stoichiometry at x=0")
		if isnothing(soc0)
			# Try the legacy-style "Initial stoichiometry" keys
			soc0 = if battmo_key == "NegativeElectrode"
				_getf("Negative electrode SOC 0")
			else
				_getf("Positive electrode SOC 0")
			end
		end
		soc100 = _getf("$pybamm_prefix stoichiometry at x=100")
		if isnothing(soc100)
			soc100 = if battmo_key == "NegativeElectrode"
				_getf("Negative electrode SOC 100")
			else
				_getf("Positive electrode SOC 100")
			end
		end
		_maybe_set!(am_dict, "StoichiometricCoefficientAtSOC0", soc0)
		_maybe_set!(am_dict, "StoichiometricCoefficientAtSOC100", soc100)

		# Try to extract OCP as a Python expression string.
		# PyBaMM stores OCP as a Python function. We attempt to extract
		# the expression by evaluating the function symbolically or
		# reading its source code if available.
		_try_extract_ocp!(am_dict, py_params, pybamm_prefix, is_legacy)

		# Reaction rate constant from m_ref
		_try_extract_reaction_rate!(am_dict, py_params, pybamm_prefix, particle_prefix, n_electrons, is_legacy)

		# Activation energies (if available)
		ea_diff = _getf("$pybamm_prefix diffusion activation energy [J.mol-1]")
		_maybe_set!(am_dict, "ActivationEnergyOfDiffusion", ea_diff)
		ea_rxn = _getf("$pybamm_prefix reaction activation energy [J.mol-1]")
		_maybe_set!(am_dict, "ActivationEnergyOfReaction", ea_rxn)

		# Volumetric surface area
		vsa = _getf("$pybamm_prefix surface area to volume ratio [m-1]")
		_maybe_set!(am_dict, "VolumetricSurfaceArea", vsa)
		if isnothing(vsa) && !isnothing(particle_radius) && !isnothing(am_vf) && particle_radius > 0
			am_dict["VolumetricSurfaceArea"] = 3.0 * am_vf / particle_radius
		end

		# Coating dict
		coating_dict = Dict{String, Any}("BruggemanCoefficient" => bruggeman)
		_maybe_set!(coating_dict, "Thickness", thickness)
		_maybe_set!(coating_dict, "EffectiveDensity", eff_density)

		# Current collector dict
		cc_dict = Dict{String, Any}("Description" => cc_material)
		_maybe_set!(cc_dict, "Thickness", cc_thickness)
		_maybe_set!(cc_dict, "Density", cc_density)
		_maybe_set!(cc_dict, "ElectronicConductivity", cc_conductivity)

		# Binder & additive (placeholders)
		binder_dict = Dict{String, Any}(
			"Description" => "Unknown",
			"Density" => 1100.0,
			"MassFraction" => 0.0,
			"ElectronicConductivity" => 100.0,
		)
		additive_dict = Dict{String, Any}(
			"Description" => "Unknown",
			"Density" => 1950.0,
			"MassFraction" => 0.0,
			"ElectronicConductivity" => 100.0,
		)

		cell_dict[battmo_key] = Dict{String, Any}(
			"Coating" => coating_dict,
			"ActiveMaterial" => am_dict,
			"CurrentCollector" => cc_dict,
			"Binder" => binder_dict,
			"ConductiveAdditive" => additive_dict,
		)
	end

	# ── Separator ─────────────────────────────────────────────────────────
	sep_dict = Dict{String, Any}()
	_maybe_set!(sep_dict, "Thickness", _getf("Separator thickness [m]"))
	_maybe_set!(sep_dict, "Porosity", _getf("Separator porosity"))
	_maybe_set!(sep_dict, "BruggemanCoefficient", _getf("Separator Bruggeman coefficient (electrolyte)", 1.5))
	_maybe_set!(sep_dict, "Density", _getf("Separator density [kg.m-3]"))
	cell_dict["Separator"] = sep_dict

	# ── Electrolyte ───────────────────────────────────────────────────────
	elyte_dict = Dict{String, Any}()
	_maybe_set!(elyte_dict, "Concentration", _getf("Initial concentration in electrolyte [mol.m-3]"))
	_maybe_set!(elyte_dict, "TransferenceNumber", _getf("Cation transference number"))
	_maybe_set!(elyte_dict, "ChargeNumber", _geti("Cation charge number", 1))
	_maybe_set!(elyte_dict, "Density", _getf("Electrolyte density [kg.m-3]"))
	cell_dict["Electrolyte"] = elyte_dict

	cell_parameters = CellParameters(cell_dict)

	# ── Cycling protocol ──────────────────────────────────────────────────
	lower_v = _getf("Lower voltage cut-off [V]", 2.5)
	upper_v = _getf("Upper voltage cut-off [V]", 4.2)

	cycling_dict = Dict{String, Any}(
		"Metadata" => Dict{String, Any}(
			"Title" => "cc_discharge",
			"Description" => "Default CC discharge protocol from PyBaMM $parameter_set conversion",
		),
		"Protocol" => "CC",
		"TotalNumberOfCycles" => 0,
		"InitialControl" => "discharging",
		"InitialStateOfCharge" => 0.99,
		"DRate" => 1.0,
		"LowerVoltageLimit" => lower_v,
		"UpperVoltageLimit" => upper_v,
	)

	cycling_protocol = CyclingProtocol(cycling_dict)

	return (cell_parameters = cell_parameters, cycling_protocol = cycling_protocol)
end

# ── OCP extraction helper ─────────────────────────────────────────────────

"""
    _try_extract_ocp!(am_dict, py_params, pybamm_prefix, is_legacy)

Attempt to extract the OCP function source from a PyBaMM ParameterValues
object and store it as a BattMo-compatible expression string in `am_dict`.
"""
function _try_extract_ocp!(am_dict::Dict, py_params, pybamm_prefix::String, is_legacy::Bool)
	try
		inspect = pyimport("inspect")
		ocp_key = "$pybamm_prefix OCP [V]"
		ocp_func = py_params[ocp_key]

		# Try to get source code of the Python function
		src = pyconvert(String, inspect.getsource(ocp_func))

		# Extract the return expression from the function body
		ocp_expr = _extract_return_expr(src)
		if !isnothing(ocp_expr)
			am_dict["OpenCircuitPotential"] = _pybamm_ocp_to_battmo_expr(ocp_expr)
		end
	catch
		# OCP extraction not available – leave as-is
	end
	return am_dict
end

"""
    _extract_return_expr(func_source::String) -> Union{String, Nothing}

Given the source code of a single-return Python function, extract the
expression from the `return` statement.
"""
function _extract_return_expr(src::String)
	# Find the last return statement
	for line in reverse(split(src, '\n'))
		stripped = strip(line)
		if startswith(stripped, "return ")
			return String(strip(stripped[8:end]))
		end
	end
	return nothing
end

# ── Reaction rate extraction helper ───────────────────────────────────────

"""
    _try_extract_reaction_rate!(am_dict, py_params, pybamm_prefix, particle_prefix, n_electrons, is_legacy)

Attempt to extract the exchange-current density prefactor (m_ref) from
PyBaMM and convert it to BattMo's `ReactionRateConstant` (k₀).

The function evaluates the exchange-current density at reference
concentrations (c_e = 1000, c_s = c_max/2) and solves for m_ref.
"""
function _try_extract_reaction_rate!(am_dict::Dict, py_params, pybamm_prefix::String,
	particle_prefix::String, n_electrons, is_legacy::Bool)
	try
		np = pyimport("numpy")
		key = "$pybamm_prefix exchange-current density [A.m-2]"
		j0_func = py_params[key]

		c_max_key = "Maximum concentration in $(lowercase(pybamm_prefix)) [mol.m-3]"
		c_max = pyconvert(Float64, py_params[c_max_key])

		# Evaluate at reference state: c_e = 1000, c_s = c_max/2, T = 298.15
		c_e_ref = 1000.0
		c_s_ref = c_max / 2.0
		T_ref = 298.15

		j0_val = pyconvert(Float64, j0_func(c_e_ref, c_s_ref, c_max, T_ref))

		# j0 = m_ref * c_e^0.5 * c_s^0.5 * (c_max - c_s)^0.5  (for α=0.5)
		denom = sqrt(c_e_ref) * sqrt(c_s_ref) * sqrt(c_max - c_s_ref)
		if denom > 0
			m_ref = j0_val / denom
			k0 = _pybamm_mref_to_battmo_k0(m_ref, n_electrons isa Number ? Int(n_electrons) : 1)
			am_dict["ReactionRateConstant"] = k0
		end
	catch
		# Could not extract – skip
	end
	return am_dict
end
