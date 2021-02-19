# Generate the Policy Assignment configurations for the specified archetype.
# Logic implemented to determine whether Policy Assignments
# need to be loaded to save on compute and memory resources
# when none defined in archetype definition.
locals {
  archetype_policy_assignments_list      = local.archetype_definition.policy_assignments
  archetype_policy_assignments_specified = try(length(local.archetype_policy_assignments_list) > 0, false)
}

# If Policy Assignments are specified in the archetype definition, generate a list of all Policy Assignment files from the built-in and custom library locations
locals {
  builtin_policy_assignments_from_json = local.archetype_policy_assignments_specified ? tolist(fileset(local.builtin_library_path, "**/policy_assignment_*.json")) : null
  builtin_policy_assignments_from_yaml = local.archetype_policy_assignments_specified ? tolist(fileset(local.builtin_library_path, "**/policy_assignment_*.{yml,yaml}")) : null
  custom_policy_assignments_from_json  = local.archetype_policy_assignments_specified && local.custom_library_path_specified ? tolist(fileset(local.custom_library_path, "**/policy_assignment_*.json")) : null
  custom_policy_assignments_from_yaml  = local.archetype_policy_assignments_specified && local.custom_library_path_specified ? tolist(fileset(local.custom_library_path, "**/policy_assignment_*.{yml,yaml}")) : null
}

# If Policy Assignment files exist, load content into dataset
locals {
  builtin_policy_assignments_dataset_from_json = try(length(local.builtin_policy_assignments_from_json) > 0, false) ? {
    for filepath in local.builtin_policy_assignments_from_json :
    filepath => jsondecode(templatefile("${local.builtin_library_path}/${filepath}", local.template_file_vars))
  } : null
  builtin_policy_assignments_dataset_from_yaml = try(length(local.builtin_policy_assignments_from_yaml) > 0, false) ? {
    for filepath in local.builtin_policy_assignments_from_yaml :
    filepath => yamldecode(templatefile("${local.builtin_library_path}/${filepath}", local.template_file_vars))
  } : null
  custom_policy_assignments_dataset_from_json = try(length(local.custom_policy_assignments_from_json) > 0, false) ? {
    for filepath in local.custom_policy_assignments_from_json :
    filepath => jsondecode(templatefile("${local.custom_library_path}/${filepath}", local.template_file_vars))
  } : null
  custom_policy_assignments_dataset_from_yaml = try(length(local.custom_policy_assignments_from_yaml) > 0, false) ? {
    for filepath in local.custom_policy_assignments_from_yaml :
    filepath => yamldecode(templatefile("${local.custom_library_path}/${filepath}", local.template_file_vars))
  } : null
}

# If Policy Assignment datasets exist, convert to map
locals {
  builtin_policy_assignments_map_from_json = try(length(local.builtin_policy_assignments_dataset_from_json) > 0, false) ? {
    for key, value in local.builtin_policy_assignments_dataset_from_json :
    value.name => value
    if value.type == local.resource_types.policy_assignment
  } : null
  builtin_policy_assignments_map_from_yaml = try(length(local.builtin_policy_assignments_dataset_from_yaml) > 0, false) ? {
    for key, value in local.builtin_policy_assignments_dataset_from_yaml :
    value.name => value
    if value.type == local.resource_types.policy_assignment
  } : null
  custom_policy_assignments_map_from_json = try(length(local.custom_policy_assignments_dataset_from_json) > 0, false) ? {
    for key, value in local.custom_policy_assignments_dataset_from_json :
    value.name => value
    if value.type == local.resource_types.policy_assignment
  } : null
  custom_policy_assignments_map_from_yaml = try(length(local.custom_policy_assignments_dataset_from_yaml) > 0, false) ? {
    for key, value in local.custom_policy_assignments_dataset_from_yaml :
    value.name => value
    if value.type == local.resource_types.policy_assignment
  } : null
}

# Merge the Policy Assignment maps into a single map.
# If duplicates exist due to a custom Policy Assignment being
# defined to override a built-in definition, this is handled by
# merging the custom policies after the built-in policies.
locals {
  archetype_policy_assignments_map = merge(
    local.builtin_policy_assignments_map_from_json,
    local.builtin_policy_assignments_map_from_yaml,
    local.custom_policy_assignments_map_from_json,
    local.custom_policy_assignments_map_from_yaml,
  )
}

# Generate a map of parameters from the archetype definition and merge
# with the parameters provided using var.parameters.
# Used to determine the parameter values for Policy Assignments.
locals {
  parameters_at_scope = merge(
    local.archetype_definition.archetype_config.parameters,
    local.parameters,
  )
}

# Extract the desired Policy Assignment from archetype_policy_assignments_map.
locals {
  archetype_policy_assignments_output = [
    for policy_assignment in local.archetype_policy_assignments_list :
    {
      resource_id = "${local.provider_path.policy_assignment}${policy_assignment}"
      scope_id    = local.scope_id
      template    = local.archetype_policy_assignments_map[policy_assignment]
      # Also need to generate a set of parameters for each Policy
      # Assignment if provided as part of the parameters
      # variable. These come from the archetype_config object in
      # the enterprise_scale module and are merged with the Policy
      # Assignment template values to provide overrides.
      parameters = contains(keys(local.parameters_at_scope), policy_assignment) ? {
        for parameter_key, parameter_value in local.parameters_at_scope[policy_assignment] :
        parameter_key => {
          # Due to object type limitations in Go, we can only support
          # a single object type in the input parameter for parameters.
          # To support processing parameters with different object
          # types we've added support for converting the input value
          # from JSON but can fallback to the raw value if that fails.
          # This provides backwards compatibility for existing
          # deployments, but also makes it easier to compose the input
          # object if only one parameter value type is needed.
          value = try(jsondecode(parameter_value), parameter_value)
        }
      } : null
    }
  ]
}
