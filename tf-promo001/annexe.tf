removed {
  from = docker_network.annexe

  lifecycle {
    destroy = false
  }
}
