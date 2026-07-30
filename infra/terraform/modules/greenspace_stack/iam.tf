# ---------- API Runtime Role (Lambda) ----------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_runtime" {
  name               = "${local.naming_prefix}-api-runtime"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name = "${local.naming_prefix}-api-runtime"
  }
}

resource "aws_iam_role_policy_attachment" "api_basic_execution" {
  role       = aws_iam_role.api_runtime.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "api_vpc_access" {
  role       = aws_iam_role.api_runtime.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "api_secrets" {
  statement {
    sid    = "SharedDbSecretRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${local.shared_db_secret_name}-*",
    ]
  }
}

resource "aws_iam_role_policy" "api_secrets" {
  name   = "secrets-read"
  role   = aws_iam_role.api_runtime.id
  policy = data.aws_iam_policy_document.api_secrets.json
}

data "aws_iam_policy_document" "api_ses" {
  statement {
    sid    = "SESSend"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = [
      # The domain identity is owned by the un17hub repository (see ses.tf), so
      # scope by identity ARN pattern rather than a module-managed resource.
      "arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/*",
    ]
  }
}

resource "aws_iam_role_policy" "api_ses" {
  name   = "ses-send"
  role   = aws_iam_role.api_runtime.id
  policy = data.aws_iam_policy_document.api_ses.json
}

# ---------- CI OIDC (GitHub Actions) ----------

data "aws_iam_policy_document" "ci_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:${coalesce(var.github_environment, var.environment)}",
      ]
    }
  }
}

resource "aws_iam_role" "ci_deploy" {
  name               = "${local.naming_prefix}-ci-deploy"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json

  tags = {
    Name = "${local.naming_prefix}-ci-deploy"
  }
}

data "aws_iam_policy_document" "ci_deploy_permissions" {
  statement {
    sid    = "LambdaDeploy"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunction",
      "lambda:GetFunctionUrlConfig",
      "lambda:ListFunctions",
      "lambda:InvokeFunction",
    ]
    resources = [
      "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "S3Assets"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${local.naming_prefix}-*",
      "arn:aws:s3:::${local.naming_prefix}-*/*",
    ]
  }

  statement {
    sid    = "AmplifyDeploy"
    effect = "Allow"
    actions = [
      "amplify:StartDeployment",
      "amplify:GetApp",
      "amplify:GetBranch",
      "amplify:ListApps",
      "amplify:ListBranches",
      "amplify:StartJob",
      "amplify:StopJob",
      "amplify:GetJob",
      "amplify:ListJobs",
    ]
    resources = [
      aws_amplify_app.web.arn,
      "${aws_amplify_app.web.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_deploy" {
  name   = "deploy-permissions"
  role   = aws_iam_role.ci_deploy.id
  policy = data.aws_iam_policy_document.ci_deploy_permissions.json
}

# ---------- CI Terraform Role (GitHub Actions OIDC - plan/apply) ----------

data "aws_iam_policy_document" "ci_terraform_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:pull_request",
        "repo:${var.github_repo}:environment:${coalesce(var.github_environment, var.environment)}",
      ]
    }
  }
}

resource "aws_iam_role" "ci_terraform" {
  name               = "${local.naming_prefix}-ci-terraform"
  assume_role_policy = data.aws_iam_policy_document.ci_terraform_assume.json

  tags = {
    Name = "${local.naming_prefix}-ci-terraform"
  }
}

data "aws_iam_policy_document" "ci_terraform_state" {
  statement {
    sid    = "TerraformStateS3List"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}",
    ]
  }

  statement {
    sid    = "TerraformStateS3Read"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}/environments/*",
    ]
  }

  statement {
    sid    = "TerraformStateS3Write"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}/environments/${var.environment}/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      "arn:aws:dynamodb:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${var.tf_lock_table}",
    ]
  }
}

resource "aws_iam_role_policy" "ci_terraform_state" {
  name   = "terraform-state"
  role   = aws_iam_role.ci_terraform.id
  policy = data.aws_iam_policy_document.ci_terraform_state.json
}

data "aws_iam_policy_document" "ci_terraform_resources" {
  # The API Lambda runs in the shared default VPC, whose id and private subnet
  # ids the environment roots read from SSM. The only network resource this
  # module owns there is an egress-only security group, so this statement is
  # scoped to that group: its lifecycle, the tags it carries, and the reads that
  # resolve the Lambda's `vpc_config`. Nothing wider belongs here — the shared
  # VPC's subnets, route tables, gateways, and endpoints are owned by
  # `un17-infra-shared`, and tenants must not create endpoint or NAT resources
  # in it.
  #
  # The resource stays `*` for two different reasons: the Describe actions have
  # no resource-level support at all, and the group's id is not known until it
  # has been created.
  #
  # The group is egress-only, so of the rule-authorizing pair only the egress
  # half is granted: it carries no ingress rules to authorize, and a destroy
  # takes the rules it does carry with it. `ec2:ModifySecurityGroupRules` is
  # deliberately absent — it is what an in-place edit of an existing egress
  # rule's description, protocol, or port range needs, and nothing here edits
  # one. Grant it alongside the change that first does, not ahead of it: it
  # addresses a rule by id with no direction in the request, so on `*` it can
  # rewrite an existing *ingress* rule on any group in the account, including
  # ones `un17-infra-shared` owns.
  statement {
    sid    = "SharedVpcSecurityGroup"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeSubnets",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "DenySelfModify"
    effect = "Deny"
    actions = [
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.naming_prefix}-ci-terraform",
    ]
  }

  statement {
    sid    = "IAMReadOIDC"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # This module manages no KMS key, alias, or key policy, so it needs no
  # key-lifecycle grants: `CreateKey`, `PutKeyPolicy`, `EnableKeyRotation`,
  # `DisableKeyRotation`, `ScheduleKeyDeletion`, `CreateAlias`, `DeleteAlias`,
  # `UpdateAlias`, `TagResource`, and `UntagResource` are all gone. The
  # key-shaped reads (`DescribeKey`, `GetKeyPolicy`, `GetKeyRotationStatus`,
  # `ListResourceTags`, `ListAliases`) are not re-homed either — the bootstrap
  # policy below already grants `kms:Describe*` / `kms:Get*` / `kms:List*` on
  # `*` so plan refresh covers any resource type without a code change.
  #
  # `kms:GenerateDataKey` is gone with them. It is an encrypt-side action, and
  # nothing this role writes lands under a *customer-managed* key. Note the
  # distinction, because one of these is not KMS-free: the Terraform state bucket
  # does default to SSE-KMS (`bootstrap/main.tf` sets `sse_algorithm =
  # "aws:kms"`), and the backend blocks request `encrypt = true` with no
  # `kms_key_id`. Either the backend's AES256 request overrides the bucket
  # default, or it falls through to the AWS-managed `aws/s3` key — and that key's
  # policy admits same-account callers through `kms:ViaService` without any
  # IAM-side grant, so both paths need nothing here. The lock table takes
  # DynamoDB's AWS-owned key, the log groups CloudWatch's, and the Lambda's
  # environment variables the AWS-managed `aws/lambda` key. Same reasoning
  # throughout.
  #
  # What that argument does *not* survive is someone pointing the state bucket at
  # a customer-managed key. That change needs `kms:GenerateDataKey` and
  # `kms:Decrypt` granted out of band first (see the two-phase note below), or
  # backend init fails in both environments.
  #
  # `kms:Decrypt` stays, and is the reason this statement still exists. Both
  # environment roots read the shared-VPC tenancy contract from SSM
  # (`/shared/network/*`) on every plan. A `SecureString` there encrypted under a
  # customer-managed key needs this grant; a plain `String`, or a `SecureString`
  # under `alias/aws/ssm`, does not — same `kms:ViaService` reasoning as above.
  # Which one it is, is a fact about the live parameters rather than about this
  # repository, so retiring the grant takes three checks, not two:
  #
  #   aws ssm describe-parameters --parameter-filters Key=Name,Values=/shared/network/
  #     -> `Type`: `String` means this grant is already dead. `SecureString`:
  #   aws ssm get-parameter --name /shared/network/vpc-id --with-decryption
  #     -> `KeyId`: `alias/aws/ssm` means dead too. A CMK means read on:
  #   aws kms get-key-policy --key-id <KeyId> --policy-name default
  #     -> delegates to account root, so this grant is what authorizes the read;
  #        names principals explicitly instead, and the grant is doing nothing.
  #
  # Removing it while it is load-bearing fails `terraform plan` in both
  # environments, and the role cannot then grant it back to itself — recovery is
  # the out-of-band `put-role-policy` described in the two-phase note below.
  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }

  # No `logs:AssociateKmsKey` / `logs:DisassociateKmsKey`: the log groups take
  # CloudWatch's AWS-owned default key and set no `kms_key_id`, so nothing here
  # binds a key to a log group. Granting either is only meaningful alongside a
  # customer-managed key, which is the posture `log_encryption.tftest.hcl`
  # rejects — reintroduce them together or not at all.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:ListTagsLogGroup",
      "logs:ListTagsForResource",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/${local.naming_prefix}/*",
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/${local.naming_prefix}/*:*",
    ]
  }

  statement {
    sid       = "CloudWatchLogsList"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # SES v1 APIs do not support resource-level permissions; wildcard required.
  statement {
    sid    = "SESManage"
    effect = "Allow"
    actions = [
      "ses:VerifyDomainIdentity",
      "ses:VerifyDomainDkim",
      "ses:GetIdentityVerificationAttributes",
      "ses:GetIdentityDkimAttributes",
      "ses:DeleteIdentity",
      "ses:CreateConfigurationSet",
      "ses:DescribeConfigurationSet",
      "ses:DeleteConfigurationSet",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Route53Zones"
    effect = "Allow"
    actions = [
      "route53:CreateHostedZone",
      "route53:DeleteHostedZone",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:ChangeTagsForResource",
      "route53:ListTagsForResource",
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    sid    = "Route53Global"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:GetChange",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "STSIdentity"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:ListFunctions",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:CreateFunctionUrlConfig",
      "lambda:GetFunctionUrlConfig",
      "lambda:UpdateFunctionUrlConfig",
      "lambda:DeleteFunctionUrlConfig",
      "lambda:ListVersionsByFunction",
      "lambda:GetFunctionCodeSigningConfig",
    ]
    resources = [
      "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "SecretsManager"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${local.naming_prefix}-*",
    ]
  }

  statement {
    sid       = "SecretsManagerList"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }

  statement {
    sid    = "SNSManage"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
    ]
    resources = [
      "arn:aws:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "CloudWatchAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListDashboards",
    ]
    resources = [
      "arn:aws:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:${local.naming_prefix}-*",
      "arn:aws:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "RDSRead"
    effect = "Allow"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBSubnetGroups",
      "rds:DescribeDBParameterGroups",
      "rds:DescribeDBParameters",
      "rds:DescribeDBSnapshots",
      "rds:ListTagsForResource",
      "rds:DescribeDBEngineVersions",
      "rds:DescribeOrderableDBInstanceOptions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EventBridgeManage"
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:ListTagsForResource",
      "events:TagResource",
      "events:UntagResource",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:ListTargetsByRule",
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/${local.naming_prefix}-*",
    ]
  }

  statement {
    sid    = "AmplifyManage"
    effect = "Allow"
    actions = [
      "amplify:CreateApp",
      "amplify:DeleteApp",
      "amplify:GetApp",
      "amplify:UpdateApp",
      "amplify:ListApps",
      "amplify:TagResource",
      "amplify:UntagResource",
      "amplify:ListTagsForResource",
      "amplify:CreateBranch",
      "amplify:DeleteBranch",
      "amplify:GetBranch",
      "amplify:UpdateBranch",
      "amplify:ListBranches",
      "amplify:CreateDomainAssociation",
      "amplify:DeleteDomainAssociation",
      "amplify:GetDomainAssociation",
      "amplify:UpdateDomainAssociation",
      "amplify:ListDomainAssociations",
    ]
    resources = [
      "arn:aws:amplify:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:apps/*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_terraform_resources" {
  name   = "terraform-resources"
  role   = aws_iam_role.ci_terraform.id
  policy = data.aws_iam_policy_document.ci_terraform_resources.json
}

# ---------- CI Terraform Bootstrap Policy ----------
#
# Permanent companion to `terraform-resources` whose sole purpose is to break
# the chicken-and-egg problem when a new resource type is added to the stack
# module: `terraform plan` refresh fails on the unauthorized read before any
# apply can grant the missing perms.
#
# Contents are deliberately bounded:
#   - Broad reads (Describe* / Get* / List*) for every AWS service the stack
#     uses. Read on `*` covers refresh on any new resource type without code
#     changes.
#   - A small, curated set of destroy-side ec2 writes that have caused
#     repeated cycles in past applies. EC2 does not support resource-level
#     permissions for most of these, so wildcard resource is unavoidable.
#
# What this policy does NOT solve — read before adding a permission here:
#
# This role is defined by the stack it applies, so it cannot grant itself a
# permission it needs at plan time. Adding a statement here does not make that
# permission available to the plan that introduces it: the policy only exists
# after an apply, and the plan fails first. The `RefreshReads` coverage above
# works only because it is already applied and already lists the service.
#
# So a new permission required at plan time — typically a data source in an
# environment root module reaching for a service not in `RefreshReads` — must
# be applied BEFORE the change that uses it. Two ways:
#
#   1. Merge the permission on its own, let it apply, then merge the consumer.
#   2. Grant it out of band, then merge both together:
#
#        aws iam put-role-policy \
#          --role-name <naming_prefix>-ci-terraform \
#          --policy-name <distinct-temporary-name> \
#          --policy-document '{...}'
#
#      Use a distinct policy name — `put-role-policy` overwrites by name, so
#      reusing `terraform-resources-bootstrap` would silently drop every
#      statement below. Delete the temporary policy once the apply has
#      reconciled the permanent grant.
#
# Drift guards:
#   - `iam.tftest.hcl` asserts statement and action counts stay below caps
#     and that every action matches an allowlisted prefix.
#   - The daily `Drift Detection` workflow re-validates the live policy
#     against the same shape, catching code-side bloat and AWS-side
#     tampering alike.

data "aws_iam_policy_document" "ci_terraform_bootstrap" {
  statement {
    sid    = "RefreshReads"
    effect = "Allow"
    actions = [
      "amplify:Get*",
      "amplify:List*",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "dynamodb:Describe*",
      "dynamodb:List*",
      "ec2:Describe*",
      "ec2:Get*",
      "events:Describe*",
      "events:List*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "lambda:Get*",
      "lambda:List*",
      "logs:Describe*",
      "logs:List*",
      "rds:Describe*",
      "rds:List*",
      "route53:Get*",
      "route53:List*",
      "s3:GetBucket*",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket*",
      "s3:ListAllMyBuckets",
      "secretsmanager:Describe*",
      "secretsmanager:List*",
      "secretsmanager:GetResourcePolicy",
      "ses:Describe*",
      "ses:Get*",
      "ses:List*",
      "sns:Get*",
      "sns:List*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # EC2 destroy-side writes that have repeatedly broken applies when omitted
  # from the main policy. Scoped to `*` because EC2 does not support
  # resource-level permissions for these actions.
  statement {
    sid    = "Ec2DestroyHelpers"
    effect = "Allow"
    actions = [
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # Read the shared-VPC tenancy contract published by un17-infra-shared. The
  # environment stacks read these SSM parameters at plan time to place the API
  # Lambda in the shared VPC.
  #
  # Scoped to the shared/network parameter path rather than folded into
  # `RefreshReads` above: that statement grants on `Resource = "*"`, and
  # combined with the `kms:Decrypt` grant in `terraform-resources` a wildcard
  # SSM read would expose every SecureString parameter in the account.
  statement {
    sid    = "SharedNetworkSsmRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:*:*:parameter/shared/network/*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_terraform_bootstrap" {
  name   = "terraform-resources-bootstrap"
  role   = aws_iam_role.ci_terraform.id
  policy = data.aws_iam_policy_document.ci_terraform_bootstrap.json
}
