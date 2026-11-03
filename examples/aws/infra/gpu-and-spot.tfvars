# Dedicated spot worker pool created with two nodes, plus a GPU pool created with one (the default). Without a
# cluster autoscaler or Karpenter they stay at that size; with one, they scale between min_size and max_size. The GPU
# pool gets the NVIDIA device plugin from the helm root. The public endpoint is limited to a documentation
# address; use your own CIDR.
name   = "acme-union"
region = "us-east-2"

cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["192.0.2.10/32"]

worker_node_pool = {
  enabled       = true
  capacity_type = "SPOT"
  desired_size  = 2
}

gpu_node_pool = {
  enabled        = true
  instance_types = ["g5.2xlarge"]
}

tags = {
  team = "data-platform"
}
