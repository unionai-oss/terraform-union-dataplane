# Apply after examples/gcp/infra/gpu.tfvars; everything about the cloud comes from that root's state. The client
# secret is not here: it goes in the union-secret-auth Secret (gcp/README.md, Apply).
union_client_id          = "example-client-id"
union_control_plane_host = "union.example.com"
union_org_name           = "example-org"
