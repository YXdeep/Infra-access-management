# terraform/main.tf

locals {
  # 1. Load the raw YAML text from the root directory
  raw_yaml = file("${path.module}/../users.yaml")

  # 2. Parse into Terraform objects
  parsed_data = yamldecode(local.raw_yaml)

  # 3. Duplicate username guard — Terraform will throw an error at plan time
  #    if any two users share the same Username key
  _username_check = {
    for user in local.parsed_data.Users : user.Username => user.Username
  }

  # 4. Filter: active employees only
  active_users = {
    for user in local.parsed_data.Users : user.Username => user
    if user.is_currently_employed == true
  }
}

# RESOURCE 1: Core AWS IAM User accounts
resource "aws_iam_user" "gitops_users" {
  for_each = local.active_users

  name = each.value.Username
  path = "/managed-gitops/"

  tags = {
    Email      = each.value.Email
    FullName   = try(each.value["Full name"], "")
    DateJoined = try(each.value.Date_Joined, "")
  }
}

# RESOURCE 2: AWS Console login profile
# password_reset_required = true forces users to set their own password on first login.
# 'password' is the computed attribute that causes perpetual state drift (not 'password_length'),
# so it is listed in ignore_changes to prevent spurious diffs on every plan.
resource "aws_iam_user_login_profile" "user_login" {
  for_each = local.active_users

  user                    = aws_iam_user.gitops_users[each.key].name
  password_length         = 20
  password_reset_required = true

  lifecycle {
    ignore_changes = [password, password_reset_required]
  }
}

# RESOURCE 3: Policy attachments
# aws_roles entries in users.yaml must be full ARNs, e.g.:
#   AWS-managed:      arn:aws:iam::aws:policy/ReadOnlyAccess
#   Customer-managed: arn:aws:iam::123456789012:policy/MyPolicy
# The ARN is passed through directly — never constructed — to avoid
# silently producing wrong ARNs for customer-managed policies.
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
