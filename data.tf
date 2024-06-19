data "aws_caller_identity" "current" {}

# Lookup the current AWS partition
data "aws_partition" "current" {
}

data "aws_region" "current" {}
