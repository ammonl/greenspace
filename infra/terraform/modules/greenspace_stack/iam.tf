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

  # There is no KMS statement here, and that is the whole surface: the role's only
  # `kms:` grants are the bootstrap policy's `Describe*` / `Get*` / `List*` reads,
  # which exist for plan refresh.
  #
  # This module manages no KMS key, alias, or key policy, so the key-lifecycle
  # grants went with the key. `kms:GenerateDataKey` went too — it is encrypt-side,
  # and nothing this role writes lands under a *customer-managed* key. Note the
  # distinction, because one of these is not KMS-free: the Terraform state bucket
  # does default to SSE-KMS (`bootstrap/main.tf` sets `sse_algorithm = "aws:kms"`),
  # and the backend blocks request `encrypt = true` with no `kms_key_id`. Either
  # the backend's AES256 request overrides the bucket default, or it falls through
  # to the AWS-managed `aws/s3` key — whose policy admits same-account callers
  # through `kms:ViaService` with no IAM-side grant. Both paths need nothing here.
  # The lock table takes DynamoDB's AWS-owned key, the log groups CloudWatch's, and
  # the Lambda's environment variables the AWS-managed `aws/lambda` key.
  #
  # `kms:Decrypt` was the last one out, and only after checking what actually
  # reads through it. Both environment roots read the shared-VPC tenancy contract
  # from SSM (`/shared/network/*`) on every plan, which would have needed the grant
  # had either parameter been a `SecureString` under a customer-managed key. They
  # are not — `vpc-id` is a `String` and `private-subnet-ids` a `StringList`, both
  # with no `KeyId`, so nothing on that path decrypts at all.
  #
  # Three changes would each make a removed grant load-bearing again, and every
  # one of them needs it restored out of band *first* (see the two-phase note
  # below), because the plan that would restore it is the plan that fails:
  #
  #   - A customer-managed key on the DynamoDB lock table. This is the worst of
  #     the three. `dynamodb:GetItem`/`PutItem` is the state lock, so it runs on
  #     every plan and every apply in both environments, and it would fail before
  #     anything else got a chance to. (`server_side_encryption { enabled = true }`
  #     with no key ARN is the AWS-managed `aws/dynamodb` key and is fine — only a
  #     CMK breaks it.)
  #   - A customer-managed key on the Terraform state bucket, which fails at
  #     backend init.
  #   - Publishing the shared-network parameters as `SecureString` under a CMK,
  #     which fails when the environment roots read them.
  #
  # A CMK on the Lambda is a lesser case worth knowing but not guarding: it does
  # not lock CI out. `GetFunctionConfiguration` returns `Environment.Error`
  # instead of failing, so the symptom is a permanent phantom `environment` diff
  # on every plan rather than an error.

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

  # No Secrets Manager statement either. This module manages no secret — #397
  # deleted `database.tf`, taking `aws_secretsmanager_secret.db_credentials` and
  # `.app` with it — so the create/write/delete grants it used to hold on
  # `${local.naming_prefix}-*` had nothing to act on. The one secret the stack
  # still reads is the shared-db secret, which belongs to `un17-infra-shared`,
  # is read at runtime rather than at plan time, and is granted on the API
  # runtime role above, not here — note it is named `rds/shared/greenspace_<env>`,
  # so the removed statement's `${local.naming_prefix}-*` scope could never have
  # covered it anyway.
  #
  # Refresh coverage for an `aws_secretsmanager_secret` added later comes from the
  # bootstrap policy's `secretsmanager:Describe*` / `List*`. An
  # `aws_secretsmanager_secret_version` is the exception: it refreshes through
  # `GetSecretValue`, which nothing grants this role, so that one needs its
  # permission landed first like any other new resource type.

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
  # `RefreshReads` above, which grants on `Resource = "*"`: a wildcard SSM read
  # would expose every parameter in the account, `SecureString` ones included.
  #
  # That hazard does *not* depend on holding `kms:Decrypt`, which the role no
  # longer does. `alias/aws/ssm` — what a `SecureString` gets unless it is given a
  # customer-managed key — grants decrypt to any same-account caller through
  # `kms:ViaService` in its own key policy, with no IAM-side grant required. So
  # `ssm:GetParameter` with `WithDecryption` on `*` is sufficient by itself, and
  # this scoping is the only thing preventing it.
  #
  # Removing `kms:Decrypt` did narrow the hypothetical blast radius, just not to
  # zero: a `SecureString` under a *customer-managed* key whose policy delegates
  # to the account root was readable with the grant and is not without it. That
  # subset is the exception. Everything under the default key still reads.
  #
  # This statement is also a floor, not just a ceiling. Both environment roots
  # read these two parameters through `data.aws_ssm_parameter` on every plan, so
  # deleting it fails `terraform plan` in both environments — and the role cannot
  # restore it, because the plan that would is the one that fails.
  # `iam.tftest.hcl` asserts its presence for that reason.
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

# ---------- CI Terraform role: inline policies + granted-action surface ----------
#
# The map below is both the attachment source (the `for_each` on
# `aws_iam_role_policy.ci_terraform`) and the guard source
# (`ci_terraform_granted_actions`), so adding a policy to the role means adding
# a map entry, and a map entry is attached and guarded by the same expression.
# There is no second copy of the policy list to fall out of sync.
#
# `ci_terraform_granted_actions` is every action the CI Terraform role is
# allowed, unioned across all of its inline policies. IAM evaluates them
# together, so this — not any one document — is the role's real permission
# surface, and it is what the grant guards in `iam.tftest.hcl` and
# `log_encryption.tftest.hcl` assert against.
#
# It lives here rather than in each test because `.tftest.hcl` files take no
# `locals` block, and hand-copying this expression into every assertion is how a
# guard ends up checking something narrower than its error message claims: the
# first version of the KMS guards read only `ci_terraform_resources` while
# reporting on "the CI Terraform role", so the very grants they existed to reject
# passed when added to `terraform-state`. One definition, one surface.
#
# The guards read this map and nothing else, so a grant that reaches the role
# without going through it stays invisible to them: a policy resource pointing
# at `aws_iam_role.ci_terraform` from outside the `for_each`, whether a
# standalone `aws_iam_role_policy` or an `aws_iam_role_policy_attachment`
# (managed policy; the role carries none). The signal to review for is the role
# reference, not the resource type — this file legitimately carries standalone
# policies for the other roles. The module README's *Least-privilege IAM*
# section is the full discussion of this boundary.
#
# Two details are load-bearing. `flatten([s.Action])` because
# `aws_iam_policy_document` renders a single-element `Action` as a bare string
# rather than a list. And `s.Effect == "Allow"`, because a guard on what the role
# may be *granted* must not trip over an explicit deny (`DenySelfModify`).
locals {
  ci_terraform_policies = {
    "terraform-state"               = data.aws_iam_policy_document.ci_terraform_state.json
    "terraform-resources"           = data.aws_iam_policy_document.ci_terraform_resources.json
    "terraform-resources-bootstrap" = data.aws_iam_policy_document.ci_terraform_bootstrap.json
  }

  ci_terraform_granted_actions = toset(flatten([
    for doc in values(local.ci_terraform_policies) :
    [for s in jsondecode(doc).Statement : flatten([s.Action]) if s.Effect == "Allow"]
  ]))
}

# `name = each.key` keeps the live policy names exactly as the three standalone
# resources set them, so this is a state-address change only — the `moved`
# blocks below carry the existing entries across, and nothing changes on AWS.
resource "aws_iam_role_policy" "ci_terraform" {
  for_each = local.ci_terraform_policies
  name     = each.key
  role     = aws_iam_role.ci_terraform.id
  policy   = each.value
}

# Both environment roots consume this module by local path, so each picks these
# moves up on its next apply; once both have applied them the blocks are inert
# and can be deleted.
moved {
  from = aws_iam_role_policy.ci_terraform_state
  to   = aws_iam_role_policy.ci_terraform["terraform-state"]
}

moved {
  from = aws_iam_role_policy.ci_terraform_resources
  to   = aws_iam_role_policy.ci_terraform["terraform-resources"]
}

moved {
  from = aws_iam_role_policy.ci_terraform_bootstrap
  to   = aws_iam_role_policy.ci_terraform["terraform-resources-bootstrap"]
}
