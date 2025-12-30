job "scheduler-api" {
  datacenters = ["dev"]
  type = "service"

  group "scheduler" {
    count = 2   # leader + standby

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "scheduler-api"
      port = "http"
    }

    task "scheduler" {
      driver = "docker"

      config {
        image      = "scheduler-api:dev"
        force_pull = false
        ports      = ["http"]
      }

      env {
        SPRING_PROFILES_ACTIVE = "dev"
        JAVA_TOOL_OPTIONS     = "-Xms256m -Xmx512m"
      }

      resources {
        cpu    = 400
        memory = 512
      }
    }

    spread {
      attribute = "${node.unique.id}"
    }
  }
}
