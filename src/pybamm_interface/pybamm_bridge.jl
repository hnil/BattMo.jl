export run_pybamm

"""
    _patch_legacy_pybamm()

Apply compatibility patches to pybamm 0.2.x so it can be imported without
a working jax installation.  This is only needed when the installed pybamm
is the legacy 0.2.x series (the only version available on Python ≥ 3.14).

The patches are idempotent: re-running this function is a no-op.
"""
function _patch_legacy_pybamm()
	pyexec("""
import sys, os, importlib.util

spec = importlib.util.find_spec("pybamm")
if spec is None:
    raise ImportError("pybamm is not installed in the current Python environment")

pkg_dir = os.path.dirname(spec.origin)

# 1. evaluate.py – disable unconditional jax import on Linux
eval_path = os.path.join(pkg_dir, "expression_tree", "operations", "evaluate.py")
if os.path.exists(eval_path):
    with open(eval_path, "r") as f:
        src = f.read()
    marker = "# PATCHED_BY_BATTMO"
    if marker not in src:
        old = '''if system() != "Windows":\n    import jax\n\n    from jax.config import config\n    config.update("jax_enable_x64", True)'''
        new = '''if False:  ''' + marker + '''\n    import jax\n    from jax.config import config\n    config.update("jax_enable_x64", True)'''
        if old in src:
            with open(eval_path, "w") as f:
                f.write(src.replace(old, new))

# 2. __init__.py – wrap jax solver imports in try/except
init_path = spec.origin
if os.path.exists(init_path):
    with open(init_path, "r") as f:
        src = f.read()
    marker = "# PATCHED_BY_BATTMO"
    if marker not in src:
        pairs = [
            ("from .solvers.jax_solver import JaxSolver",
             "try:\\n        from .solvers.jax_solver import JaxSolver  " + marker + "\\n    except ImportError:\\n        pass"),
            ("from .solvers.jax_bdf_solver import jax_bdf_integrate",
             "try:\\n        from .solvers.jax_bdf_solver import jax_bdf_integrate  " + marker + "\\n    except ImportError:\\n        pass"),
        ]
        for old, new in pairs:
            src = src.replace(old, new)
        with open(init_path, "w") as f:
            f.write(src)
""", pydict())
end

"""
    _ensure_pybamm()

Import pybamm, applying compatibility patches for legacy 0.2.x when needed.
Returns the Python pybamm module.
"""
function _ensure_pybamm()
	# If pybamm is already loaded, just return it
	try
		return pyimport("pybamm")
	catch
		# Not yet imported – may need patching
	end
	try
		_patch_legacy_pybamm()
	catch e
		@warn "Failed to patch legacy pybamm for jax compatibility" exception = e
	end
	return pyimport("pybamm")
end

"""
    run_pybamm(; model_name = "DFN", parameter_set = "Chen2020",
                 C_rate = 1.0, t_eval = nothing,
                 temperature = nothing, thermal = false,
                 sei = false)

Run a PyBaMM simulation from Julia using PythonCall and return the results as a
Julia NamedTuple.

Requires PyBaMM to be installed in the Python environment used by PythonCall.
The recommended setup is to have a `CondaPkg.toml` at the project root (this
repository ships one) which pins Python < 3.14 and installs modern pybamm
(≥ 24.1) automatically through CondaPkg / PythonCall.

The function also supports the legacy pybamm 0.2.x series (the only version
available on Python ≥ 3.14) and applies compatibility patches automatically.

# Arguments
- `model_name::String`: PyBaMM model class name. One of `"SPM"`, `"SPMe"`, or `"DFN"`.
- `parameter_set::String`: Name of the PyBaMM parameter set (e.g. `"Chen2020"`, `"Marquis2019"`).
- `C_rate::Float64`: C-rate for CC discharge (default `1.0`).
- `t_eval::Union{Nothing, AbstractVector}`: Time points (s) at which to evaluate.
  If `nothing`, a default time span of `3700/C_rate` seconds is used.
- `temperature::Union{Nothing, Float64}`: Ambient temperature in K. If `nothing`
  uses the parameter-set default.
- `thermal::Bool`: When `true`, use the lumped thermal model.
- `sei::Bool`: When `true`, enable the SEI growth model (reaction-limited).

# Returns
A `NamedTuple` with fields:
- `time::Vector{Float64}` – time in seconds
- `voltage::Vector{Float64}` – cell voltage in V
- `current::Vector{Float64}` – cell current in A
- `sei_thickness::Union{Nothing, Vector{Float64}}` – total SEI thickness in m (only when `sei = true`)
- `cell_temperature::Union{Nothing, Vector{Float64}}` – volume-averaged cell temperature in K (only when `thermal = true`)

# Example
```julia
using BattMo
result = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = 1.0)
result_sei = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = 1.0, sei = true)
```
"""
function run_pybamm(;
	model_name::String = "DFN",
	parameter_set::String = "Chen2020",
	C_rate::Float64 = 1.0,
	t_eval::Union{Nothing, AbstractVector} = nothing,
	temperature::Union{Nothing, Float64} = nothing,
	thermal::Bool = false,
	sei::Bool = false,
)

	pybamm = _ensure_pybamm()

	# Detect PyBaMM version to handle API differences (0.x = legacy, 24.x+ = modern)
	pybamm_version = pyconvert(String, pybamm.__version__)
	is_legacy = startswith(pybamm_version, "0.")

	# Build model options
	options = Dict{String, Any}()
	if thermal
		options["thermal"] = "lumped"
	end
	if sei
		if is_legacy
			options["sei"] = "reaction limited"
		else
			options["SEI"] = "reaction limited"
		end
	end

	# Select model
	model_constructor = if model_name == "SPM"
		pybamm.lithium_ion.SPM
	elseif model_name == "SPMe"
		pybamm.lithium_ion.SPMe
	elseif model_name == "DFN"
		pybamm.lithium_ion.DFN
	else
		error("Unsupported PyBaMM model: $model_name. Use \"SPM\", \"SPMe\", or \"DFN\".")
	end

	py_model = if isempty(options)
		model_constructor()
	else
		model_constructor(; options = pydict(options))
	end

	# Load parameter set — legacy 0.2.x uses chemistry keyword
	params = if is_legacy
		chemistry = getproperty(pybamm.parameter_sets, Symbol(parameter_set))
		pybamm.ParameterValues(; chemistry)
	else
		pybamm.ParameterValues(parameter_set)
	end

	# Set C-rate via current — parameter key differs between versions
	capacity_key = is_legacy ? "Cell capacity [A.h]" : "Nominal cell capacity [A.h]"
	I_typ = pyconvert(Float64, params[capacity_key]) * C_rate

	current_key = is_legacy ? "Typical current [A]" : "Current function [A]"
	params[current_key] = I_typ

	# Set temperature if provided
	if !isnothing(temperature)
		params["Ambient temperature [K]"] = temperature
		params["Initial temperature [K]"] = temperature
	end

	# Build simulation and solve
	sim = pybamm.Simulation(py_model; parameter_values = params)

	np = pyimport("numpy")
	if isnothing(t_eval)
		# Default time span: slightly above 1/C_rate hours (3600/C_rate seconds)
		# to ensure full discharge is captured.  The extra 100 s margin matches the
		# PyBaMM recommendation of 3700/C.
		t_end = 3700.0 / C_rate
		py_t_eval = np.linspace(0.0, t_end, 100)
	else
		py_t_eval = np.array(collect(Float64, t_eval))
	end
	sol = sim.solve(; t_eval = py_t_eval)

	# Extract results to Julia vectors
	time_s = pyconvert(Vector{Float64}, sol["Time [s]"].entries)
	voltage = pyconvert(Vector{Float64}, sol["Voltage [V]"].entries)
	current = pyconvert(Vector{Float64}, sol["Current [A]"].entries)

	# Extract SEI thickness if SEI model is enabled
	sei_thickness = nothing
	if sei
		try
			sei_thickness = pyconvert(Vector{Float64}, sol["Total SEI thickness [m]"].entries)
		catch
			try
				sei_thickness = pyconvert(Vector{Float64}, sol["X-averaged total SEI thickness [m]"].entries)
			catch
				@warn "Could not extract SEI thickness from PyBaMM solution"
			end
		end
	end

	# Extract cell temperature if thermal model is enabled
	cell_temperature = nothing
	if thermal
		try
			cell_temperature = pyconvert(Vector{Float64}, sol["X-averaged cell temperature [K]"].entries)
		catch
			try
				cell_temperature = pyconvert(Vector{Float64}, sol["Cell temperature [K]"].entries)
			catch
				@warn "Could not extract cell temperature from PyBaMM solution"
			end
		end
	end

	return (time = time_s, voltage = voltage, current = current, sei_thickness = sei_thickness, cell_temperature = cell_temperature)
end
