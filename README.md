# CSA-unit-2
IAM & Least Privilege Enforcement (Unit 2)
Terraform project that builds a least-privilege IAM structure:

IAM Groups: Admins, Developers, Auditors, each with a distinct custom policy scoped to what that role actually needs.
MFA enforcement: An additional policy attached to the Admins group denies almost every action unless the caller has authenticated with MFA (aws:MultiFactorAuthPresent), while still letting users enroll/manage their own MFA device so they don't get locked out.
EC2 → S3 access without hardcoded credentials: A custom IAM Role (EC2-S3-Access-Role) + instance profile that an EC2 instance can assume to read/write a specific S3 bucket, with no access keys stored anywhere.
