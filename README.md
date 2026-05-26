# Infra-access-management

Centralized GitOps repository for infrastructure access control. Manages Linux server user accounts and AWS IAM permissions via structured code configurations and automated CI/CD pipelines.

# Infrastructure Access Management (IAM)

This repository serves as the single source of truth for user access across our Linux infrastructure and AWS environments. 

## How to Request Access:
1. Create a new branch.
2. Edit the `users.yaml` file to add your details (username, SSH key, and roles).
3. Open a Pull Request (PR).
4. Once an administrator reviews and merges your PR, automation will automatically provision your accounts.


