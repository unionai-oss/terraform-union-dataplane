region = "eastus2"
name   = "union-gpu"

worker_node_pool = {
  max_nodes = 20
}

gpu_node_pool = {
  enabled   = true
  max_nodes = 4
}

enable_key_vault = true

tags = {
  team = "data"
}

# The AKS API endpoint is public (nodes are private); limit it to the addresses you run Terraform and kubectl from.
api_server_authorized_ip_ranges = ["203.0.113.0/24"]
