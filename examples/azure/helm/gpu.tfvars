# Follows infra/gpu.tfvars. Placeholders: copy the organization and control plane host from the data plane's Azure
# deploy page in the Union UI, and the client ID from `uctl selfserve provision-dataplane-resources` (its secret goes
# in the union-secret-auth Secret, README: Apply).
union_org_name           = "example-org"
union_control_plane_host = "example-org.example.com"
union_client_id          = "example-org-operator"
