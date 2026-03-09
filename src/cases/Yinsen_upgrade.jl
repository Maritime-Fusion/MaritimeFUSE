function case_parameters(::Val{:Yinsen_upgrade})
    ini = ParametersInits()
    act = ParametersActors()

    ini.general.casename = "Yinsen_upgrade"
    ini.general.init_from = :scalars 

    ini.build.symmetric = true 
    ini.build.divertors = :double 

    ini.equilibrium.B0 = 9.0
    ini.equilibrium.ip = 7e6
    ini.equilibrium.xpoints = :double 
    ini.equilibrium.boundary_from = :scalars 
    ini.equilibrium.R0 = 2.97
    ini.equilibrium.ϵ = 0.327 # a = 0.97
    ini.equilibrium.κ = 1.8
    ini.equilibrium.δ = 0.4

    ini.build.n_first_wall_conformal_layers = 4
    layers = OrderedCollections.OrderedDict{Symbol,Float64}()
    layers[:gap_OH] = 0.52
    layers[:OH] = 0.316

    # layers[:gap_OH_TF] = 0.1 # uncomment if not bucked 
    layers[:hfs_TF] = 0.4
    layers[:hfs_gap_TF_low_temp_shield] = 0.103 # combined last few layers into gap
    layers[:hfs_hfh2_shield] = 0.073
    layers[:hfs_WC_shield] = 0.145
    layers[:hfs_vessel_flibe] = 0.031
    layers[:hfs_blanket_outer] = 0.314
    layers[:hfs_vacuum_vessel_outer] = 0.036
    layers[:hfs_blanket_inner] = 0.021
    layers[:hfs_vacuum_vessel_inner] = 0.016
    layers[:hfs_wall] = 0.023

    layers[:plasma] = 1.943

    layers[:lfs_wall] = 0.023
    layers[:lfs_vacuum_vessel_inner] = 0.016
    layers[:lfs_blanket_inner] = 0.021
    layers[:lfs_vacuum_vessel_outer] = 0.036
    layers[:lfs_blanket_outer] = 0.314
    layers[:lfs_vessel_flibe] = 0.031
    layers[:lfs_WC_shield] = 0.145
    layers[:lfs_hfh2_shield] = 0.073
    layers[:lfs_gap_low_temp_shield_TF] = 0.103
    layers[:lfs_TF] = 0.4

    layers[:gap_cryostat] = 0.340
    layers[:cryostat] = 0.104

    ini.build.layers = layers
    ini.build.layers[:OH].coils_inside = 6
    ini.build.layers[:gap_cryostat].coils_inside = 8
    ini.build.layers[:hfs_blanket_outer].material = :flibe
    ini.build.layers[:lfs_blanket_outer].material = :flibe
    ini.build.layers[:hfs_blanket_inner].material = :flibe
    ini.build.layers[:lfs_blanket_inner].material = :flibe
    ini.build.layers[:lfs_vacuum_vessel_outer].material = :inconel 
    ini.build.layers[:lfs_vacuum_vessel_inner].material = :inconel 
    ini.build.layers[:hfs_vacuum_vessel_outer].material = :inconel 
    ini.build.layers[:hfs_vacuum_vessel_inner].material = :inconel

    ini.oh.technology = :rebco
    ini.pf_active.technology = :rebco 
    ini.tf.technology = :rebco 

    ini.tf.n_coils = 16
    ini.tf.shape = :princeton_D
    ini.center_stack.bucked = true

    resize!(ini.ic_antenna, 1)
    ini.ic_antenna[1].power_launched = 10e6
    ini.ic_antenna[1].efficiency_conversion = 0.7
    ini.ic_antenna[1].efficiency_coupling = 0.85

    resize!(act.ActorSimpleIC.actuator, 1)
    act.ActorSimpleIC.actuator[1].rho_0 = 0.2

    ini.core_profiles.Te_core = 27.5e3
    ini.core_profiles.Te_shaping = 2.0
    ini.core_profiles.Ti_Te_ratio = 1.0
    ini.core_profiles.ne_setting = :greenwald_fraction_ped
    ini.core_profiles.ne_value = 0.55 * 0.75
    ini.core_profiles.ne_shaping = 2.5
    ini.core_profiles.zeff = 2.0
    ini.core_profiles.bulk = :DT
    ini.core_profiles.impurity = :Ne
    ini.core_profiles.helium_fraction = 0.1
    ini.core_profiles.rot_core = 0.0

    act.ActorTGLF.model = :TGLFNN
    act.ActorTGLF.tglfnn_model = "sat0quench_em_d3d_azf+1"
    act.ActorFluxMatcher.algorithm = :old_anderson
    act.ActorFluxMatcher.max_iterations = 500
    act.ActorBlanket.blanket_multiplier = 1.14

    ini.requirements.flattop_duration = 300.0
    ini.requirements.coil_j_margin = 0.1
    ini.requirements.tritium_breeding_ratio = 1.05
    ini.requirements.power_electric_net = 25e6

    return ini, act
end