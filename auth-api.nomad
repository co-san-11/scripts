job "auth-api" {
  datacenters = ["dev"]
  type = "service"

  group "auth-api" {
    count = 3

    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
    }

    service {
      name = "auth-api"
      port = "http"

      check {
        type     = "http"
        path     = "/actuator/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "auth-api" {
      driver = "docker"

      config {
        image      = "auth-api:dev"
        force_pull = false
        ports      = ["http"]
      }

      env {
        SPRING_PROFILES_ACTIVE = "dev"
        SERVER_PORT           = "8080"
        JAVA_TOOL_OPTIONS     = "-Xms256m -Xmx512m"
      }

      resources {
        cpu    = 500
        memory = 768
      }
    }

    spread {
      attribute = "${node.unique.id}"
    }
  }
}
