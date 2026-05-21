check "minimum_public_subnets" {
  assert {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Provide at least two public subnet CIDRs for EKS high availability."
  }
}

check "subnet_pairing" {
  assert {
    condition     = length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs)
    error_message = "public_subnet_cidrs and private_subnet_cidrs must have the same number of CIDRs."
  }
}

check "cluster_endpoint_access" {
  assert {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one non-public CIDR for EKS API public access. Do not leave the endpoint open to 0.0.0.0/0."
  }
}

check "github_runner_secret" {
  assert {
    condition     = !var.enable_github_runner || var.github_runner_app_secret_arn != ""
    error_message = "Set github_runner_app_secret_arn when enable_github_runner is true."
  }
}
