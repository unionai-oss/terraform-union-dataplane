# Goes with ../infra/minimal.tfvars: the cluster, buckets and role come from that root's state. Use your own org, control
# plane host and client ID (uctl selfserve provision-dataplane-resources prints the ID; its secret goes in the
# union-secret-auth Secret, README: Apply).
union_org_name           = "example"
union_control_plane_host = "example.union.ai"
union_client_id          = "example-client-id"
