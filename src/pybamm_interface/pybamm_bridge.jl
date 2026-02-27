export run_pybamm

"""
    run_pybamm(; model_name = "DFN", parameter_set = "Chen2020",
                 C_rate = 1.0, t_eval = nothing,
                 temperature = nothing, thermal = false)

Run a PyBaMM simulation from Julia using PythonCall and return the results as a
Julia NamedTuple.

Requires PyBaMM to be installed in the Python environment used by PythonCall.
Install it with, e.g.:

```
using PythonCall
pyimport("pip")          # make sure pip is available
run(`\$(PythonCall.python_executable_path()) -m pip install pybamm`)
```

The function auto-detects the installed PyBaMM version and adapts to its API
(tested with both the legacy 0.2.x series and the modern 24.x+ releases).

# Arguments
- `model_name::String`: PyBaMM model class name. One of `"SPM"`, `"SPMe"`, or `"DFN"`.
- `parameter_set::String`: Name of the PyBaMM parameter set (e.g. `"Chen2020"`, `"Marquis2019"`).
- `C_rate::Float64`: C-rate for CC discharge (default `1.0`).
- `t_eval::Union{Nothing, AbstractVector}`: Time points (s) at which to evaluate.
  If `nothing`, PyBaMM chooses automatically.
- `temperature::Union{Nothing, Float64}`: Ambient temperature in K. If `nothing`
  uses the parameter-set default.
- `thermal::Bool`: When `true`, use the lumped thermal model.

# Returns
A `NamedTuple` with fields:
- `time::Vector{Float64}` – time in seconds
- `voltage::Vector{Float64}` – cell voltage in V
- `current::Vector{Float64}` – cell current in A

# Example
```julia
using BattMo
result = run_pybamm(; model_name = "DFN", parameter_set = "Chen2020", C_rate = 1.0)
```
"""
function run_pybamm(;
	model_name::String = "DFN",
	parameter_set::String = "Chen2020",
	C_rate::Float64 = 1.0,
	t_eval::Union{Nothing, AbstractVector} = nothing,
	temperature::Union{Nothing, Float64} = nothing,
	thermal::Bool = false,
)

	pybamm = pyimport("pybamm")

	# Detect PyBaMM version to handle API differences
	pybamm_version = pyconvert(String, pybamm.__version__)
	is_legacy = startswith(pybamm_version, "0.")

	# Select model
	if thermal
		options = pydict(Dict("thermal" => "lumped"))
		py_model = if model_name == "SPM"
			pybamm.lithium_ion.SPM(; options)
		elseif model_name == "SPMe"
			pybamm.lithium_ion.SPMe(; options)
		elseif model_name == "DFN"
			pybamm.lithium_ion.DFN(; options)
		else
			error("Unsupported PyBaMM model: $model_name. Use \"SPM\", \"SPMe\", or \"DFN\".")
		end
	else
		py_model = if model_name == "SPM"
			pybamm.lithium_ion.SPM()
		elseif model_name == "SPMe"
			pybamm.lithium_ion.SPMe()
		elseif model_name == "DFN"
			pybamm.lithium_ion.DFN()
		else
			error("Unsupported PyBaMM model: $model_name. Use \"SPM\", \"SPMe\", or \"DFN\".")
		end
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
		# Default: discharge for 1 hour scaled by C-rate
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

	return (time = time_s, voltage = voltage, current = current)
end
