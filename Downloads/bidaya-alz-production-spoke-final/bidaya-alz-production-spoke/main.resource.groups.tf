module "resource_groups" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.2"

  for_each = { for key, value in module.config.outputs.connectivity_resource_groups : key => value if try(value.settings.enabled, true) }

  name             = each.value.name
  location         = each.value.location
  enable_telemetry = var.enable_telemetry
  tags             = try(each.value.tags, null) == null ? module.config.outputs.tags : each.value.tags

  providers = {
    azurerm = azurerm.connectivity
  }
}


# Create the Bidaya monitoring resource group in the Management subscription.
# The Log Analytics resource group is created by the ALZ management module.
module "management_resource_groups" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.2"

  for_each = local.management_resource_groups

  name             = each.value.name
  location         = each.value.location
  enable_telemetry = var.enable_telemetry
  tags             = module.config.outputs.tags

  providers = {
    azurerm = azurerm.management
  }
}
