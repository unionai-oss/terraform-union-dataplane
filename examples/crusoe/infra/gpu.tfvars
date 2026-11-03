allow_public_api_endpoint = true
region                    = "us-east1-a"
name                      = "union-gpu"
ssh_public_key            = "ssh-ed25519 AAAAexample user@example.com"

labels = { team = "example" }

nat_gateway_enabled = true

worker_node_pool = { enabled = true }
gpu_node_pool    = { enabled = true, node_count = 2 }
