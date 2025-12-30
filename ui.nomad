job "ui" {
  datacenters = ["dev"]
  type = "service"

  group "ui" {
    count = 3

    network {
      mode = "bridge"
      port "http" {
        to = 80
      }
    }

    service {
      name = "ui"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.ui.rule=Host(`ui.dev.local`)",
        "traefik.http.services.ui.loadbalancer.server.port=80"
      ]
    }

    task "ui" {
      driver = "docker"

      config {
        image      = "ui:dev"
        force_pull = false
        ports      = ["http"]
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }

    spread {
      attribute = "${node.unique.id}"
    }
  }
}
