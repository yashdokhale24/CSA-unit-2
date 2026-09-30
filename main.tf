terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# S3 bucket that the EC2 role is allowed to access (created for demo purposes)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# IAM Groups
# ---------------------------------------------------------------------------
resource "aws_iam_group" "admins" {
  name = "Admins"
}

resource "aws_iam_group" "developers" {
  name = "Developers"
}

resource "aws_iam_group" "auditors" {
  name = "Auditors"
}

# ---------------------------------------------------------------------------
# Admins: broad account administration, but NOT full "*:*" root-equivalent.
# Explicitly excludes billing/org changes and account closure to demonstrate
# least privilege even at the admin tier.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "admins_policy" {
  statement {
    sid    = "AllowServiceAdministration"
    effect = "Allow"
    actions = [
      "ec2:*",
      "s3:*",
      "iam:Get*",
      "iam:List*",
      "iam:CreateUser",
      "iam:CreateGroup",
      "iam:CreateRole",
      "iam:AttachUserPolicy",
      "iam:AttachGroupPolicy",
      "iam:AttachRolePolicy",
      "iam:PutUserPolicy",
      "iam:PutGroupPolicy",
      "iam:PutRolePolicy",
      "cloudwatch:*",
      "logs:*"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyBillingAndOrgChanges"
    effect    = "Deny"
    actions   = ["aws-portal:*", "organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "admins_policy" {
  name        = "AdminsLeastPrivilegePolicy"
  description = "Admin permissions scoped away from billing/org root actions"
  policy      = data.aws_iam_policy_document.admins_policy.json
}

resource "aws_iam_group_policy_attachment" "admins_attach" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.admins_policy.arn
}

# ---------------------------------------------------------------------------
# Admins: enforce MFA. Denies almost everything unless the caller has
# authenticated with MFA, while still allowing users to manage their own
# credentials/MFA device so they aren't permanently locked out.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "require_mfa" {
  statement {
    sid       = "AllowViewAccountInfo"
    effect    = "Allow"
    actions   = ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageOwnMFA"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:ListMFADevices",
      "iam:GetUser",
      "iam:ChangePassword"
    ]
    resources = [
      "arn:aws:iam::*:mfa/$${aws:username}",
      "arn:aws:iam::*:user/$${aws:username}"
    ]
  }

  statement {
    sid       = "DenyAllExceptListedUnlessMFAed"
    effect    = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken"
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "require_mfa" {
  name        = "RequireMFAForAdmins"
  description = "Denies all actions for Admins group members unless authenticated with MFA"
  policy      = data.aws_iam_policy_document.require_mfa.json
}

resource "aws_iam_group_policy_attachment" "admins_mfa_attach" {
  group      = aws_iam_group.admins.name
  policy_arn = aws_iam_policy.require_mfa.arn
}

# ---------------------------------------------------------------------------
# Developers: scoped to EC2 + S3 for their own dev workloads, no IAM access.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "developers_policy" {
  statement {
    sid    = "EC2DevAccess"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ec2:CreateTags"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "S3DevBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.app_bucket.arn,
      "${aws_s3_bucket.app_bucket.arn}/*"
    ]
  }

  statement {
    sid       = "DenyIAMAccess"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "developers_policy" {
  name        = "DevelopersLeastPrivilegePolicy"
  description = "EC2 + scoped S3 access for developers, explicit deny on IAM"
  policy      = data.aws_iam_policy_document.developers_policy.json
}

resource "aws_iam_group_policy_attachment" "developers_attach" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developers_policy.arn
}

# ---------------------------------------------------------------------------
# Auditors: read-only across the board, with explicit CloudTrail/Config
# read access for compliance review. No write actions anywhere.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "auditors_policy" {
  statement {
    sid    = "ReadOnlyAudit"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
      "iam:GenerateCredentialReport",
      "iam:GenerateServiceLastAccessedDetails",
      "s3:Get*",
      "s3:List*",
      "ec2:Describe*",
      "cloudtrail:LookupEvents",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:DescribeTrails",
      "config:Describe*",
      "config:Get*",
      "config:List*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "auditors_policy" {
  name        = "AuditorsReadOnlyPolicy"
  description = "Strict read-only access for compliance auditing"
  policy      = data.aws_iam_policy_document.auditors_policy.json
}

resource "aws_iam_group_policy_attachment" "auditors_attach" {
  group      = aws_iam_group.auditors.name
  policy_arn = aws_iam_policy.auditors_policy.arn
}

# ---------------------------------------------------------------------------
# Custom IAM Role: lets an EC2 instance reach S3 securely with no hardcoded
# credentials, via an instance profile.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_s3_role" {
  name               = "EC2-S3-Access-Role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_s3_access" {
  statement {
    sid    = "AllowScopedS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.app_bucket.arn,
      "${aws_s3_bucket.app_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "ec2_s3_access" {
  name        = "EC2-S3-Scoped-Access"
  description = "Allows EC2 instances assuming this role to read/write only the app bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_access.json
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_access.arn
}

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "EC2-S3-Access-Profile"
  role = aws_iam_role.ec2_s3_role.name
}
