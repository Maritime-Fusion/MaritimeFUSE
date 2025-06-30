"""
    case_parameters(:Yinsen)
Yinsen
"""

function case_parameters(::Type{Val{:Yinsen}})
    ini = ParametersInits()
    act = ParametersActors()

    ini.general.casename = "Yinsen"
    ini.general.init_from = :scalars 

    ini.build.symmetric = true 
    ini.build.divertors = :double 

    ini.equilibrium.B0 = 8.8
    ini.equilibrium.ip = 10.3e6
    ini.equilibrium.xpoints = :double 
    ini.equilibrium.boundary_from = :scalars 
    ini.equilibrium.R0 = 2.85
    ini.equilibrium.ϵ = 0.31
    ini.equilibrium.κ = 1.8
    ini.equilibrium.δ = 0.8 

    layers = OrderedCollections.OrderedDict{Symbol,Float64}()
    layers[:gap_OH] = 0.43
    layers[:OH] = 0.22

    # layers[:gap_OH_TF] = 0.1 # uncomment if not bucked 
    layers[:hfs_TF] = 0.7
    layers[:hfs_gap_TF_low_temp_shield] = 0.05
    layers[:hfs_low_temp_shield] = 0.1
    layers[:hfs_blanket] = 0.23
    layers[:hfs_vacuum_vessel] = 0.035
    layers[:hfs_wall] = 0.055

    layers[:plasma] = 1.88

    layers[:lfs_wall] = 0.055
    layers[:lfs_vacuum_vessel] = 0.035
    layers[:lfs_blanket] = 0.46
    layers[:lfs_low_temp_shield] = 0.05
    layers[:lfs_gap_low_temp_shield_TF] = 0.09
    layers[:lfs_TF] = 0.7

    layers[:gap_cryostat] = 0.5
    layers[:cryostat] = 0.10 # borrowed from DTT case

    ini.build.layers = layers
    ini.build.layers[:OH].coils_inside = 6
    ini.build.layers[:gap_cryostat].coils_inside = 8

    ini.oh.technology = :rebco
    ini.pf_active.technology = :rebco 
    ini.tf.technology = :rebco 

    ini.tf.n_coils = 16
    ini.tf.shape = :princeton_D
    ini.center_stack.bucked = true

    resize!(ini.ic_antenna, 1)
    ini.ic_antenna[1].power_launched = 7.5e6

    ini.core_profiles.Te_core = 27.5e3
    ini.core_profiles.Te_shaping = 1.8
    ini.core_profiles.Ti_Te_ratio = 0.72
    ini.core_profiles.ne_setting = :ne_ped
    ini.core_profiles.ne_value = 75e19
    ini.core_profiles.ne_shaping = 0.9 # check this 
    ini.core_profiles.zeff = 2.0
    ini.core_profiles.bulk = :DT
    ini.core_profiles.impurity = :Ne
    ini.core_profiles.helium_fraction = 0.01
    ini.core_profiles.rot_core = 0.0

    ini.requirements.flattop_duration = 300.0
    ini.requirements.coil_j_margin = 0.2
    ini.requirements.tritium_breeding_ratio = 1.05

    return ini, act
end