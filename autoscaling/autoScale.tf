provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-1"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqTct2kzoI8GR008xizhsPfg+lbnZLWlxxSBP5nu7gm0KT3W3e+wdNzoQU21f6B/PW1YAVShJZP7I/OIXLQ82bW0PnFWxzXi+f9bz+ETmiIgKzaPOEP6W2IHyygHHc6Wy5OD6aLP5yjRJcvoKJXLp2C1wvviJjsvY8+c9g7Nk1F40/MSR4QqBE+mX4QgF1saTBKwLgOrLlqgYgrDnlmi+x4837f4W1BfPT/ruFGkqhRXG2IgonSEbNtL3XZ1tuzod7CCyjyKQ83vy8sXn/U/j3t3kId4lh5JlCPO+Q67aAK1c0oAvDos6JVtmofWT14Ud+2oOcD5x4Xi9i0Z5SzwXh andrew.loesch@C02Q9FEKG8WN-L"
}

# create a security group to expose web traffic ports to public
resource "aws_security_group" "web" {
  name        = "Web Traffic"
  description = "Allow all inbound traffic from http (80) and https (443)"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "web-traffic"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh" {
  name        = "ssh-traffic"
  description = "Allow all SSH traffic"
  vpc_id = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "default" {
    image_id = "${var.aws_ami}"
    instance_type = "${var.instance_type}"
    name = "${var.app_name}"
    key_name = "${var.aws_key_name}"
    security_groups = ["${aws_security_group.web.id}", "${aws_security_group.ssh.id}"]

    lifecycle {
      create_before_destroy = true
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install perl-Switch perl-DateTime perl-Sys-Syslog perl-LWP-Protocol-https -y
    curl http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip -O
    unzip CloudWatchMonitoringScripts-1.2.1.zip
    rm CloudWatchMonitoringScripts-1.2.1.zip
    cd aws-scripts-mon
    echo 'AWSAccessKeyId="${var.aws_access_key}"' >> aws.conf
    echo 'AWSSecretKey="${var.aws_secret_key}"' >> aws.conf
    (crontab -l ; echo "*/1 * * * * ~/aws-scripts-mon/mon-put-instance-data.pl --mem-used-incl-cache-buff --mem-util --disk-space-util --disk-path=/ --from-cron")| crontab -
    yum install -y docker
    service docker start
    usermod -a -G docker ec2-user
    docker run -p 80:80 -d ${var.docker_image}
    HEREDOC
}

resource "aws_autoscaling_group" "default" {
    name = "${var.app_name}-${var.app_version}"
    max_size = 50
    min_size = 2
    launch_configuration = "${aws_launch_configuration.default.name}"
    health_check_type = "ELB"
    load_balancers = ["${aws_elb.default.id}"]
    vpc_zone_identifier = ["${aws_subnet.us-west-1a-public.id}", "${aws_subnet.us-west-1b-public.id}"]
    termination_policies = ["OldestInstance"]

    lifecycle {
      create_before_destroy = true
    }

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
    evaluation_periods = "1"
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