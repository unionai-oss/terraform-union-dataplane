# Smallest useful input: everything else has a default. Pass your own name, which becomes part of bucket names.
name   = "acme-union"
region = "us-east-2"
# The cluster endpoint stays private, so run the helm apply from a host with a route into the VPC (README:
# Prerequisites).
