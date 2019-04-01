locals {
  moduletags = "${merge(map("kubernetes.io/cluster/${var.cluster_name}", "owned"), map("EKS","true"))}"
  tags       = "${merge(var.tags, local.moduletags)}"
}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.2.1"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = ["${compact(concat(var.attributes, list("workers")))}"]
  tags       = "${local.tags}"
  enabled    = "${var.enabled}"
}

resource "aws_iam_role" "default" {
  count              = "${var.enabled == "true" ? 1 : 0}"
  name               = "${module.label.id}"
  assume_role_policy = "${join("", data.aws_iam_policy_document.assume_role.*.json)}"
}

resource "aws_iam_instance_profile" "default" {
  count = "${var.enabled == "true" ? 1 : 0}"
  name  = "${module.label.id}"
  role  = "${join("", aws_iam_role.default.*.name)}"
}

resource "aws_security_group" "default" {
  count       = "${var.enabled == "true" ? 1 : 0}"
  name        = "${module.label.id}"
  description = "Security Group for EKS worker nodes"
  vpc_id      = "${var.vpc_id}"
  tags        = "${module.label.tags}"
}

resource "aws_security_group_rule" "egress" {
  count             = "${var.enabled == "true" ? 1 : 0}"
  description       = "Allow all egress traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${join("", aws_security_group.default.*.id)}"
  type              = "egress"
}

resource "aws_security_group_rule" "ingress_self" {
  count                    = "${var.enabled == "true" ? 1 : 0}"
  description              = "Allow nodes to communicate with each other"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = "${join("", aws_security_group.default.*.id)}"
  source_security_group_id = "${join("", aws_security_group.default.*.id)}"
  type                     = "ingress"
}

resource "aws_security_group_rule" "ingress_cluster" {
  count                    = "${var.enabled == "true" ? 1 : 0}"
  description              = "Allow worker kubelets and pods to receive communication from the cluster control plane"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = "${join("", aws_security_group.default.*.id)}"
  source_security_group_id = "${var.cluster_security_group_id}"
  type                     = "ingress"
}

resource "aws_security_group_rule" "ingress_security_groups" {
  count                    = "${var.enabled == "true" ? length(var.allowed_security_groups) : 0}"
  description              = "Allow inbound traffic from existing Security Groups"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = "${element(var.allowed_security_groups, count.index)}"
  security_group_id        = "${join("", aws_security_group.default.*.id)}"
  type                     = "ingress"
}

resource "aws_security_group_rule" "ingress_cidr_blocks" {
  count             = "${var.enabled == "true" && length(var.allowed_cidr_blocks) > 0 ? 1 : 0}"
  description       = "Allow inbound traffic from CIDR blocks"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${var.allowed_cidr_blocks}"]
  security_group_id = "${join("", aws_security_group.default.*.id)}"
  type              = "ingress"
}

data "aws_ami" "eks_worker" {
  count = "${var.enabled == "true" && var.image_id == "" ? 1 : 0}"

  filter {
    name   = "name"
    values = ["${var.eks_worker_ami_name_filter}"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon
}

module "autoscale_group" {
  source = "git::https://github.com/anderssoder/terraform-aws-ec2-autoscale-group.git?ref=cf-rolling-upgrade"

  enabled    = "${var.enabled}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"

  image_id                  = "${coalesce(var.image_id, join("", data.aws_ami.eks_worker.*.id))}"
  iam_instance_profile_name = "${join("", aws_iam_instance_profile.default.*.name)}"
  security_group_ids        = ["${join("", aws_security_group.default.*.id)}"]
  user_data_base64          = "${base64encode(join("", data.template_file.userdata.*.rendered))}"
  tags                      = "${module.label.tags}"

  instance_type                                             = "${var.instance_type}"
  subnet_ids                                                = ["${var.subnet_ids}"]
  min_size                                                  = "${var.min_size}"
  max_size                                                  = "${var.max_size}"
  associate_public_ip_address                               = "${var.associate_public_ip_address}"
  block_device_mappings                                     = ["${var.block_device_mappings}"]
  credit_specification                                      = ["${var.credit_specification}"]
  disable_api_termination                                   = "${var.disable_api_termination}"
  ebs_optimized                                             = "${var.ebs_optimized}"
  elastic_gpu_specifications                                = ["${var.elastic_gpu_specifications}"]
  instance_initiated_shutdown_behavior                      = "${var.instance_initiated_shutdown_behavior}"
  instance_market_options                                   = ["${var.instance_market_options }"]
  key_name                                                  = "${var.key_name}"
  placement                                                 = ["${var.placement}"]
  enable_monitoring                                         = "${var.enable_monitoring}"
  load_balancers                                            = ["${var.load_balancers}"]
  health_check_grace_period                                 = "${var.health_check_grace_period}"
  health_check_type                                         = "${var.health_check_type}"
  min_elb_capacity                                          = "${var.min_elb_capacity}"
  wait_for_elb_capacity                                     = "${var.wait_for_elb_capacity}"
  target_group_arns                                         = ["${var.target_group_arns}"]
  default_cooldown                                          = "${var.default_cooldown}"
  force_delete                                              = "${var.force_delete}"
  termination_policies                                      = "${var.termination_policies}"
  placement_group                                           = "${var.placement_group}"
  enabled_metrics                                           = ["${var.enabled_metrics}"]
  metrics_granularity                                       = "${var.metrics_granularity}"
  wait_for_capacity_timeout                                 = "${var.wait_for_capacity_timeout}"
  protect_from_scale_in                                     = "${var.protect_from_scale_in}"
  service_linked_role_arn                                   = "${var.service_linked_role_arn}"
  autoscaling_policies_enabled                              = "${var.autoscaling_policies_enabled}"
  scale_up_cooldown_seconds                                 = "${var.scale_up_cooldown_seconds}"
  scale_up_scaling_adjustment                               = "${var.scale_up_scaling_adjustment}"
  scale_up_adjustment_type                                  = "${var.scale_up_adjustment_type}"
  scale_up_policy_type                                      = "${var.scale_up_policy_type}"
  scale_down_cooldown_seconds                               = "${var.scale_down_cooldown_seconds}"
  scale_down_scaling_adjustment                             = "${var.scale_down_scaling_adjustment}"
  scale_down_adjustment_type                                = "${var.scale_down_adjustment_type}"
  scale_down_policy_type                                    = "${var.scale_down_policy_type}"
  cpu_utilization_high_evaluation_periods                   = "${var.cpu_utilization_high_evaluation_periods}"
  cpu_utilization_high_period_seconds                       = "${var.cpu_utilization_high_period_seconds}"
  cpu_utilization_high_threshold_percent                    = "${var.cpu_utilization_high_threshold_percent}"
  cpu_utilization_high_statistic                            = "${var.cpu_utilization_high_statistic}"
  cpu_utilization_low_evaluation_periods                    = "${var.cpu_utilization_low_evaluation_periods}"
  cpu_utilization_low_period_seconds                        = "${var.cpu_utilization_low_period_seconds}"
  cpu_utilization_low_statistic                             = "${var.cpu_utilization_low_statistic}"
  cpu_utilization_low_threshold_percent                     = "${var.cpu_utilization_low_threshold_percent}"
  cfn_creation_policy_timeout                               = "${var.cfn_creation_policy_timeout}"
  cfn_creation_policy_min_successful_instances_percent      = "${var.cfn_creation_policy_min_successful_instances_percent}"
  #cfn_update_policy_min_successful_instances_percent        = "${var.cfn_update_policy_min_successful_instances_percent}"
  cfn_update_policy_max_batch_size                          = "${var.cfn_update_policy_max_batch_size}"
  cfn_update_policy_ignore_unmodified_group_size_properties = "${var.cfn_update_policy_ignore_unmodified_group_size_properties}"
  cfn_update_policy_pause_time                              = "${var.cfn_update_policy_pause_time}"
  cfn_update_policy_suspended_processes                     = "${var.cfn_update_policy_suspended_processes}"
  cfn_update_policy_wait_on_resource_signals                = "${var.cfn_update_policy_wait_on_resource_signals}"
  cfn_deletion_policy                                       = "${var.cfn_deletion_policy}"
  node_drain_enabled                                        = "${var.node_drain_enabled}"
}

data "template_file" "userdata" {
  count    = "${var.enabled == "true" ? 1 : 0}"
  template = "${file("${path.module}/userdata.tpl")}"

  vars {
    cluster_endpoint           = "${var.cluster_endpoint}"
    certificate_authority_data = "${var.cluster_certificate_authority_data}"
    cluster_name               = "${var.cluster_name}"
    bootstrap_extra_args       = "${var.bootstrap_extra_args}"
  }
}

data "template_file" "config_map_aws_auth" {
  count    = "${var.enabled == "true" ? 1 : 0}"
  template = "${file("${path.module}/config_map_aws_auth.tpl")}"

  vars {
    aws_iam_role_arn = "${join("", aws_iam_role.default.*.arn)}"
  }
}

data "template_file" "kube_node_drainer_asg_ds" {
  count    = "${var.enabled == "true" && var.node_drain_enabled == "true" ? 1 : 0}"
  template = "${file("${path.module}/kube-node-drainer-asg-ds.tpl")}"

  vars {
    hyperkubeimage = "${var.hyperkubeimage}"
    aws_cli_image  = "${var.aws_cli_image}"
    REGION         = "${var.region}"
  }

  depends_on = ["module.autoscale_group"]
}

data "template_file" "kube_node_drainer_asg_status_updater" {
  count    = "${var.enabled == "true" && var.node_drain_enabled == "true" ? 1 : 0}"
  template = "${file("${path.module}/kube-node-drainer-asg-status-updater.tpl")}"

  vars {
    hyperkubeimage   = "${var.hyperkubeimage}"
    aws_cli_image    = "${var.aws_cli_image}"
    REGION           = "${var.region}"
    aws_iam_role_arn = "${join("", aws_iam_role.default.*.arn)}"
    cluster_name     = "${var.cluster_name}"
  }

  depends_on = ["module.autoscale_group"]
}

data "template_file" "kube_rbac" {
  count    = "${var.enabled == "true" && var.node_drain_enabled == "true" ? 1 : 0}"
  template = "${file("${path.module}/kube-rbac.tpl")}"

  vars {}

  depends_on = ["module.autoscale_group"]
}
