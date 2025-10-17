#= =================== =#
#  ActorPFTapeCalculator  #
#= =================== =#
@actor_parameters_struct ActorPFTapeCalculator{T} begin
    # REBCO tape specifications
    tape_width::Entry{Float64} = Entry{Float64}("m", "Width of REBCO tape"; default=0.004)  # 4mm typical
    tape_thickness::Entry{Float64} = Entry{Float64}("m", "Thickness of REBCO tape"; default=0.0001)  # 0.1mm typical
    tape_cost_per_kAm::Entry{Float64} = Entry{Float64}("\$/kA⋅m", "Cost of REBCO tape"; default=10.0)  # Need to fill from vendor data
    safety_margin::Entry{Float64} = Entry{Float64}("-", "Safety margin factor (operate at Ic/margin)"; default=1.5)
    
    # Material properties
    temperature::Entry{Float64} = Entry{Float64}("K", "Operating temperature for critical current calculation"; default=20.0)  # Typical for fusion magnets
    
    # Calculation options
    fill_radial_space::Entry{Bool} = Entry{Bool}("-", "Use all available radial space (more parallel tapes than needed)"; default=false)
    verbose::Entry{Bool} = act_common_parameters(; verbose=false)
    do_plot::Entry{Bool} = act_common_parameters(; do_plot=false)
end

mutable struct ActorPFTapeCalculator{D,P} <: SingleAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::OverrideParameters{P,FUSEparameters__ActorPFTapeCalculator{P}}
    total_tape_length::Float64
    total_tape_cost::Float64
    total_kAm::Float64
    coil_details::Vector{Dict{String,Any}}  # Store per-coil breakdown
end

"""
    ActorPFTapeCalculator(dd::IMAS.dd, act::ParametersAllActors; kw...)

Calculates REBCO tape requirements for PF coils based on their geometry and current requirements.

# Physics basis
For each coil, calculates:
- Critical current per tape based on local magnetic field using FusionMaterials
- Number of parallel tapes needed: N_parallel = I_total / (I_c / margin)
- Number of turns that fit vertically: N_turns = floor(height / tape_thickness)
- Average circumference per turn: 2π × r_avg
- Total tape length: N_parallel × N_turns × 2π × r_avg
- Total kA⋅m: I_total × N_turns × 2π × r_avg
- Cost: (kA⋅m) × (\$/kA⋅m)

# Constraints checked
- Verifies N_parallel fits within radial build
- Verifies N_turns fits within vertical build
- Warns if geometry is insufficient for current requirements

# Key inputs (from dd.pf_active.coil[])
- Current per coil: coil.current.data
- Coil geometry: coil.element[].geometry (position, dimensions)
- Maximum magnetic field: coil.b_field_max_timed.data (used for Ic calculation)
- Material properties: dd.build.oh.technology or dd.build.pf_active.technology

# Key outputs
- Updates coil.element[].turns_with_sign with calculated N_turns
- Stores total tape length and cost in actor fields
- Stores detailed breakdown per coil in actor.coil_details
- Optionally prints detailed breakdown per coil

# REBCO tape parameters to specify
- `tape_width`, `tape_thickness`: Physical dimensions
  * Common widths: 2mm, 4mm, 6mm, 12mm
  * Typical thickness: ~0.1mm
- `tape_cost_per_kAm`: Current market price
  * Typical range: \$5-20/kA⋅m depending on Ic rating and volume
- `temperature`: Operating temperature for critical current lookup
  * Typical: 20K for fusion magnets (vs 77K for other applications)

!!! note
    Must run after ActorPFdesign or ActorPFactive to have coil currents and fields defined.
    Critical current is automatically calculated based on local magnetic field for each coil.
"""
function ActorPFTapeCalculator(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorPFTapeCalculator(dd, act.ActorPFTapeCalculator; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function ActorPFTapeCalculator(dd::IMAS.dd, par::FUSEparameters__ActorPFTapeCalculator; kw...)
    logging_actor_init(ActorPFTapeCalculator)
    par = OverrideParameters(par; kw...)
    return ActorPFTapeCalculator(dd, par, 0.0, 0.0, 0.0, Dict{String,Any}[])
end

"""
    _step(actor::ActorPFTapeCalculator)

Calculates tape requirements for each PF coil and updates coil.element[].turns_with_sign
"""
function _step(actor::ActorPFTapeCalculator{T}) where {T<:Real}
    dd = actor.dd
    par = actor.par
    
    # Reset totals
    actor.total_tape_length = 0.0
    actor.total_tape_cost = 0.0
    actor.total_kAm = 0.0
    empty!(actor.coil_details)
    
    if par.verbose
        println("\n" * "="^80)
        println("REBCO Tape Requirements Calculation")
        println("="^80)
        println("Tape specifications:")
        println("  Width: $(par.tape_width*1000) mm")
        println("  Thickness: $(par.tape_thickness*1000) mm")
        println("  Operating temperature: $(par.temperature) K")
        println("  Safety margin: $(par.safety_margin)x")
        println("  Cost: \$$(par.tape_cost_per_kAm)/kA⋅m")
        println("="^80)
    end
    
    for (coil_idx, coil) in enumerate(dd.pf_active.coil)
        # Get coil current
        I_total = abs(@ddtime(coil.current.data))  # Total current the coil must carry
        
        if I_total == 0.0
            if par.verbose
                println("\nCoil $(coil.name): Skipping (zero current)")
            end
            continue
        end
        
        # Get coil geometry
        element = coil.element[1]
        geom = element.geometry
        
        # Get coil position and dimensions
        r_coil = element.geometry.rectangle.r  # Radial position of coil center
        z_coil = element.geometry.rectangle.z  # Vertical position of coil center
        width_coil = element.geometry.rectangle.width  # Radial build
        height_coil = element.geometry.rectangle.height  # Vertical build
        
        # Calculate average radius (for mean turn circumference)
        r_avg = r_coil  # Center of coil is already at average radius
        
        # Get magnetic field at this coil location
        B_field = abs(only(coil.b_field_max_timed.data))  # Tesla
        
        # Get material and calculate critical current density at this field
        if IMAS.is_ohmic_coil(coil)
            coil_material = FusionMaterials.Material(dd.build.oh.technology)
        else
            coil_material = FusionMaterials.Material(dd.build.pf_active.technology)
        end
        
        # Critical current density in A/m²
        J_c = coil_material.critical_current_density(; Bext=B_field, temperature=par.temperature)
        
        # Calculate critical current per tape
        # Cross-sectional area of REBCO carrying layer (typically much thinner than total tape thickness)
        # For simplicity, use tape_width × tape_thickness, but in reality the superconducting layer is ~1-2 microns
        # You may want to add a parameter for the actual SC layer thickness
        tape_cross_section = par.tape_width * par.tape_thickness  # m²
        I_c_per_tape = J_c * tape_cross_section  # Amperes
        I_safe_per_tape = I_c_per_tape / par.safety_margin
        
        # Calculate number of turns that fit vertically (DO THIS FIRST)
        N_turns = floor(Int, height_coil / par.tape_thickness)
        
        if N_turns == 0
            @warn "Coil $(coil.name): Height too small ($(height_coil*1000) mm) for even one turn!"
            continue
        end

        # Now calculate current PER TURN (not total current)
        I_per_turn = I_total / N_turns  # This is the current each turn must carry

        # Calculate number of parallel tapes needed (for current per turn)
        N_parallel_needed = ceil(Int, I_per_turn / I_safe_per_tape)
        
        # Check if parallel tapes fit radially
        N_parallel_max = floor(Int, width_coil / par.tape_width)
        
        if N_parallel_needed > N_parallel_max
            @warn "Coil $(coil.name): Need $N_parallel_needed parallel tapes but only $N_parallel_max fit in radial build ($(width_coil*1000) mm)! Consider wider tape or larger coil."
            N_parallel = N_parallel_max  # Use what fits
        elseif par.fill_radial_space
            N_parallel = N_parallel_max  # Use all available space for extra margin
        else
            N_parallel = N_parallel_needed  # Use only what's needed
        end
        
        # Calculate tape length per coil
        circumference_per_turn = 2π * r_avg
        length_per_coil = N_parallel * N_turns * circumference_per_turn
        
        # Calculate kA⋅m (cost basis)
        kAm_per_coil = (I_total / 1000.0) * N_turns * circumference_per_turn
        
        # Calculate cost
        cost_per_coil = kAm_per_coil * par.tape_cost_per_kAm
        
        # Update totals
        actor.total_tape_length += length_per_coil
        actor.total_kAm += kAm_per_coil
        actor.total_tape_cost += cost_per_coil
        
        # Store detailed breakdown
        coil_detail = Dict{String,Any}(
            "name" => coil.name,
            "r" => r_coil,
            "z" => z_coil,
            "width" => width_coil,
            "height" => height_coil,
            "current" => I_total,
            "B_field" => B_field,
            "J_c" => J_c,
            "I_c_per_tape" => I_c_per_tape,
            "N_parallel" => N_parallel,
            "N_parallel_needed" => N_parallel_needed,
            "N_parallel_max" => N_parallel_max,
            "N_turns" => N_turns,
            "circumference" => circumference_per_turn,
            "tape_length" => length_per_coil,
            "kAm" => kAm_per_coil,
            "cost" => cost_per_coil
        )
        push!(actor.coil_details, coil_detail)
        
        # Store number of turns in IMAS structure
        # Use turns_with_sign to preserve polarity of current
        sign_current = sign(@ddtime(coil.current.data))
        element.turns_with_sign = sign_current * N_turns
        
        if par.verbose
            println("\n$(coil.name):")
            println("  Position: R=$(round(r_coil, digits=3)) m, Z=$(round(z_coil, digits=3)) m")
            println("  Dimensions: $(round(width_coil*1000, digits=1)) mm (radial) × $(round(height_coil*1000, digits=1)) mm (vertical)")
            println("  Current requirement: $(round(I_total/1000, digits=1)) kA")
            println("  Magnetic field: $(round(B_field, digits=2)) T")
            println("  Critical current density: $(round(J_c/1e9, digits=2)) GA/m²")
            println("  Critical current per tape: $(round(I_c_per_tape, digits=1)) A")
            println("  Safe current per tape: $(round(I_safe_per_tape, digits=1)) A")
            println("  Parallel tapes: $N_parallel ($(N_parallel_needed) needed, $(N_parallel_max) max)")
            println("  Turns: $N_turns")
            println("  Avg circumference: $(round(circumference_per_turn, digits=2)) m")
            println("  Tape length: $(round(length_per_coil/1000, digits=2)) km")
            println("  kA⋅m: $(round(kAm_per_coil, digits=2)) kA⋅m")
            println("  Cost: \$$(round(cost_per_coil, digits=2))")
        end
    end
    
    return actor
end

"""
    _finalize(actor::ActorPFTapeCalculator)

Prints summary of total tape requirements across all coils
"""
function _finalize(actor::ActorPFTapeCalculator{D,P}) where {D<:Real,P<:Real}
    par = actor.par
    
    if par.verbose || true  # Always print summary
        println("\n" * "="^80)
        println("Total REBCO Tape Requirements (All PF Coils)")
        println("="^80)
        println("  Total tape length: $(round(actor.total_tape_length/1000, digits=2)) km")
        println("  Total kA⋅m: $(round(actor.total_kAm, digits=2)) kA⋅m")
        println("  Total cost: \$$(round(actor.total_tape_cost, digits=2))")
        println("="^80)
    end
    
    if par.do_plot
        display(plot(actor))
    end
    
    return actor
end
