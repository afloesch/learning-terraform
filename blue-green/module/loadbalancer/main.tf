# Create a new load balancer
resource "aws_elb" "default" {
  name = "${var.app_name}"
  subnets = ["${var.subnet_ids}"]
  security_groups = ["${var.security_groups}"]

  #lifecycle { prevent_destroy = true }

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 5
    timeout = 3
    target = "HTTP:80/"
    interval = 30
  }

  cross_zone_load_balancing = true
  idle_timeout = 500
  connection_draining = true
  connection_draining_timeout = 1000
}

resource "aws_lb_cookie_stickiness_policy" "http" {
  name = "http-sticky-policy"
  load_balancer = "${aws_elb.default.id}"
  lb_port = 80
  cookie_expiration_period = 600
}