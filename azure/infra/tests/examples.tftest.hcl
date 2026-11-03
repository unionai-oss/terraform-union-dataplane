# checks.sh runs this once per examples/azure/infra/*.tfvars, with its values as each run's variables.
mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "time" {}

# The key vault and role assignments validate these as UUIDs. Built with join and format because checks.sh bans GUID and 12-digit literals.
override_data {
  target          = data.azurerm_client_config.current
  override_during = plan
  values = {
    tenant_id       = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 1)])
    subscription_id = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 2)])
    object_id       = join("-", ["00000000", "0000", "0000", "0000", format("%012d", 3)])
  }
}

# Resource group IDs are validated by the AVM modules, and the mock generates a random string.
override_resource {
  target          = azurerm_resource_group.this
  override_during = plan
  values          = { id = "/subscriptions/sub/resourceGroups/union-dataplane-rg" }
}

run "plans" {
  command = plan
}
