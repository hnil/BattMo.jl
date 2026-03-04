# # PyBaMM Feature Comparison – TODO List
#
# This file documents the physical effects and features available in PyBaMM and
# tracks which ones are already supported in BattMo.jl, which are in progress,
# and which remain to be implemented.
#
# ## Status Legend
# - ✅ Supported in BattMo.jl
# - 🔧 Partially supported / in progress
# - ❌ Not yet supported
#
# ## Electrochemical Models
# - ✅ Doyle-Fuller-Newman (DFN / P2D)
# - ✅ Single Particle Model (SPM) — via simplified P2D settings
# - ✅ Single Particle Model with electrolyte (SPMe) — via simplified P2D settings
# - ❌ Many-Particle Model (MPM)
# - ❌ Multi-Scale Multi-Domain (MSMD) model
#
# ## Solid-Phase Transport
# - ✅ Full Fickian diffusion in particles
# - ✅ Polynomial approximation (uniform / quadratic / quartic)
# - ❌ Size distribution of particles
#
# ## Electrolyte Transport
# - ✅ Concentrated solution theory (Stefan-Maxwell)
# - ✅ Custom electrolyte conductivity and diffusivity functions (via PythonCall)
#
# ## Electrode Kinetics
# - ✅ Standard Butler-Volmer
# - ❌ Marcus kinetics
# - ❌ Marcus-Hush-Chidsey kinetics
# - ❌ Asymmetric Butler-Volmer (arbitrary transfer coefficients)
#
# ## Thermal Models
# - ✅ Isothermal operation
# - ✅ Arrhenius temperature dependence for rate constant and diffusion
# - 🔧 Lumped thermal model (energy balance)
# - ❌ 1D thermal model (through-cell)
# - ❌ Pouch cell 2D thermal model
#
# ## Degradation – SEI
# - ✅ SEI layer growth model (BattMo: Bolay model; PyBaMM: reaction-limited)
# - ✅ Comparison example: `chen2020_sei_comparison.jl`
# - ❌ Electron-migration limited SEI
# - ❌ Interstitial-diffusion limited SEI
# - ❌ Solvent-diffusion limited SEI (EC reaction)
# - ❌ SEI on cracks
#
# ## Degradation – Lithium Plating
# - ❌ Reversible lithium plating
# - ❌ Irreversible lithium plating
# - ❌ Partially reversible lithium plating
#
# ## Degradation – Other
# - ❌ Active material loss / particle cracking
# - ❌ Loss of lithium inventory (LLI) tracking
#
# ## Geometry
# - ✅ 1D (through-cell, P2D)
# - ✅ Pouch cell (3D)
# - ✅ Cylindrical / jelly-roll (3D)
# - ❌ Half-cell configuration (lithium metal anode)
#
# ## Operating Modes / Cycling Protocols
# - ✅ Constant current (CC) discharge / charge
# - ✅ CCCV (constant-current–constant-voltage)
# - ✅ Multi-cycle CCCV (see `control_protocol_comparison.jl`)
# - 🔧 Arbitrary cycling protocols (multi-step)
# - ❌ Drive-cycle / current profile input
# - ❌ GITT (Galvanostatic Intermittent Titration Technique)
#
# ## Solver and Performance
# - ✅ Direct (LU) linear solver
# - ✅ Iterative solvers with preconditioners (AMG)
# - ✅ Automatic differentiation (ForwardDiff)
# - ❌ Sensitivity analysis (parameter sensitivities via adjoint)
# - ❌ Event-based termination (voltage, capacity, time limits)
#
# ## Parameter Sets
# - ✅ Chen 2020 (LG INR21700 M50)
# - ✅ Xu 2015 – comparison: `xu2015_comparison.jl`
# - ✅ Chayambuka 2022 – comparison: `chayambuka2022_comparison.jl`
# - 🔧 Marquis 2019 – PyBaMM only, comparison: `marquis2019_comparison.jl`
# - 🔧 Ecker 2015 – PyBaMM only, comparison: `ecker2015_comparison.jl`
# - 🔧 Mohtat 2020 – PyBaMM only, comparison: `mohtat2020_comparison.jl`
# - 🔧 OKane 2022 – PyBaMM only, comparison: `okane2022_comparison.jl`
# - 🔧 Ai 2020 – PyBaMM only, comparison: `ai2020_comparison.jl`
#
# ## Output / Post-Processing
# - ✅ Voltage, current, capacity time series
# - ✅ Spatial profiles (concentration, potential, temperature)
# - ✅ Discharge / charge energy and capacity
# - ✅ Round-trip efficiency
# - ❌ Internal resistance extraction
# - ❌ Electrochemical impedance spectroscopy (EIS) — frequency domain
#
# ## PyBaMM Interop
# - ✅ `run_pybamm()` – run PyBaMM simulations from Julia (CC discharge + Experiment cycling)
# - ✅ Comparison examples (Chen 2020 DFN discharge, multi-C-rate, SEI, thermal, SPMe)
# - ✅ Multi-cycle SEI comparison: `chen2020_sei_cycling_comparison.jl`
# - ✅ Parameter-set comparisons: Xu 2015, Chayambuka 2022, Marquis 2019, Ecker 2015,
#      Mohtat 2020, OKane 2022, Ai 2020
# - ✅ Control protocol comparison (CC, CC cycling, CCCV, multi-cycle CCCV):
#      `control_protocol_comparison.jl`
# - ✅ Performance benchmarking framework
