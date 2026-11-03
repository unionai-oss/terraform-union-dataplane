region    = "eu-north1"
parent_id = "project-e00example"
tenant_id = "tenant-e00example"
subnet_id = "vpc-subnet-e00example"

# The API endpoint is public; limit it to the addresses you run kubectl from.
public_endpoint_allowed_cidrs = ["203.0.113.0/24"]
