resource "aws_alb" "default" {
  name = "${var.app_name}"
  internal = false
  security_groups = ["${var.security_groups}"]
  subnets = ["${var.subnet_ids}"]

  ip_address_type = "ipv4"
  enable_deletion_protection = false
}

resource "aws_alb_target_group" "default" {
  name = "${var.app_name}"
  port = 80
  protocol = "HTTP"
  vpc_id = "${var.vpc_id}"

  stickiness {
      type = "lb_cookie"
      cookie_duration = "1200"
      enabled = true
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 5
    timeout = 3
    path = "/"
    protocol = "HTTP"
    port = "80"
    interval = 30
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = "${aws_alb.default.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.default.arn}"
    type             = "forward"
  }
}