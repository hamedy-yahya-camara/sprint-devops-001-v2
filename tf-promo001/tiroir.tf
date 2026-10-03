resource "docker_container" "tiroir" {
  name         = "tiroir-anis"
  image        = "nginx:1.27-alpine"
  network_mode = "promo001-anis"

  ports {
    internal = 80
    external = 8160
  }

  env = [
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "NGINX_VERSION=1.27.5",
    "PKG_RELEASE=1",
    "DYNPKG_RELEASE=1",
    "NJS_VERSION=0.8.10",
    "NJS_RELEASE=1",
  ]

  lifecycle {
    ignore_changes = [env, ports]
  }
}
