region = "ap-southeast-1"

project = "NTT"

state_bucket_name = "ntt-terraform-state-ap-southeast-1"

lock_table_name = "ntt-terraform-state-lock"

#cicd_role_name = "github-cicd-role"

#github_org  = "github-org"

#github_repo = "ntt-assignment"

tags = {
  Project            = "GCC"
  Environment        = "Production"
  DataClassification = "Internal"
  Owner              = "NTT"
  CostCenter         = "NTT"
  Terraform          = "True"
}
