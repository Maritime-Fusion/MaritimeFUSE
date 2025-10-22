#= =================== =#
#  ActorPFTapeCalculator  #
#= =================== =#
@actor_parameters_struct ActorPFTapeCalculator{T} begin
    # REBCO tape specifications
    tape_width::Entry{Float64} = Entry{Float64}("m", "Width of REBCO tape"; default=0.004)  # 4mm typical
    tape_thickness::Entry{Float64} = Entry{Float64}("m", "Thickness of REBCO tape"; default=0.0001)  # 0.1mm typical
    tape_cost_per_kAm::Entry{Float64} = Entry{Float64}("\$/kA⋅m", "Cost of REBCO tape"; default=10.0)
    safety_margin::Entry{Float64} = Entry{Float64}("-", "Safety margin factor (operate at Ic/margin)"; default=1.5)
    
    # Conductor specifications (assembled from multiple tapes)
    conductor_critical_current_low_field::Entry{Float64} = Entry{Float64}("A", "Conductor Ic at low field (<5T)"; default=45e3)  # 45 kA
    conductor_critical_current_mid_field::Entry{Float64} = Entry{Float64}("A", "Conductor Ic at mid field (5-10T)"; default=40e3)  # 40 kA
    conductor_critical_current_high_field::Entry{Float64} = Entry{Float64}("A", "Conductor Ic at high field (>10T)"; default=35e3)  # 35 kA
    
    # Material properties
    temperature::Entry{Float64} = Entry{Float64}("K", "Operating temperature for critical current calculation"; default=20.0)
    
    # Conductor structure
    conductor_structure_factor::Entry{Float64} = Entry{Float64}("-", "Multiplier for conductor thickness (accounts for insulation, structure)"; default=1.3)
    turn_insulation_thickness::Entry{Float64} = Entry{Float64}("m", "Additional insulation between turns"; default=0.001)  # 1mm
    
    # Calculation options
    verbose::Entry{Bool} = act_common_parameters(; verbose=false)
    do_plot::Entry{Bool} = act_common_parameters(; do_plot=false)
end

mutable struct ActorPFTapeCalculator{D,P} <: SingleAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::OverrideParameters{P,FUSEparameters__ActorPFTapeCalculator{P}}
    total_tape_length::Float64
    total_tape_cost::Float64
    total_kAm::Float64
    coil_details::Vector{Dict{String,Any}}
end

"""
    ActorPFTapeCalculator(dd::IMAS.dd, act::ParametersAllActors; kw...)

Calculates REBCO tape requirements for PF coils based on their geometry and current requirements.

# Physics basis
HTS conductors are assembled from multiple REBCO tapes stacked together:
- Each conductor carries 20-40 kA (operating current)
- Conductor critical current: 35-45 kA depending on magnetic field
- Multiple tapes are stacked (typically 100-200 tapes per conductor at high field)
- Conductors are wound in layers (radially and vertically) to fit within coil geometry

Winding arrangement:
- Turns are wound radially in each layer
- Multiple layers stack vertically to accommodate all required turns
- This is similar to a "pancake" or "layer-wound" coil configuration

For each coil:
1. Determine conductor operating current based on local field
2. Calculate number of turns: N_turns = I_total / I_operating_conductor
3. Calculate tapes per conductor based on tape Ic vs conductor Ic
4. Determine conductor cross-section (compact rectangular stacking)
5. Calculate how turns fit in layers (radially and vertically)
6. Calculate total tape length: N_turns × circumference × tapes_per_conductor
7. Calculate cost based on kA⋅m

# Key inputs
- Coil current and geometry from dd.pf_active.coil[]
- Conductor critical currents (35-45 kA) based on field strength
- Individual tape critical current estimates for cost calculation

# Key outputs
- Updates coil.element[].turns_with_sign
- Total tape length and cost
- Detailed per-coil breakdown including winding configuration
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
        println("Individual tape specifications:")
        println("  Width: $(par.tape_width*1000) mm")
        println("  Thickness: $(par.tape_thickness*1000) mm")
        println("Conductor specifications:")
        println("  Operating temperature: $(par.temperature) K")
        println("  Safety margin: $(par.safety_margin)x")
        println("  Ic at low field (<5T): $(par.conductor_critical_current_low_field/1000) kA")
        println("  Ic at mid field (5-10T): $(par.conductor_critical_current_mid_field/1000) kA")
        println("  Ic at high field (>10T): $(par.conductor_critical_current_high_field/1000) kA")
        println("Winding configuration:")
        println("  Layer-wound (pancake style) with vertical stacking")
        println("  Turn insulation: $(par.turn_insulation_thickness*1000) mm")
        println("  Cost: \$$(par.tape_cost_per_kAm)/kA⋅m")
        println("="^80)
    end
    
    for (coil_idx, coil) in enumerate(dd.pf_active.coil)
        # Get coil current requirement
        I_total = abs(@ddtime(coil.current.data))  # Total current the coil must carry (Amperes)
        
        if I_total == 0.0
            if par.verbose
                println("\nCoil $(coil.name): Skipping (zero current)")
            end
            continue
        end
        
        # Get coil geometry
        element = coil.element[1]
        r_coil = element.geometry.rectangle.r
        z_coil = element.geometry.rectangle.z
        width_coil = element.geometry.rectangle.width  # Radial build available
        height_coil = element.geometry.rectangle.height  # Vertical build available
        
        # Get magnetic field at this coil location
        B_field = abs(only(coil.b_field_max_timed.data))  # Tesla
        
        # Determine conductor critical current based on field
        I_c_conductor = if B_field > 10.0
            par.conductor_critical_current_high_field
        elseif B_field > 5.0
            par.conductor_critical_current_mid_field
        else
            par.conductor_critical_current_low_field
        end
        
        # Operating current for the conductor (with safety margin)
        I_operating_conductor = I_c_conductor / par.safety_margin
        
        # Calculate number of turns needed
        N_turns = ceil(Int, I_total / I_operating_conductor)
        
        # Estimate individual tape critical current for cost calculation
        # These are rough estimates based on typical REBCO performance at 20K
        I_c_per_tape = if B_field > 10.0
            175.0  # A, conservative at 13T
        elseif B_field > 5.0
            250.0  # A, at mid field
        else
            450.0  # A, at low field where REBCO performs well
        end
        
        # Calculate tapes per conductor (for cost estimation)
        tapes_per_conductor = ceil(Int, I_c_conductor / I_c_per_tape)
        
        # Estimate conductor geometry
        # Stack tapes in a roughly square cross-section for compactness
        tapes_per_side = ceil(Int, sqrt(tapes_per_conductor))
        
        # Conductor bare dimensions (before insulation/structure)
        conductor_radial_bare = tapes_per_side * par.tape_width
        conductor_vertical_bare = tapes_per_side * par.tape_thickness
        
        # Add structure factor for insulation, potting, etc.
        conductor_radial_thickness = conductor_radial_bare * par.conductor_structure_factor
        conductor_vertical_thickness = conductor_vertical_bare * par.conductor_structure_factor
        
        # Add turn-to-turn insulation
        conductor_radial_with_insulation = conductor_radial_thickness + par.turn_insulation_thickness
        conductor_vertical_with_insulation = conductor_vertical_thickness + par.turn_insulation_thickness
        
        # Calculate winding arrangement - layer wound configuration
        # Turns are wound radially, then stacked vertically in layers
        turns_per_radial_layer = floor(Int, width_coil / conductor_radial_with_insulation)
        
        if turns_per_radial_layer == 0
            @warn "Coil $(coil.name): Conductor ($(round(conductor_radial_with_insulation*1000, digits=1)) mm) too wide to fit in radial build ($(round(width_coil*1000, digits=1)) mm)!"
            continue
        end
        
        # Calculate number of vertical layers needed
        n_vertical_layers = ceil(Int, N_turns / turns_per_radial_layer)
        
        # Check if layers fit vertically
        vertical_build_needed = n_vertical_layers * conductor_vertical_with_insulation
        fits_vertically = vertical_build_needed <= height_coil
        
        # Radial build used (may be less than available)
        radial_build_used = turns_per_radial_layer * conductor_radial_with_insulation
        fits_radially = radial_build_used <= width_coil  # Should always be true by construction
        
        if !fits_vertically
            @warn "Coil $(coil.name): $n_vertical_layers layers need $(round(vertical_build_needed*1000, digits=1)) mm vertically but only $(round(height_coil*1000, digits=1)) mm available!"
        end
        
        # Calculate tape length per coil
        r_avg = r_coil
        circumference_per_turn = 2π * r_avg
        total_conductor_length = N_turns * circumference_per_turn
        total_tape_length = total_conductor_length * tapes_per_conductor
        
        # Calculate kA⋅m (for cost calculation)
        # This is based on the actual current × conductor length
        kAm_per_coil = (I_total / 1000.0) * total_conductor_length
        
        # Calculate cost
        cost_per_coil = kAm_per_coil * par.tape_cost_per_kAm
        
        # Update totals
        actor.total_tape_length += total_tape_length
        actor.total_kAm += kAm_per_coil
        actor.total_tape_cost += cost_per_coil
        
        # Store detailed breakdown
        coil_detail = Dict{String,Any}(
            "name" => coil.name,
            "r" => r_coil,
            "z" => z_coil,
            "width" => width_coil,
            "height" => height_coil,
            "current_requirement" => I_total,
            "B_field" => B_field,
            "I_c_conductor" => I_c_conductor,
            "I_operating_conductor" => I_operating_conductor,
            "I_c_per_tape" => I_c_per_tape,
            "N_turns" => N_turns,
            "tapes_per_conductor" => tapes_per_conductor,
            "conductor_radial" => conductor_radial_with_insulation,
            "conductor_vertical" => conductor_vertical_with_insulation,
            "turns_per_layer" => turns_per_radial_layer,
            "n_layers" => n_vertical_layers,
            "radial_build_used" => radial_build_used,
            "vertical_build_needed" => vertical_build_needed,
            "fits_radially" => fits_radially,
            "fits_vertically" => fits_vertically,
            "circumference" => circumference_per_turn,
            "tape_length" => total_tape_length,
            "kAm" => kAm_per_coil,
            "cost" => cost_per_coil
        )
        push!(actor.coil_details, coil_detail)
        
        # Store number of turns in IMAS structure
        sign_current = sign(@ddtime(coil.current.data))
        element.turns_with_sign = sign_current * N_turns
        
        if par.verbose
            println("\n$(coil.name):")
            println("  Position: R=$(round(r_coil, digits=3)) m, Z=$(round(z_coil, digits=3)) m")
            println("  Dimensions: $(round(width_coil*1000, digits=1)) mm (radial) × $(round(height_coil*1000, digits=1)) mm (vertical)")
            println("  Current requirement: $(round(I_total/1000, digits=1)) kA")
            println("  Magnetic field: $(round(B_field, digits=2)) T")
            println("  Conductor Ic: $(round(I_c_conductor/1000, digits=1)) kA")
            println("  Conductor operating current: $(round(I_operating_conductor/1000, digits=1)) kA")
            println("  Number of turns: $N_turns")
            println("  Tape Ic estimate: $(round(I_c_per_tape, digits=1)) A")
            println("  Tapes per conductor: $tapes_per_conductor")
            println("  Conductor dimensions: $(round(conductor_radial_with_insulation*1000, digits=1)) mm × $(round(conductor_vertical_with_insulation*1000, digits=1)) mm (with insulation)")
            println("  Winding configuration:")
            println("    - Turns per radial layer: $turns_per_radial_layer")
            println("    - Number of vertical layers: $n_vertical_layers")
            println("    - Radial build used: $(round(radial_build_used*1000, digits=1)) mm / $(round(width_coil*1000, digits=1)) mm")
            println("    - Vertical build needed: $(round(vertical_build_needed*1000, digits=1)) mm / $(round(height_coil*1000, digits=1)) mm")
            println("  Fit status:")
            println("    - Radial: $(fits_radially ? "✓" : "✗")")
            println("    - Vertical: $(fits_vertically ? "✓" : "✗")")
            println("  Avg turn circumference: $(round(circumference_per_turn, digits=2)) m")
            println("  Total tape length: $(round(total_tape_length/1000, digits=2)) km")
            println("  kA⋅m: $(round(kAm_per_coil/1e6, digits=2)) M kA⋅m")
            println("  Cost: \$$(round(cost_per_coil/1e6, digits=2))M")
        end
    end
    
    return actor
end

function _finalize(actor::ActorPFTapeCalculator{D,P}) where {D<:Real,P<:Real}
    par = actor.par
    
    if par.verbose || true
        println("\n" * "="^80)
        println("Total REBCO Tape Requirements (All PF Coils)")
        println("="^80)
        println("  Total tape length: $(round(actor.total_tape_length/1000, digits=2)) km")
        println("  Total kA⋅m: $(round(actor.total_kAm/1e6, digits=2)) M kA⋅m")
        println("  Total cost: \$$(round(actor.total_tape_cost/1e6, digits=2))M")
        println("="^80)
    end
    
    if par.do_plot
        display(plot(actor))
    end
    
    return actor
end