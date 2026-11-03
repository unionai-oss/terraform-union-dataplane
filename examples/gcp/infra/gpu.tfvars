project_id = "example-project"
region     = "us-east4"
name       = "union-gpu"

labels = { team = "example" }

worker_node_pool = { enabled = true, spot = true }
gpu_node_pool    = { enabled = true }

master_authorized_networks = [{ cidr_block = "203.0.113.0/24", display_name = "office" }]
