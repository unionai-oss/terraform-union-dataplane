region = "eastus2"

# The AKS API endpoint is public (nodes are private); limit it to the addresses you run Terraform and kubectl from.
api_server_authorized_ip_ranges = ["203.0.113.0/24"]
