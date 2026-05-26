# terraform/main.tf

locals {
  # 1. Load the raw text from your capitalized users.yaml file located in the root directory
  raw_yaml = file("${path.module}/../users.yaml")
  
  # 2. Parse the text data structure into standard Terraform object variables
  parsed_data = yamldecode(local.raw_yaml)

  # 3. Filter data blocks: extract only employees whose employment status is actively set to true
  active_users = {
    for user in local.parsed_data.users : user.Username => user
    if user.is_currently_employed == true
  }
}

# RESOURCE 1: Create the core AWS IAM User Profile accounts
resource "aws_iam_user" "gitops_users" {
  for_each = local.active_users
  
  name = each.value.Username
  path = "/managed-gitops/"

  # Automatically tag each account with metadata parsed from your file elements
  tags = {
    Email       = each.value.Email
    FullName    = each.value["Full name"]
    DateJoined  = each.value.Date_Joined
  }
}

# RESOURCE 2: Provision a management login profile workspace for AWS console access
resource "aws_iam_user_login_profile" "user_login" {
  for_each = local.active_users
  
  user            = aws_iam_user.gitops_users[each.key].name
  password_length = 20

  # Forces administrative resets to stay un-overwritten during future automated runs
  lifecycle {
    ignore_changes = [password_length, password_reset_required]
  }
}

# RESOURCE 3: Flatten and dynamically attach managed policies based on your 'aws_roles' array
resource "aws_iam_user_policy_attachment" "role_attachments" {
  for_each = {
    for pair in flatten([
      for username, user in local.active_users : [
        for role in user.aws_roles : {
          username   = username
          policy_arn = "arn:aws:iam::aws:policy/${role}"
        }
      ]
    ]) : "${pair.username}-${pair.policy_arn}" => pair
  }

  user       = aws_iam_user.gitops_users[each.value.username].name
  policy_arn = each.value.policy_arn
}
