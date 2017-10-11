resource "aws_launch_configuration" "default" {
    image_id = "${var.aws_ami}"
    instance_type = "${var.instance_type}"
    key_name = "${var.aws_key_name}"
    security_groups = ["${var.security_group_ids}"]
    iam_instance_profile = "${var.iam_instance_profile}"

    lifecycle { create_before_destroy = true }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y docker
    service docker start

    aws s3 cp --region ${var.region} s3://${var.app_env_var_bucket}/${var.app_env_var_filename} /etc/environment

    export AWS_ACCESS_KEY_ID=${var.aws_access_key}
    export AWS_SECRET_ACCESS_KEY=${var.aws_secret_key}
    mkdir logs
    eval "$(aws ecr get-login --no-include-email --region ${var.region})"

    docker run -d --name="cloudwatch-monitoring" 417834917721.dkr.ecr.us-west-1.amazonaws.com/cloudwatch-monitoring:autoscale
    docker run -v /logs:/logs -p 80:${var.docker_port} --env-file /etc/environment -d ${var.docker_image}
    docker run -v /logs:/tmp/clogs -e SUMO_COLLECTOR_NAME_PREFIX=" " -e SUMO_COLLECTOR_NAME="${var.sumo_collector_name}" -e SUMO_CLOBBER=true -d --name="sumo-logic-collector" sumologic/collector:latest-file ${var.sumo_access_id} ${var.sumo_access_key}
    HEREDOC
}

resource "aws_autoscaling_group" "default" {
    name = "${var.app_name}-${var.app_version}"
    max_size = "${var.max}"
    min_size = "${var.min}"
    min_elb_capacity = "${var.min}"
    launch_configuration = "${aws_launch_configuration.default.name}"
    health_check_type = "ELB"
    #load_balancers = ["${var.loadbalancer_id}"]
    target_group_arns = ["${var.loadbalancer_id}"]
    vpc_zone_identifier = ["${var.subnet_group_ids}"]
    termination_policies = ["OldestInstance"]

    lifecycle { create_before_destroy = true }

    tag {
        key = "Name"
        value = "${var.app_name}-${var.app_version}"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_policy" "scale-up" {
    name = "${var.app_name}-${var.app_version}-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.default.name}"
}

resource "aws_autoscaling_policy" "scale-down" {
    name = "${var.app_name}-${var.app_version}-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.default.name}"
}

resource "aws_cloudwatch_metric_alarm" "cpu-high" {
    alarm_name = "${var.app_name}-${var.app_version}-cpu-util-high"
    namespace = "AWS/EC2"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "CPUUtilization"
    period = "60"
    statistic = "Average"
    threshold = "10"
    alarm_description = "This metric monitors CPU for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-up.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}

resource "aws_cloudwatch_metric_alarm" "cpu-low" {
    alarm_name = "${var.app_name}-${var.app_version}-cpu-util-low"
    namespace = "AWS/EC2"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "15"
    metric_name = "CPUUtilization"
    period = "60"
    statistic = "Average"
    threshold = "2"
    alarm_description = "This metric monitors CPU for low utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-down.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}

resource "aws_cloudwatch_metric_alarm" "memory-high" {
    alarm_name = "${var.app_name}-${var.app_version}-mem-util-high"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "MemoryUtilization"
    namespace = "System/Linux"
    period = "60"
    statistic = "Average"
    threshold = "90"
    alarm_description = "This metric monitors ec2 memory for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-up.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}

resource "aws_cloudwatch_metric_alarm" "memory-low" {
    alarm_name = "${var.app_name}-${var.app_version}-mem-util-low"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "15"
    metric_name = "MemoryUtilization"
    namespace = "System/Linux"
    period = "60"
    statistic = "Average"
    threshold = "20"
    alarm_description = "This metric monitors ec2 memory for low utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.scale-down.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.default.name}"
    }
}