# terraform/main.tf

locals {
  # 1. Load the raw text from your capitalized users.yaml file located in the root directory
  raw_yaml = file("${path.module}/../users.yaml")

  # 2. Parse the text data structure into standard Terraform object variables
  parsed_data = yamldecode(local.raw_yaml)

  # 3. Guard: fail fast at plan time if any usernames are duplicated in users.yaml
  _username_check = {
    for user in local.parsed_data.Users : user.Username => user.Username
  }

  # 4. Filter data blocks: extract only employees whose employment status is actively set to true
  active_users = {
    for user in local.parsed_data.Users : user.Username => user
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
    Email      = each.value.Email
    FullName   = try(each.value["Full name"], "")
    DateJoined = try(each.value.Date_Joined, "")
  }
}

# RESOURCE 2: Provision a management login profile workspace for AWS console access
# Note: password_reset_required = true forces the user to set their own password on first login.
# 'password' (not 'password_length') is the computed attribute that causes state drift, so it
# is listed in ignore_changes to prevent perpetual diffs on every subsequent terraform plan.
resource "aws_iam_user_login_profile" "user_login" {
  for_each = local.active_users

  user                    = aws_iam_user.gitops_users[each.key].name
  password_length         = 20
  password_reset_required = true

  lifecycle {
    ignore_changes = [password, password_reset_required]
  }
}

# RESOURCE 3: Flatten and dynamically attach managed policies based on your 'aws_roles' array.
# IMPORTANT: aws_roles entries in users.yaml must be full ARNs, e.g.:
#   - arn:aws:iam::aws:policy/ReadOnlyAccess          (AWS-managed)
#   - arn:aws:iam::123456789012:policy/MyCustomPolicy  (customer-managed)
# This avoids the previous bug where constructing the ARN as
# "arn:aws:iam::aws:policy/${role}" would silently produce wrong ARNs
# for any customer-managed policies.
resource "aws_iam_user_policy_attachment" "role_attachments" {
  for_each = {
    for pair in flatten([
      for username, user in local.active_users : [
        for role in user.aws_roles : {
          username   = username
          policy_arn = role
        }
      ]
    ]) : "${pair.username}-${pair.policy_arn}" => pair
  }

  user       = aws_iam_user.gitops_users[each.value.username].name
  policy_arn = each.value.policy_arn
}
