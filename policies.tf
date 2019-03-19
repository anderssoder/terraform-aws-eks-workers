data "aws_iam_policy_document" "assume_role" {
  count = "${var.enabled == "true" ? 1 : 0}"

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals = {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  count      = "${var.enabled == "true" ? 1 : 0}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  count      = "${var.enabled == "true" ? 1 : 0}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  count      = "${var.enabled == "true" ? 1 : 0}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_iam_policy" "worker_node_main_policy" {
  count = "${var.enabled == "true" ? 1 : 0}"
  name  = "${module.label.id}${var.delimiter}worker${var.delimiter}policy"

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement": [
        {
          "Action": "ec2:Describe*",
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "ec2:AttachVolume",
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "ec2:DetachVolume",
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "sts:AssumeRole",
          "Effect":"Allow",
          "Resource":"*"
        },
        {
          "Action": "cloudformation:SignalResource",
          "Effect": "Allow",
          "Resource": "${module.autoscale_group.cloudformation_stack_id}/*"
        },
        {
          "Action": "autoscaling:Describe*",
          "Effect": "Allow",
          "Resource": [ "*" ]
        },
        {
          "Action": [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeTags"
          ],
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": [
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup"
          ],
          "Condition": {
            "Null": { "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "false" }
          },
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "ec2:CreateTags",
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": "elasticloadbalancing:*",
          "Effect": "Allow",
          "Resource": "*"
        },
        {
          "Action": [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetRepositoryPolicy",
            "ecr:DescribeRepositories",
            "ecr:ListImages",
            "ecr:BatchGetImage"
          ],
          "Resource": "*",
          "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "worker_node_main_policy" {
  count      = "${var.enabled == "true" ? 1 : 0}"
  policy_arn = "${join("", aws_iam_policy.worker_node_main_policy.*.arn)}"
  role       = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_iam_policy" "node_drain_policy" {
  count = "${var.enabled == "true" && var.node_drain_enabled == "true" ? 1 : 0}"
  name  = "${module.label.id}${var.delimiter}node${var.delimiter}drain${var.delimiter}policy"

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLifecycleHooks"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "autoscaling:CompleteLifecycleAction"
      ],
      "Effect": "Allow",
      "Condition": {
        "Null": { "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "false" }
      },
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "node_drain_policy" {
  count      = "${var.enabled == "true" && var.node_drain_enabled == "true" ? 1 : 0}"
  policy_arn = "${join("", aws_iam_policy.node_drain_policy.*.arn)}"
  role       = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_iam_policy" "node_encryption_policy" {
  count = "${var.enabled == "true" && var.node_encryption_enabled == "true" ? 1 : 0}"
  name  = "${module.label.id}${var.delimiter}node${var.delimiter}encryption${var.delimiter}policy"

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement": [
    {
      "Action" : "kms:Decrypt",
      "Effect" : "Allow",
      "Resource" : "${var.kms_key_arn}"
    },
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "node_encryption_policy" {
  count      = "${var.enabled == "true" && var.node_encryption_enabled == "true" ? 1 : 0}"
  policy_arn = "${join("", aws_iam_policy.node_encryption_policy.*.arn)}"
  role       = "${join("", aws_iam_role.default.*.name)}"
}
