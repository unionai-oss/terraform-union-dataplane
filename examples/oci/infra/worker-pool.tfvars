region           = "us-ashburn-1"
tenancy_ocid     = "ocid1.tenancy.oc1..example"
compartment_ocid = "ocid1.compartment.oc1..example"
name             = "union-prod"
api_allowed_cidr = "203.0.113.0/24"

labels = { team = "platform" }

worker_node_pool = {
  enabled     = true
  size        = 3
  preemptible = true
}
