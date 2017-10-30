output "vpc_id" {
    value = "${aws_vpc.default.id}"
}

output "public_subnet_ids" {
  value = ["${aws_subnet.subnet.*.id}"]
}