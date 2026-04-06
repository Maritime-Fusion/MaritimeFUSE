function case_parameters(::Val{:Yinsen_upgrade})
    ini = ParametersInits()
    act = ParametersActors()

    ini.general.casename = "Yinsen_upgrade"
    ini.general.init_from = :scalars 

    ini.build.symmetric = true 
    ini.build.divertors = :double 

    ini.equilibrium.B0 = 9.286485472412783
    ini.equilibrium.ip = 9.628203468095273e6
    ini.equilibrium.xpoints = :double 
    ini.equilibrium.boundary_from = :scalars 
    ini.equilibrium.R0 = 3.1787013920965883
    ini.equilibrium.ϵ = 0.32938792404919526
    ini.equilibrium.κ = 1.8011464502597552
    ini.equilibrium.δ = 0.8913532801788087

    ini.build.n_first_wall_conformal_layers = 4
    layers = OrderedCollections.OrderedDict{Symbol,Float64}()
    layers[:gap_OH] = 0.581
    layers[:OH] = 0.438

    # layers[:gap_OH_TF] = 0.1 # uncomment if not bucked 
    layers[:hfs_TF] = 0.5
    layers[:hfs_gap_TF_low_temp_shield] = 0.01
    layers[:hfs_low_temp_shield] = 0.01
    layers[:hfs_gap_neutron_shield_low_temp_shield] = 0.01
    layers[:hfs_neutron_shield] = 0.148
    layers[:hfs_vessel_flibe] = 0.034
    layers[:hfs_blanket_outer] = 0.201
    layers[:hfs_vacuum_vessel_outer] = 0.039
    layers[:hfs_blanket_inner] = 0.022
    layers[:hfs_vacuum_vessel_inner] = 0.017
    layers[:hfs_wall] = 0.025

    layers[:plasma] = 2.274

    layers[:lfs_wall] = 0.025
    layers[:lfs_vacuum_vessel_inner] = 0.017
    layers[:lfs_blanket_inner] = 0.022
    layers[:lfs_vacuum_vessel_outer] = 0.039
    layers[:lfs_blanket_outer] = 0.403
    layers[:lfs_vessel_flibe] = 0.034
    layers[:lfs_neutron_shield] = 0.195
    layers[:lfs_gap_neutron_shield_low_temp_shield] = 0.01
    layers[:lfs_low_temp_shield] = 0.01
    layers[:lfs_gap_low_temp_shield_TF] = 0.01
    layers[:lfs_TF] = 0.5

    layers[:gap_cryostat] = 0.56
    layers[:cryostat] = 0.1

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
    ini.build.layers[:lfs_neutron_shield].material = :tungsten_carbide
    ini.build.layers[:hfs_neutron_shield].material = :tungsten_carbide

    ini.oh.technology = :rebco
    ini.pf_active.technology = :rebco 
    ini.tf.technology = :rebco 

    ini.tf.n_coils = 18
    ini.tf.shape = :princeton_D
    ini.center_stack.bucked = true

    resize!(ini.ic_antenna, 1)
    ini.ic_antenna[1].power_launched = 1.3464985363586068e7
    ini.ic_antenna[1].efficiency_conversion = 0.5
    ini.ic_antenna[1].efficiency_coupling = 0.9

    resize!(act.ActorSimpleIC.actuator, 1)
    act.ActorSimpleIC.actuator[1].rho_0 = 0.2

    ini.core_profiles.Te_core = 27.5e3
    ini.core_profiles.Te_shaping = 2.0
    ini.core_profiles.Ti_Te_ratio = 0.72
    ini.core_profiles.ne_setting = :greenwald_fraction_ped
    ini.core_profiles.ne_value = 0.5020605726007484
    ini.core_profiles.ne_shaping = 2.5
    ini.core_profiles.zeff = 2.0
    ini.core_profiles.bulk = :DT
    ini.core_profiles.impurity = :Ne
    ini.core_profiles.helium_fraction = 0.1
    ini.core_profiles.rot_core = 0.0

    act.ActorTGLF.model = :TGLFNN
    act.ActorTGLF.tglfnn_model = "sat0quench_em_d3d_azf+1"
    act.ActorFluxMatcher.algorithm = :old_anderson
    act.ActorFluxMatcher.rho_transport = 0.2:0.05:0.8
    act.ActorFluxMatcher.max_iterations = 500
    act.ActorEquilibrium.symmetrize = true 
    act.ActorPlasmaLimits.models = [:vertical_stability, :κ_controllability, :q95_gt_2, :beta_troyon_nn]
    act.ActorPFdesign.model = :uniform 
    act.ActorHFSsizing.error_on_technology = false
    act.ActorHFSsizing.error_on_performance = false

    ini.requirements.flattop_duration = 300.0
    ini.requirements.log10_flattop_duration = 2.4771212547196626
    ini.requirements.coil_j_margin = 0.15
    ini.requirements.coil_stress_margin = 0.15
    ini.requirements.Psol_R = 15.0 
    ini.requirements.power_electric_net = 4.0e7
    ini.requirements.lh_power_threshold_fraction = 1.1 
    ini.requirements.tritium_breeding_ratio = 1.1

    return ini, act
end