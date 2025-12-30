job "gateway" {
  datacenters = ["dev"]
  type = "service"

  group "gateway" {
    count = 3

    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
    }

    service {
      name = "gateway"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.gateway.rule=Host(`api.dev.local`)",
        "traefik.http.services.gateway.loadbalancer.server.port=8080"
      ]

      check {
        type     = "http"
        path     = "/actuator/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "gateway" {
      driver = "docker"

      config {
        image      = "gateway:dev"
        force_pull = false
        ports      = ["http"]
      }

      env {
        SPRING_PROFILES_ACTIVE = "dev"
        JAVA_TOOL_OPTIONS     = "-Xms256m -Xmx768m"
      }

      resources {
        cpu    = 800
        memory = 1024
      }
    }

    spread {
      attribute = "${node.unique.id}"
    }
  }
}
