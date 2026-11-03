region    = "eu-north1"
name      = "union-gpu"
parent_id = "project-e00example"
tenant_id = "tenant-e00example"
subnet_id = "vpc-subnet-e00example"

labels = { team = "example" }

public_endpoint_allowed_cidrs = ["203.0.113.0/24"]

worker_node_pool = { enabled = true }
gpu_node_pool    = { enabled = true }
